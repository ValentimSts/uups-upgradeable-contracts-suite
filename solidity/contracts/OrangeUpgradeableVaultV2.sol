// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { OrangeUpgradeableVault } from "./OrangeUpgradeableVault.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title OrangeUpgradeableVaultV2
 * @notice Upgraded version of OrangeUpgradeableVault with additional features.
 *
 * @dev Version 2 adds:
 *      - Withdrawal fee system (configurable by owner)
 *      - Pause/unpause functionality for emergencies
 *      - Batch withdrawal capability
 *      - Fee collection for owner
 *
 *      Demonstrates safe upgrade patterns:
 *      - Inherits from V1 to preserve storage layout
 *      - New state variables added after V1's storage
 *      - Uses storage gap from V1 for new variables
 */
contract OrangeUpgradeableVaultV2 is OrangeUpgradeableVault, PausableUpgradeable {

    error FeeTooHigh();
    error ArrayLengthMismatch();
    error EmptyArray();
    error NoFeesToCollect();


    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesCollected(address indexed collector, uint256 amount);
    event BatchWithdrawn(address indexed user, uint256 totalAmount, uint256 feeAmount);


    uint256 public constant MAX_FEE_BPS = 1000;
    uint256 public constant BPS_DENOMINATOR = 10000;


    uint256 public withdrawalFeeBps;
    uint256 public accumulatedFees;


    uint256[46] private __gapV2;


    /**
     * @dev Reinitializes the contract for V2. Can only be called once during upgrade.
     * @param initialFeeBps Initial withdrawal fee in basis points
     */
    function initializeV2(uint256 initialFeeBps) external reinitializer(2) {
        if (initialFeeBps > MAX_FEE_BPS) revert FeeTooHigh();

        __Pausable_init();
        withdrawalFeeBps = initialFeeBps;
    }


    /**
     * @dev Withdraws ETH from the vault with fee deduction.
     * @param amount The gross amount to withdraw (fee deducted from this)
     */
    function withdraw(uint256 amount) external override nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroWithdrawal();
        if (balances[msg.sender] < amount) revert InsufficientBalance();

        uint256 fee = (amount * withdrawalFeeBps) / BPS_DENOMINATOR;
        uint256 netAmount = amount - fee;

        balances[msg.sender] -= amount;
        totalDeposits -= amount;
        accumulatedFees += fee;

        (bool success, ) = payable(msg.sender).call{value: netAmount}("");
        if (!success) revert ETHTransferFailed();

        emit Withdrawn(msg.sender, netAmount);
    }


    /**
     * @dev Withdraws all ETH from the vault for the sender with fee deduction.
     * @return netAmount The net amount withdrawn after fees
     */
    function withdrawAll() external override nonReentrant whenNotPaused returns (uint256 netAmount) {
        uint256 amount = balances[msg.sender];
        if (amount == 0) revert ZeroWithdrawal();

        uint256 fee = (amount * withdrawalFeeBps) / BPS_DENOMINATOR;
        netAmount = amount - fee;

        balances[msg.sender] = 0;
        totalDeposits -= amount;
        accumulatedFees += fee;

        (bool success, ) = payable(msg.sender).call{value: netAmount}("");
        if (!success) revert ETHTransferFailed();

        emit Withdrawn(msg.sender, netAmount);
    }


    /**
     * @dev Deposits ETH into the vault (pausable in V2).
     */
    function deposit() external payable override nonReentrant whenNotPaused {
        if (msg.value == 0) revert ZeroDeposit();

        balances[msg.sender] += msg.value;
        totalDeposits += msg.value;

        emit Deposited(msg.sender, msg.value);
    }


    /**
     * @dev Withdraws specific amounts to multiple recipients.
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to send to each recipient
     */
    function batchWithdraw(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external nonReentrant whenNotPaused {
        if (recipients.length != amounts.length) revert ArrayLengthMismatch();
        if (recipients.length == 0) revert EmptyArray();

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        if (balances[msg.sender] < totalAmount) revert InsufficientBalance();

        uint256 totalFee = (totalAmount * withdrawalFeeBps) / BPS_DENOMINATOR;

        balances[msg.sender] -= totalAmount;
        totalDeposits -= totalAmount;
        accumulatedFees += totalFee;

        // Distribute net amounts proportionally
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 fee = (amounts[i] * withdrawalFeeBps) / BPS_DENOMINATOR;
            uint256 netAmount = amounts[i] - fee;

            (bool success, ) = payable(recipients[i]).call{value: netAmount}("");
            if (!success) revert ETHTransferFailed();
        }

        emit BatchWithdrawn(msg.sender, totalAmount, totalFee);
    }


    /**
     * @dev Sets the withdrawal fee. Only callable by owner.
     * @param newFeeBps New fee in basis points
     */
    function setWithdrawalFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();

        emit FeeUpdated(withdrawalFeeBps, newFeeBps);
        withdrawalFeeBps = newFeeBps;
    }


    /**
     * @dev Collects accumulated fees. Only callable by owner.
     * @param to Address to receive fees
     */
    function collectFees(address to) external onlyOwner {
        uint256 fees = accumulatedFees;
        if (fees == 0) revert NoFeesToCollect();

        accumulatedFees = 0;

        (bool success, ) = payable(to).call{value: fees}("");
        if (!success) revert ETHTransferFailed();

        emit FeesCollected(to, fees);
    }


    /**
     * @dev Pauses all deposits and withdrawals. Only callable by owner.
     */
    function pause() external onlyOwner {
        _pause();
    }


    /**
     * @dev Unpauses all deposits and withdrawals. Only callable by owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }


    /**
     * @dev Calculates the net amount after fees.
     * @param grossAmount The gross amount before fees
     * @return netAmount The amount after fee deduction
     * @return feeAmount The fee amount
     */
    function calculateNetAmount(uint256 grossAmount) external view returns (uint256 netAmount, uint256 feeAmount) {
        feeAmount = (grossAmount * withdrawalFeeBps) / BPS_DENOMINATOR;
        netAmount = grossAmount - feeAmount;
    }


    /**
     * @dev Returns the contract version.
     * @return Version string
     */
    function version() external pure override returns (string memory) {
        return "2.0.0";
    }
}
