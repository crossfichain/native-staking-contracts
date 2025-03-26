// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../mocks/MockERC20.sol";
import {MockStakingOracle} from "../mocks/MockStakingOracle.sol";
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
    uint256 public constant APY = 100 * 1e16; // 100% with 18 decimals
    uint256 public constant UNBONDING_PERIOD = 14 days;
    
    function setUp() public {
        console.log("Starting E2E test setup");
        
        vm.startPrank(admin);
        
        // Deploy mock contracts
        xfi = new MockERC20("XFI", "XFI", 18);
        oracle = new MockStakingOracle();
        
        // Setup oracle values
        oracle.setCurrentAPY(APY);
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
        uint256 stakeAmount = 100 ether;
        uint256 user2StakeAmount = 50 ether;

        // Setup initial state
        oracle.setCurrentAPY(APY);
        oracle.setPrice(1e18);

        // User1 stakes XFI through manager
        vm.startPrank(user1);
        xfi.approve(address(manager), stakeAmount);
        uint256 shares = manager.stakeAPY(stakeAmount);
        assertGt(shares, 0, "User should receive vault shares");
        assertEq(vault.totalAssets(), stakeAmount, "Vault should hold XFI");
        vm.stopPrank();

        // Fast forward 180 days to accumulate rewards
        vm.warp(block.timestamp + 180 days);

        // Compound rewards
        vm.startPrank(compounder);
        uint256 rewardAmount = (stakeAmount * APY * 180 days) / (365 days * 10000); // Calculate rewards
        xfi.mint(compounder, rewardAmount);
        xfi.approve(address(vault), rewardAmount);
        vault.compoundRewards(rewardAmount);
        vm.stopPrank();

        // User2 stakes XFI through manager
        vm.startPrank(user2);
        xfi.approve(address(manager), user2StakeAmount);
        manager.stakeAPY(user2StakeAmount);
        vm.stopPrank();

        // Calculate expected rewards after 180 days with 100% APY
        // For 100% APY, after 180 days (half a year), we expect ~41% increase
        // Formula: (1 + 1)^(180/365) ? 1.41
        uint256 expectedMinimumAssets = stakeAmount * 141 / 100; // 41% increase

        // Set max liquidity percent to 100% for testing
        vm.startPrank(admin);
        vault.setMaxLiquidityPercent(10000); // 100%
        vm.stopPrank();

        // Request withdrawal through manager
        vm.startPrank(user1);
        vault.approve(address(manager), shares);
        uint256 assets = manager.withdrawAPY(shares);
        vm.stopPrank();

        // Since we set maxLiquidityPercent to 100%, withdrawal should be immediate
        assertGt(assets, stakeAmount, "Should get more than original stake due to rewards");
        assertGt(assets, expectedMinimumAssets, "Should get at least 41% more than staked");
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