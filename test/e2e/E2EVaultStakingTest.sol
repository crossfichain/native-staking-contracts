// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./E2ETestBase.sol";

/**
 * @title E2EVaultStakingTest
 * @dev E2E tests for vault (APY) staking operations
 */
contract E2EVaultStakingTest is E2ETestBase {
    function testFullStakingFlow() public {
        uint256 stakeAmount = 100 ether;

        // User1 stakes XFI through manager
        vm.startPrank(user1);
        xfi.approve(address(manager), stakeAmount);
        uint256 shares = manager.stakeAPY(stakeAmount);
        assertGt(shares, 0, "User should receive vault shares");
        assertEq(vault.totalAssets(), stakeAmount, "Vault should hold XFI");
        vm.stopPrank();

        // Record initial state
        uint256 initialPrice = vault.convertToAssets(1 ether);
        
        // Fast forward some time
        vm.warp(block.timestamp + 30 days);
        
        // Add rewards to the vault directly
        uint256 rewardAmount = 10 ether;
        xfi.mint(address(vault), rewardAmount);
        
        // Check that the price per share has increased
        uint256 newPrice = vault.convertToAssets(1 ether);
        assertGt(newPrice, initialPrice, "Price per share should increase after rewards");
        
        // Calculate what the full stakeAmount should now be worth
        uint256 expectedNewValue = vault.convertToAssets(shares);
        assertGt(expectedNewValue, stakeAmount, "Stake value should have increased");
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
        xfi.mint(compounder, rewardAmount);
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
        xfi.mint(compounder, rewardAmount);
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