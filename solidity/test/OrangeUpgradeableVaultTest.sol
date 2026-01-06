// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { OrangeUpgradeableVault } from "../contracts/OrangeUpgradeableVault.sol";
import { OrangeUpgradeableVaultV2 } from "../contracts/OrangeUpgradeableVaultV2.sol";

contract OrangeUpgradeableVaultTest is Test {
    OrangeUpgradeableVault public implementation;
    OrangeUpgradeableVault public vault;
    ERC1967Proxy public proxy;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    function setUp() public {
        // Deploy implementation
        implementation = new OrangeUpgradeableVault();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            OrangeUpgradeableVault.initialize.selector,
            owner
        );
        proxy = new ERC1967Proxy(address(implementation), initData);

        // Create interface to proxy
        vault = OrangeUpgradeableVault(payable(address(proxy)));

        // Fund test users
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    // Allow test contract to receive ETH
    receive() external payable {}

    // ============ Initialization Tests ============

    function test_Initialize_SetsOwner() public view {
        assertEq(vault.owner(), owner);
    }

    function test_Initialize_StartsWithZeroDeposits() public view {
        assertEq(vault.totalDeposits(), 0);
    }

    function test_Initialize_ReturnsCorrectVersion() public view {
        assertEq(vault.version(), "1.0.0");
    }

    function test_Initialize_CannotReinitialize() public {
        vm.expectRevert();
        vault.initialize(user1);
    }

    function test_Implementation_CannotBeInitialized() public {
        vm.expectRevert();
        implementation.initialize(user1);
    }

    // ============ Deposit Tests ============

    function test_Deposit_UpdatesBalance() public {
        uint256 amount = 1 ether;

        vm.prank(user1);
        vault.deposit{value: amount}();

        assertEq(vault.balanceOf(user1), amount);
        assertEq(vault.totalDeposits(), amount);
    }

    function test_Deposit_EmitsEvent() public {
        uint256 amount = 1 ether;

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit OrangeUpgradeableVault.Deposited(user1, amount);
        vault.deposit{value: amount}();
    }

    function test_Deposit_RevertsOnZero() public {
        vm.prank(user1);
        vm.expectRevert(OrangeUpgradeableVault.ZeroDeposit.selector);
        vault.deposit{value: 0}();
    }

    function test_Deposit_MultipleUsers() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.prank(user2);
        vault.deposit{value: 2 ether}();

        assertEq(vault.balanceOf(user1), 1 ether);
        assertEq(vault.balanceOf(user2), 2 ether);
        assertEq(vault.totalDeposits(), 3 ether);
    }

    function test_Deposit_ViaReceive() public {
        vm.prank(user1);
        (bool success, ) = address(vault).call{value: 1 ether}("");

        assertTrue(success);
        assertEq(vault.balanceOf(user1), 1 ether);
    }

    // ============ Withdraw Tests ============

    function test_Withdraw_UpdatesBalance() public {
        vm.prank(user1);
        vault.deposit{value: 2 ether}();

        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        vault.withdraw(1 ether);

        assertEq(vault.balanceOf(user1), 1 ether);
        assertEq(user1.balance, balanceBefore + 1 ether);
    }

    function test_Withdraw_EmitsEvent() public {
        vm.prank(user1);
        vault.deposit{value: 2 ether}();

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit OrangeUpgradeableVault.Withdrawn(user1, 1 ether);
        vault.withdraw(1 ether);
    }

    function test_Withdraw_RevertsOnZero() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.prank(user1);
        vm.expectRevert(OrangeUpgradeableVault.ZeroWithdrawal.selector);
        vault.withdraw(0);
    }

    function test_Withdraw_RevertsOnInsufficientBalance() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.prank(user1);
        vm.expectRevert(OrangeUpgradeableVault.InsufficientBalance.selector);
        vault.withdraw(2 ether);
    }

    // ============ WithdrawAll Tests ============

    function test_WithdrawAll_WithdrawsEntireBalance() public {
        vm.prank(user1);
        vault.deposit{value: 5 ether}();

        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        uint256 withdrawn = vault.withdrawAll();

        assertEq(withdrawn, 5 ether);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(user1.balance, balanceBefore + 5 ether);
    }

    function test_WithdrawAll_RevertsOnZeroBalance() public {
        vm.prank(user1);
        vm.expectRevert(OrangeUpgradeableVault.ZeroWithdrawal.selector);
        vault.withdrawAll();
    }

    // ============ Upgrade Authorization Tests ============

    function test_Upgrade_OnlyOwner() public {
        OrangeUpgradeableVault newImpl = new OrangeUpgradeableVault();

        vm.prank(user1);
        vm.expectRevert();
        vault.upgradeToAndCall(address(newImpl), "");
    }

    function test_Upgrade_OwnerCanUpgrade() public {
        OrangeUpgradeableVaultV2 newImpl = new OrangeUpgradeableVaultV2();

        // Should not revert
        vault.upgradeToAndCall(
            address(newImpl),
            abi.encodeWithSelector(OrangeUpgradeableVaultV2.initializeV2.selector, 100)
        );

        OrangeUpgradeableVaultV2 vaultV2 = OrangeUpgradeableVaultV2(payable(address(proxy)));
        assertEq(vaultV2.version(), "2.0.0");
    }

    // ============ Integration Tests ============

    function test_Integration_DepositWithdrawCycle() public {
        // User1 deposits
        vm.prank(user1);
        vault.deposit{value: 5 ether}();

        // User2 deposits
        vm.prank(user2);
        vault.deposit{value: 3 ether}();

        assertEq(vault.totalDeposits(), 8 ether);

        // User1 partial withdraw
        vm.prank(user1);
        vault.withdraw(2 ether);

        assertEq(vault.balanceOf(user1), 3 ether);
        assertEq(vault.totalDeposits(), 6 ether);

        // User2 withdraw all
        vm.prank(user2);
        vault.withdrawAll();

        assertEq(vault.balanceOf(user2), 0);
        assertEq(vault.totalDeposits(), 3 ether);
    }

    function test_Integration_ContractBalanceMatchesTotalDeposits() public {
        vm.prank(user1);
        vault.deposit{value: 5 ether}();

        vm.prank(user2);
        vault.deposit{value: 3 ether}();

        assertEq(address(vault).balance, vault.totalDeposits());

        vm.prank(user1);
        vault.withdraw(2 ether);

        assertEq(address(vault).balance, vault.totalDeposits());
    }
}
