// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { OrangeUpgradeableVault } from "../contracts/OrangeUpgradeableVault.sol";
import { OrangeUpgradeableVaultV2 } from "../contracts/OrangeUpgradeableVaultV2.sol";

contract OrangeUpgradeableVaultV2Test is Test {
    OrangeUpgradeableVault public implementationV1;
    OrangeUpgradeableVaultV2 public implementationV2;
    OrangeUpgradeableVaultV2 public vault;
    ERC1967Proxy public proxy;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    uint256 public constant INITIAL_FEE_BPS = 100; // 1%

    function setUp() public {
        // Deploy V1 implementation
        implementationV1 = new OrangeUpgradeableVault();

        // Deploy proxy with V1
        bytes memory initData = abi.encodeWithSelector(
            OrangeUpgradeableVault.initialize.selector,
            owner
        );
        proxy = new ERC1967Proxy(address(implementationV1), initData);

        // Deploy V2 implementation
        implementationV2 = new OrangeUpgradeableVaultV2();

        // Upgrade to V2
        OrangeUpgradeableVault(payable(address(proxy))).upgradeToAndCall(
            address(implementationV2),
            abi.encodeWithSelector(OrangeUpgradeableVaultV2.initializeV2.selector, INITIAL_FEE_BPS)
        );

        // Create interface to proxy
        vault = OrangeUpgradeableVaultV2(payable(address(proxy)));

        // Fund test users
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
    }

    // Allow test contract to receive ETH
    receive() external payable {}

    // ============ Initialization Tests ============

    function test_InitializeV2_SetsVersion() public view {
        assertEq(vault.version(), "2.0.0");
    }

    function test_InitializeV2_SetsFee() public view {
        assertEq(vault.withdrawalFeeBps(), INITIAL_FEE_BPS);
    }

    function test_InitializeV2_PreservesOwner() public view {
        assertEq(vault.owner(), owner);
    }

    function test_InitializeV2_RevertsOnHighFee() public {
        // Deploy fresh proxy with V1
        bytes memory initData = abi.encodeWithSelector(
            OrangeUpgradeableVault.initialize.selector,
            owner
        );
        ERC1967Proxy newProxy = new ERC1967Proxy(address(implementationV1), initData);

        // Try to upgrade with fee > MAX_FEE_BPS
        vm.expectRevert(OrangeUpgradeableVaultV2.FeeTooHigh.selector);
        OrangeUpgradeableVault(payable(address(newProxy))).upgradeToAndCall(
            address(implementationV2),
            abi.encodeWithSelector(OrangeUpgradeableVaultV2.initializeV2.selector, 1001)
        );
    }

    // ============ Upgrade Preservation Tests ============

    function test_Upgrade_PreservesBalances() public {
        // Setup: Deploy V1, deposit, then upgrade
        bytes memory initData = abi.encodeWithSelector(
            OrangeUpgradeableVault.initialize.selector,
            owner
        );
        ERC1967Proxy newProxy = new ERC1967Proxy(address(implementationV1), initData);
        OrangeUpgradeableVault vaultV1 = OrangeUpgradeableVault(payable(address(newProxy)));

        // Deposit as user1
        vm.prank(user1);
        vaultV1.deposit{value: 5 ether}();

        uint256 balanceBefore = vaultV1.balanceOf(user1);
        uint256 totalBefore = vaultV1.totalDeposits();

        // Upgrade to V2
        vaultV1.upgradeToAndCall(
            address(implementationV2),
            abi.encodeWithSelector(OrangeUpgradeableVaultV2.initializeV2.selector, 100)
        );

        OrangeUpgradeableVaultV2 vaultV2 = OrangeUpgradeableVaultV2(payable(address(newProxy)));

        // Verify balances preserved
        assertEq(vaultV2.balanceOf(user1), balanceBefore);
        assertEq(vaultV2.totalDeposits(), totalBefore);
    }

    // ============ Fee System Tests ============

    function test_Withdraw_DeductsFee() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        vault.withdraw(10 ether);

        // Fee is 1%, so user receives 9.9 ETH
        uint256 expectedNet = 10 ether - (10 ether * INITIAL_FEE_BPS / 10000);
        assertEq(user1.balance, balanceBefore + expectedNet);
        assertEq(vault.accumulatedFees(), 10 ether * INITIAL_FEE_BPS / 10000);
    }

    function test_WithdrawAll_DeductsFee() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        uint256 netAmount = vault.withdrawAll();

        uint256 expectedNet = 10 ether - (10 ether * INITIAL_FEE_BPS / 10000);
        assertEq(netAmount, expectedNet);
        assertEq(user1.balance, balanceBefore + expectedNet);
    }

    function test_CalculateNetAmount_ReturnsCorrectValues() public view {
        (uint256 net, uint256 fee) = vault.calculateNetAmount(10 ether);

        assertEq(fee, 10 ether * INITIAL_FEE_BPS / 10000);
        assertEq(net, 10 ether - fee);
    }

    function test_SetWithdrawalFee_UpdatesFee() public {
        uint256 newFee = 200; // 2%

        vm.expectEmit(false, false, false, true);
        emit OrangeUpgradeableVaultV2.FeeUpdated(INITIAL_FEE_BPS, newFee);
        vault.setWithdrawalFee(newFee);

        assertEq(vault.withdrawalFeeBps(), newFee);
    }

    function test_SetWithdrawalFee_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setWithdrawalFee(200);
    }

    function test_SetWithdrawalFee_RevertsOnHighFee() public {
        vm.expectRevert(OrangeUpgradeableVaultV2.FeeTooHigh.selector);
        vault.setWithdrawalFee(1001);
    }

    // ============ Fee Collection Tests ============

    function test_CollectFees_TransfersFees() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        vm.prank(user1);
        vault.withdraw(10 ether);

        uint256 fees = vault.accumulatedFees();
        uint256 ownerBalanceBefore = owner.balance;

        vm.expectEmit(true, false, false, true);
        emit OrangeUpgradeableVaultV2.FeesCollected(owner, fees);
        vault.collectFees(owner);

        assertEq(owner.balance, ownerBalanceBefore + fees);
        assertEq(vault.accumulatedFees(), 0);
    }

    function test_CollectFees_OnlyOwner() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        vm.prank(user1);
        vault.withdraw(10 ether);

        vm.prank(user1);
        vm.expectRevert();
        vault.collectFees(user1);
    }

    function test_CollectFees_RevertsOnZeroFees() public {
        vm.expectRevert(OrangeUpgradeableVaultV2.NoFeesToCollect.selector);
        vault.collectFees(owner);
    }

    // ============ Pause Tests ============

    function test_Pause_BlocksDeposits() public {
        vault.pause();

        vm.prank(user1);
        vm.expectRevert();
        vault.deposit{value: 1 ether}();
    }

    function test_Pause_BlocksWithdrawals() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vault.pause();

        vm.prank(user1);
        vm.expectRevert();
        vault.withdraw(1 ether);
    }

    function test_Unpause_AllowsOperations() public {
        vault.pause();
        vault.unpause();

        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        assertEq(vault.balanceOf(user1), 1 ether);
    }

    function test_Pause_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.pause();
    }

    function test_Unpause_OnlyOwner() public {
        vault.pause();

        vm.prank(user1);
        vm.expectRevert();
        vault.unpause();
    }

    // ============ Batch Withdraw Tests ============

    function test_BatchWithdraw_SendsToMultipleRecipients() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        address[] memory recipients = new address[](2);
        recipients[0] = user2;
        recipients[1] = user3;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 3 ether;
        amounts[1] = 2 ether;

        uint256 user2Before = user2.balance;
        uint256 user3Before = user3.balance;

        vm.prank(user1);
        vault.batchWithdraw(recipients, amounts);

        // Each receives amount minus 1% fee
        uint256 net2 = 3 ether - (3 ether * INITIAL_FEE_BPS / 10000);
        uint256 net3 = 2 ether - (2 ether * INITIAL_FEE_BPS / 10000);

        assertEq(user2.balance, user2Before + net2);
        assertEq(user3.balance, user3Before + net3);
    }

    function test_BatchWithdraw_EmitsEvent() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        address[] memory recipients = new address[](1);
        recipients[0] = user2;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        uint256 totalFee = 5 ether * INITIAL_FEE_BPS / 10000;

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit OrangeUpgradeableVaultV2.BatchWithdrawn(user1, 5 ether, totalFee);
        vault.batchWithdraw(recipients, amounts);
    }

    function test_BatchWithdraw_RevertsOnArrayMismatch() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        address[] memory recipients = new address[](2);
        recipients[0] = user2;
        recipients[1] = user3;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        vm.prank(user1);
        vm.expectRevert(OrangeUpgradeableVaultV2.ArrayLengthMismatch.selector);
        vault.batchWithdraw(recipients, amounts);
    }

    function test_BatchWithdraw_RevertsOnEmptyArray() public {
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(user1);
        vm.expectRevert(OrangeUpgradeableVaultV2.EmptyArray.selector);
        vault.batchWithdraw(recipients, amounts);
    }

    function test_BatchWithdraw_RevertsOnInsufficientBalance() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        address[] memory recipients = new address[](1);
        recipients[0] = user2;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        vm.prank(user1);
        vm.expectRevert(OrangeUpgradeableVault.InsufficientBalance.selector);
        vault.batchWithdraw(recipients, amounts);
    }

    // ============ Integration Tests ============

    function test_Integration_FullLifecycle() public {
        // Users deposit
        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        vm.prank(user2);
        vault.deposit{value: 5 ether}();

        assertEq(vault.totalDeposits(), 15 ether);

        // User1 withdraws with fee
        vm.prank(user1);
        vault.withdraw(5 ether);

        // User2 batch withdraws
        address[] memory recipients = new address[](1);
        recipients[0] = user3;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2 ether;

        vm.prank(user2);
        vault.batchWithdraw(recipients, amounts);

        // Owner collects fees
        uint256 fees = vault.accumulatedFees();
        assertGt(fees, 0);

        vault.collectFees(owner);
        assertEq(vault.accumulatedFees(), 0);
    }

    function test_Integration_ZeroFeeMode() public {
        // Set fee to 0
        vault.setWithdrawalFee(0);

        vm.prank(user1);
        vault.deposit{value: 10 ether}();

        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        vault.withdraw(10 ether);

        // No fee deducted
        assertEq(user1.balance, balanceBefore + 10 ether);
        assertEq(vault.accumulatedFees(), 0);
    }
}
