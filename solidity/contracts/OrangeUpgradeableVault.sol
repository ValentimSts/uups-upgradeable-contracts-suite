// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title OrangeUpgradeableVault
 * @notice UUPS upgradeable ETH vault with deposit and withdrawal functionality.
 *
 * @dev This is Version 1 of the vault contract demonstrating:
 *      - UUPS proxy pattern for upgradeability
 *      - Initializer instead of constructor
 *      - Storage gap for future upgrades
 *      - Basic deposit/withdraw operations
 *
 *      The contract can be upgraded to V2 which adds fee collection,
 *      pause functionality, and batch operations.
 */
contract OrangeUpgradeableVault is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    error ZeroDeposit();
    error ZeroWithdrawal();
    error InsufficientBalance();
    error ETHTransferFailed();

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    mapping(address => uint256) public balances;
    uint256 public totalDeposits;


    constructor() {
        _disableInitializers();
    }


    /**
     * @dev Initializes the vault contract. Replaces constructor for upgradeable contracts.
     * @param owner_ The address that will own the contract
     */
    function initialize(address owner_) external initializer {
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }


    /**
     * @dev Deposits ETH into the vault. Updates the sender's balance and total deposits.
     */
    function deposit() external payable virtual nonReentrant {
        if (msg.value == 0) revert ZeroDeposit();

        balances[msg.sender] += msg.value;
        totalDeposits += msg.value;

        emit Deposited(msg.sender, msg.value);
    }


    /**
     * @dev Withdraws ETH from the vault.
     * @param amount The amount of ETH to withdraw
     */
    function withdraw(uint256 amount) external virtual nonReentrant {
        if (amount == 0) revert ZeroWithdrawal();
        if (balances[msg.sender] < amount) revert InsufficientBalance();

        balances[msg.sender] -= amount;
        totalDeposits -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        emit Withdrawn(msg.sender, amount);
    }


    /**
     * @dev Withdraws all ETH from the vault for the sender.
     * @return amount The amount of ETH withdrawn
     */
    function withdrawAll() external virtual nonReentrant returns (uint256 amount) {
        amount = balances[msg.sender];
        if (amount == 0) revert ZeroWithdrawal();

        balances[msg.sender] = 0;
        totalDeposits -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        emit Withdrawn(msg.sender, amount);
    }


    /**
     * @dev Returns the balance of a specific user.
     * @param user The address to query
     * @return The user's balance in wei
     */
    function balanceOf(address user) external view returns (uint256) {
        return balances[user];
    }


    /**
     * @dev Returns the contract version.
     * @return Version string
     */
    function version() external pure virtual returns (string memory) {
        return "1.0.0";
    }


    /**
     * @dev Authorizes contract upgrades. Only owner can upgrade.
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}


    receive() external payable {
        if (msg.value > 0) {
            balances[msg.sender] += msg.value;
            totalDeposits += msg.value;
            emit Deposited(msg.sender, msg.value);
        }
    }
}
