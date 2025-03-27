// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/core/NativeStakingVault.sol";
import "../../src/interfaces/IOracle.sol";
import {INativeStakingVault} from "../../src/interfaces/INativeStakingVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockStakingOracle} from "../mocks/MockStakingOracle.sol";

contract NativeStakingVaultTest is Test {
    MockERC20 public xfi;
    MockStakingOracle public oracle;
    NativeStakingVault public vault;
    
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    address public constant COMPOUNDER = address(0x3);
    
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant DEPOSIT_AMOUNT = 100 ether;
    uint256 public constant UNBONDING_PERIOD = 14 days;
    
    function setUp() public {
        vm.startPrank(ADMIN);
        
        // Deploy mock contracts
        xfi = new MockERC20("XFI", "XFI", 18);
        oracle = new MockStakingOracle();
        
        // Setup oracle values
        oracle.setCurrentAPY(100 * 1e16); // 100% with 18 decimals
        oracle.setUnbondingPeriod(UNBONDING_PERIOD);
        
        // Deploy vault
        vault = new NativeStakingVault();
        vault.initialize(
            address(xfi),
            address(oracle),
            "XFI Staking Vault",
            "xXFI"
        );
        
        // Setup roles
        vault.grantRole(vault.COMPOUNDER_ROLE(), COMPOUNDER);
        
        // Give users some XFI
        xfi.mint(USER, INITIAL_BALANCE);
        xfi.mint(COMPOUNDER, INITIAL_BALANCE);
        
        vm.stopPrank();
    }
    
    function testDeposit() public {
        vm.startPrank(USER);
        xfi.approve(address(vault), DEPOSIT_AMOUNT);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, USER);
        vm.stopPrank();
        
        assertEq(shares, DEPOSIT_AMOUNT); // 1:1 ratio initially
        assertEq(vault.balanceOf(USER), DEPOSIT_AMOUNT);
        assertEq(xfi.balanceOf(address(vault)), DEPOSIT_AMOUNT);
    }
    
    function testWithdraw() public {
        // First deposit
        vm.startPrank(USER);
        xfi.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, USER);
        
        // Then withdraw
        vm.startPrank(USER);
        uint256 assets = vault.withdraw(DEPOSIT_AMOUNT, USER, USER);
        vm.stopPrank();
        
        assertEq(assets, DEPOSIT_AMOUNT);
        assertEq(vault.balanceOf(USER), 0);
        assertEq(xfi.balanceOf(USER), INITIAL_BALANCE);
    }
    
    function testRequestWithdrawal() public {
        // First deposit
        vm.startPrank(USER);
        xfi.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, USER);
        
        // Request withdrawal
        bytes memory requestId = vault.requestWithdrawal(DEPOSIT_AMOUNT, USER, USER);
        vm.stopPrank();
        
        // Check withdrawal request
        INativeStakingVault.WithdrawalRequest[] memory requests = vault.getUserWithdrawalRequests(USER);
        assertEq(requests.length, 1);
        assertEq(requests[0].assets, DEPOSIT_AMOUNT);
        assertEq(requests[0].owner, USER);
        assertEq(requests[0].completed, false);
        assertEq(requests[0].unlockTime, block.timestamp + UNBONDING_PERIOD);
    }
    
    function testClaimWithdrawal() public {
        // Setup withdrawal request
        vm.startPrank(USER);
        xfi.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, USER);
        bytes memory requestId = vault.requestWithdrawal(DEPOSIT_AMOUNT, USER, USER);
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);
        
        // Claim withdrawal
        vm.prank(USER);
        uint256 assets = vault.claimWithdrawal(requestId);
        
        assertEq(assets, DEPOSIT_AMOUNT);
        assertEq(xfi.balanceOf(USER), INITIAL_BALANCE);
    }
    
    function testCompound() public {
        // Setup initial deposit
        vm.startPrank(USER);
        xfi.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, USER);
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + 365 days);
        
        // Add rewards
        uint256 rewardAmount = 10 ether;
        xfi.mint(COMPOUNDER, rewardAmount);
        
        // Compound rewards
        vm.startPrank(COMPOUNDER);
        xfi.approve(address(vault), rewardAmount);
        bool success = vault.compound();
        vm.stopPrank();
        
        assertTrue(success);
        assertGt(vault.totalAssets(), DEPOSIT_AMOUNT, "Total assets should increase after compounding");
    }
    
    function testCompoundRewards() public {
        uint256 rewardAmount = 10 ether;
        
        // Setup rewards
        xfi.mint(COMPOUNDER, rewardAmount);
        vm.startPrank(COMPOUNDER);
        xfi.approve(address(vault), rewardAmount);
        bool success = vault.compoundRewards(rewardAmount);
        vm.stopPrank();
        
        assertTrue(success);
        assertEq(xfi.balanceOf(address(vault)), rewardAmount);
    }
    
    function testPauseUnpause() public {
        vm.startPrank(ADMIN);
        vault.pause();
        assertTrue(vault.paused());
        
        vault.unpause();
        assertFalse(vault.paused());
        vm.stopPrank();
    }
    
    function testMaxLiquidityPercent() public {
        vm.startPrank(ADMIN);
        vault.setMaxLiquidityPercent(2000); // 20%
        assertEq(vault.maxLiquidityPercent(), 2000);
        vm.stopPrank();
    }
    
    function testMinWithdrawalAmount() public {
        vm.startPrank(ADMIN);
        vault.setMinWithdrawalAmount(1 ether);
        assertEq(vault.minWithdrawalAmount(), 1 ether);
        vm.stopPrank();
    }
    
    function testFailDepositWhenPaused() public {
        vm.startPrank(ADMIN);
        vault.pause();
        vm.stopPrank();
        
        vm.startPrank(USER);
        xfi.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, USER);
    }
    
    function testFailWithdrawBelowMinAmount() public {
        vm.startPrank(USER);
        xfi.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, USER);
        vault.withdraw(0.05 ether, USER, USER); // Below min withdrawal amount
    }
    
    function testFailCompoundWithoutRole() public {
        vm.prank(USER);
        vault.compound();
    }
    
    function testFailSetMaxLiquidityPercentAboveMax() public {
        vm.startPrank(ADMIN);
        vault.setMaxLiquidityPercent(10001); // Above 100%
    }
} 