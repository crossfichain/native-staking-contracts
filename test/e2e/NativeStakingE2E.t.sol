// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../mocks/MockERC20.sol";
import {MockStakingOracle} from "../mocks/MockOracle.sol";
import "../../src/core/NativeStakingVault.sol";
import "../../src/core/NativeStakingManager.sol";

/**
 * @title NativeStakingE2ETest
 * @dev Comprehensive end-to-end test for the Native Staking system
 * 
 * Note: This test focuses on the basic functionality of the system.
 * The unstaking tests need further refinement to properly track request IDs
 * and handle the unstaking freeze period.
 */
contract NativeStakingE2ETest is Test {
    // System contracts
    MockStakingOracle public oracle;
    MockERC20 public xfi;
    NativeStakingVault public vault;
    NativeStakingManager public manager;
    
    // Test accounts
    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public compounder = address(0x4);
    
    // Test constants
    string public constant VALIDATOR_ID = "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant APY = 10000; // 100% in basis points
    uint256 public constant UNBONDING_PERIOD = 14 days;
    
    function setUp() public {
        console.log("Starting E2E test setup");
        
        vm.startPrank(admin);
        
        // Deploy mock contracts
        xfi = new MockERC20("XFI", "XFI", 18);
        oracle = new MockStakingOracle();
        
        // Setup oracle values
        oracle.setAPY(APY);
        oracle.setUnbondingPeriod(UNBONDING_PERIOD);
        oracle.setPrice(1e18); // Set XFI price to 1 USD
        
        // Deploy vault
        vault = new NativeStakingVault();
        vault.initialize(
            address(xfi),
            address(oracle),
            "XFI Staking Vault",
            "xXFI"
        );
        
        // Deploy manager
        manager = new NativeStakingManager();
        manager.initialize(
            address(0), // No APR contract for this test
            address(vault),
            address(xfi),
            address(oracle),
            false, // Do not enforce minimum amounts for tests
            0, // No initial freeze time
            50 ether, // Min stake amount
            10 ether, // Min unstake amount
            1 ether // Min reward claim amount
        );
        
        // Setup roles
        vault.grantRole(vault.STAKING_MANAGER_ROLE(), address(manager));
        vault.grantRole(vault.COMPOUNDER_ROLE(), compounder);
        
        // Give users some XFI
        xfi.mint(user1, INITIAL_BALANCE);
        xfi.mint(user2, INITIAL_BALANCE);
        xfi.mint(compounder, INITIAL_BALANCE);
        
        vm.stopPrank();
        
        console.log("E2E test setup completed");
    }
    
    function testFullStakingFlow() public {
        console.log("Testing full staking flow");
        
        uint256 stakeAmount = 100 ether;
        
        // User1 stakes XFI
        vm.startPrank(user1);
        xfi.approve(address(manager), stakeAmount);
        uint256 shares = manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        assertGt(shares, 0, "Should receive vault shares");
        assertEq(vault.balanceOf(user1), shares, "User should own the shares");
        assertEq(xfi.balanceOf(address(vault)), stakeAmount, "Vault should hold the XFI");
        
        // Fast forward 6 months and compound rewards
        vm.warp(block.timestamp + 180 days);
        
        // Add some rewards to simulate appreciation
        vm.startPrank(compounder);
        uint256 rewardAmount = 10 ether;
        xfi.mint(compounder, rewardAmount); // Mint some rewards
        xfi.approve(address(vault), rewardAmount);
        vault.compoundRewards(rewardAmount);
        vm.stopPrank();
        
        // User2 stakes XFI
        vm.startPrank(user2);
        xfi.approve(address(manager), stakeAmount);
        uint256 shares2 = manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        assertGt(shares2, 0, "User2 should receive vault shares");
        assertLt(shares2, shares, "User2 should get fewer shares due to appreciation");
        
        // User1 requests withdrawal
        vm.startPrank(user1);
        uint256 requestId = vault.requestWithdrawal(shares, user1, user1);
        vm.stopPrank();
        
        assertGt(requestId, 0, "Should get valid request ID");
        
        // Fast forward through unbonding period
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);
        
        // User1 claims withdrawal
        vm.startPrank(user1);
        uint256 assets = vault.claimWithdrawal(requestId);
        vm.stopPrank();
        
        // Calculate expected assets (original stake + proportional rewards)
        uint256 totalAssets = stakeAmount + rewardAmount;
        uint256 expectedAssets = stakeAmount + rewardAmount; // User1 gets all rewards since they were the only staker
        
        assertGt(assets, stakeAmount, "Should get more than original stake amount back due to rewards");
        assertEq(assets, expectedAssets, "Should get original stake plus all rewards");
        assertEq(xfi.balanceOf(user1), INITIAL_BALANCE - stakeAmount + assets, "User should get XFI back with rewards");
    }
    
    function testCompoundingRewards() public {
        uint256 stakeAmount = 1000 ether;
        uint256 rewardAmount = 100 ether;
        
        // User1 stakes XFI
        vm.startPrank(user1);
        xfi.approve(address(manager), stakeAmount);
        manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        // Add rewards
        vm.startPrank(compounder);
        xfi.approve(address(vault), rewardAmount);
        vault.compoundRewards(rewardAmount);
        vm.stopPrank();
        
        // Check total assets
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, stakeAmount + rewardAmount, "Total assets should include rewards");
        
        // User1 withdraws everything
        vm.startPrank(admin);
        vault.setMaxLiquidityPercent(10000); // 100% for testing
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 shares = vault.balanceOf(user1);
        uint256 assets = vault.redeem(shares, user1, user1);
        vm.stopPrank();
        
        assertGt(assets, stakeAmount, "Should get more than original stake due to rewards");
    }
    
    function testMultipleUsersWithRewards() public {
        uint256 stakeAmount = 1000 ether;
        uint256 rewardAmount = 100 ether;
        
        // User1 stakes XFI
        vm.startPrank(user1);
        xfi.approve(address(manager), stakeAmount);
        uint256 shares1 = manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        // User2 stakes XFI
        vm.startPrank(user2);
        xfi.approve(address(manager), stakeAmount);
        uint256 shares2 = manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        // Add rewards
        vm.startPrank(compounder);
        xfi.approve(address(vault), rewardAmount);
        vault.compoundRewards(rewardAmount);
        vm.stopPrank();
        
        // Check total assets
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, stakeAmount * 2 + rewardAmount, "Total assets should include both stakes and rewards");
        
        // Both users withdraw everything
        vm.startPrank(admin);
        vault.setMaxLiquidityPercent(10000); // 100% for testing
        vm.stopPrank();
        
        // User1 withdraws
        vm.startPrank(user1);
        uint256 assets1 = vault.redeem(shares1, user1, user1);
        vm.stopPrank();
        
        // User2 withdraws
        vm.startPrank(user2);
        uint256 assets2 = vault.redeem(shares2, user2, user2);
        vm.stopPrank();
        
        // Both users should get their fair share of rewards
        assertGt(assets1, stakeAmount, "User1 should get more than original stake due to rewards");
        assertGt(assets2, stakeAmount, "User2 should get more than original stake due to rewards");
        
        // Allow for small rounding differences (1 wei)
        uint256 diff = assets1 > assets2 ? assets1 - assets2 : assets2 - assets1;
        assertLe(diff, 1, "Both users should get equal rewards (within 1 wei)");
    }
} 