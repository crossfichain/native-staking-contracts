// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/NativeStakingVault.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockStakingOracle.sol";
import {INativeStakingVault} from "../../src/interfaces/INativeStakingVault.sol";

contract NativeStakingVaultTest is Test {
    // Test constants
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    address public constant COMPOUNDER = address(0x3);
    
    // Contracts
    MockERC20 public xfi;
    MockStakingOracle public oracle;
    NativeStakingVault public vault;
    
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant DEPOSIT_AMOUNT = 100 ether;
    uint256 public constant APY = 1000; // 10% in basis points
    uint256 public constant UNBONDING_PERIOD = 7 days;
    
    function setUp() public {
        // Deploy mock contracts
        xfi = new MockERC20("XFI", "XFI", 18);
        oracle = new MockStakingOracle();
        
        // Deploy vault
        vault = new NativeStakingVault();
        
        // Initialize vault with admin as msg.sender
        vm.startPrank(ADMIN);
        vault.initialize(
            address(xfi),
            address(oracle),
            "XFI Staking Vault",
            "xXFI"
        );
        
        // Setup roles
        vault.grantRole(vault.COMPOUNDER_ROLE(), COMPOUNDER);
        vm.stopPrank();
        
        // Setup initial balances
        xfi.mint(USER, INITIAL_BALANCE);
        
        // Setup oracle values
        oracle.setAPY(APY);
        oracle.setUnbondingPeriod(UNBONDING_PERIOD);
        oracle.setPrice(1e18); // Set XFI price to 1 USD
    }
    
    function testInitialization() public {
        assertEq(vault.name(), "XFI Staking Vault");
        assertEq(vault.symbol(), "xXFI");
        assertEq(vault.decimals(), 18);
        assertEq(vault.asset(), address(xfi));
        assertEq(vault.maxLiquidityPercent(), 1000); // 10%
        assertEq(vault.minWithdrawalAmount(), 0.1 ether);
    }
    
    function testDeposit() public {
        vm.startPrank(USER);
        xfi.approve(address(vault), DEPOSIT_AMOUNT);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, USER);
        vm.stopPrank();
        
        assertEq(vault.balanceOf(USER), shares);
        assertEq(xfi.balanceOf(address(vault)), DEPOSIT_AMOUNT);
    }
    
    function testWithdraw() public {
        // First deposit
        vm.startPrank(USER);
        xfi.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, USER);
        
        // Set max liquidity percent to 100% for testing
        vm.stopPrank();
        vm.startPrank(ADMIN);
        vault.setMaxLiquidityPercent(10000); // 100%
        vm.stopPrank();
        
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
        uint256 requestId = vault.requestWithdrawal(DEPOSIT_AMOUNT, USER, USER);
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
        uint256 requestId = vault.requestWithdrawal(DEPOSIT_AMOUNT, USER, USER);
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