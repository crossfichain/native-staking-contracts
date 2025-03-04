// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./APRStakingBase.t.sol";

/**
 * @title APRStakingIntegrationTest
 * @dev Integration tests for the APR staking flow
 * Tests multiple contracts working together to handle full user journeys
 */
contract APRStakingIntegrationTest is APRStakingBaseTest {
    // Constants for testing
    string constant VALIDATOR_1 = "validator1";
    string constant VALIDATOR_2 = "validator2";
    
    function testCompleteStakingJourney() public {
        // Starting balances
        uint256 user1InitialBalance = user1.balance;
        
        // Step 1: Initial stake
        uint256 stakeAmount = 50 ether;
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_1);
        
        // Verify stake
        assertEq(nativeStaking.getTotalStaked(user1), stakeAmount);
        assertEq(user1.balance, user1InitialBalance - stakeAmount);
        
        // Step 2: Wait and accrue rewards
        skip(30 days);
        
        // Step 3: Add more to stake
        uint256 additionalStake = 25 ether;
        vm.prank(user1);
        stakingManager.stakeAPR{value: additionalStake}(additionalStake, VALIDATOR_2);
        
        // Total staked should increase
        assertEq(nativeStaking.getTotalStaked(user1), stakeAmount + additionalStake);
        
        // Step 4: Wait more time for rewards to accrue
        skip(60 days);
        
        // Step 5: Request partial unstake
        uint256 unstakeAmount = 15 ether;
        vm.prank(user1);
        uint256 requestId = stakingManager.unstakeAPR(unstakeAmount, VALIDATOR_1);
        
        // Remaining staked amount should be reduced
        assertEq(nativeStaking.getTotalStaked(user1), stakeAmount + additionalStake - unstakeAmount);
        
        // Step 6: Wait for unbonding period
        skip(UNBONDING_PERIOD + 1);
        
        // Step 7: Claim unstake
        vm.prank(user1);
        uint256 claimedAmount = stakingManager.claimUnstakeAPR(requestId);
        assertEq(claimedAmount, unstakeAmount);
        
        // Step 8: Wait more time
        skip(90 days);
        
        // Step 9: Claim rewards
        vm.prank(user1);
        uint256 rewards = stakingManager.claimRewardsAPR();
        
        // Should receive rewards
        assertGt(rewards, 0);
        
        // Step 10: Request unstake for remaining amount
        uint256 remainingStake = nativeStaking.getTotalStaked(user1);
        vm.prank(user1);
        uint256 finalRequestId = stakingManager.unstakeAPR(remainingStake, VALIDATOR_2);
        
        // Wait for unbonding period
        skip(UNBONDING_PERIOD + 1);
        
        // Step 11: Claim final unstake
        vm.prank(user1);
        uint256 finalClaimed = stakingManager.claimUnstakeAPR(finalRequestId);
        assertEq(finalClaimed, remainingStake);
        
        // Final staked amount should be 0
        assertEq(nativeStaking.getTotalStaked(user1), 0);
        
        // User should have received all funds back plus rewards
        uint256 expectedBalance = user1InitialBalance + rewards;
        assertApproxEqAbs(user1.balance, expectedBalance, 0.01 ether);
    }
    
    function testMultiUserConcurrentStaking() public {
        // Initial stake by user1
        vm.prank(user1);
        stakingManager.stakeAPR{value: 50 ether}(50 ether, VALIDATOR_1);
        
        // Skip time
        skip(30 days);
        
        // User2 stakes
        vm.prank(user2);
        stakingManager.stakeAPR{value: 100 ether}(100 ether, VALIDATOR_2);
        
        // Skip time
        skip(45 days);
        
        // User3 stakes
        vm.prank(user3);
        stakingManager.stakeAPR{value: 75 ether}(75 ether, VALIDATOR_1);
        
        // Skip time
        skip(60 days);
        
        // User1 unstakes partially
        vm.prank(user1);
        uint256 request1 = stakingManager.unstakeAPR(20 ether, VALIDATOR_1);
        
        // User3 unstakes partially
        vm.prank(user3);
        uint256 request3 = stakingManager.unstakeAPR(25 ether, VALIDATOR_1);
        
        // Skip unbonding period
        skip(UNBONDING_PERIOD + 1);
        
        // User1 claims unstake
        vm.prank(user1);
        stakingManager.claimUnstakeAPR(request1);
        
        // User3 claims unstake
        vm.prank(user3);
        stakingManager.claimUnstakeAPR(request3);
        
        // Skip more time
        skip(30 days);
        
        // All users claim rewards
        vm.prank(user1);
        uint256 rewards1 = stakingManager.claimRewardsAPR();
        
        vm.prank(user2);
        uint256 rewards2 = stakingManager.claimRewardsAPR();
        
        vm.prank(user3);
        uint256 rewards3 = stakingManager.claimRewardsAPR();
        
        // Check that rewards were proportional to stake amount and time
        assertGt(rewards1, 0);
        assertGt(rewards2, 0);
        assertGt(rewards3, 0);
        
        // User with larger stake for longer time should get more rewards
        assertGt(rewards2, rewards1);
        assertGt(rewards2, rewards3);
    }
    
    function testOracleAndStakingIntegration() public {
        // Set initial APR to 10%
        oracle.setCurrentAPR(10);
        
        // User1 stakes
        vm.prank(user1);
        stakingManager.stakeAPR{value: 100 ether}(100 ether, VALIDATOR_1);
        
        // Skip 3 months
        skip(90 days);
        
        // Update APR to 15%
        oracle.setCurrentAPR(15);
        
        // Skip 3 more months
        skip(90 days);
        
        // Update APR to 8%
        oracle.setCurrentAPR(8);
        
        // Skip 3 more months
        skip(90 days);
        
        // Update APR to 12%
        oracle.setCurrentAPR(12);
        
        // Skip 3 more months
        skip(90 days);
        
        // Claim rewards
        vm.prank(user1);
        uint256 rewards = stakingManager.claimRewardsAPR();
        
        // Rewards should account for variable APR throughout the year
        uint256 estimatedRewards = 11.25 ether; // Average of (10% + 15% + 8% + 12%)/4 = 11.25%
        assertApproxEqRel(rewards, estimatedRewards, 0.05e18); // Allow 5% tolerance for calculation differences
    }
    
    function testUnbondingPeriodChanges() public {
        // Set initial unbonding period to 14 days
        oracle.setUnbondingPeriod(14 days);
        
        // User1 stakes
        vm.prank(user1);
        stakingManager.stakeAPR{value: 100 ether}(100 ether, VALIDATOR_1);
        
        // Request unstake
        vm.prank(user1);
        uint256 request1 = stakingManager.unstakeAPR(50 ether, VALIDATOR_1);
        
        // Check unbonding period
        INativeStaking.UnstakeRequest[] memory requests = nativeStaking.getUserUnstakeRequests(user1);
        assertEq(requests[request1].unlockTime, block.timestamp + 14 days);
        
        // Change unbonding period to 21 days
        oracle.setUnbondingPeriod(21 days);
        
        // Stake more
        vm.prank(user1);
        stakingManager.stakeAPR{value: 50 ether}(50 ether, VALIDATOR_2);
        
        // Request unstake again
        vm.prank(user1);
        uint256 request2 = stakingManager.unstakeAPR(25 ether, VALIDATOR_2);
        
        // Check new unbonding period
        requests = nativeStaking.getUserUnstakeRequests(user1);
        assertEq(requests[request2].unlockTime, block.timestamp + 21 days);
        
        // First request should still use old unbonding period
        skip(14 days + 1);
        
        // Can claim first request
        vm.prank(user1);
        stakingManager.claimUnstakeAPR(request1);
        
        // Second request should still be locked
        vm.prank(user1);
        vm.expectRevert("Still in unbonding period");
        stakingManager.claimUnstakeAPR(request2);
        
        // Skip additional time
        skip(7 days);
        
        // Now can claim second request
        vm.prank(user1);
        stakingManager.claimUnstakeAPR(request2);
    }
    
    function testStakeUnstakeWithChangingPrices() public {
        // Set initial price
        diaOracle.setPrice("XFI/USD", 1e8); // $1
        
        // User1 stakes
        vm.prank(user1);
        stakingManager.stakeAPR{value: 100 ether}(100 ether, VALIDATOR_1);
        
        // Skip time
        skip(30 days);
        
        // Change price
        diaOracle.setPrice("XFI/USD", 2e8); // $2
        
        // User1 stakes more
        vm.prank(user1);
        stakingManager.stakeAPR{value: 50 ether}(50 ether, VALIDATOR_1);
        
        // Skip time
        skip(30 days);
        
        // Request unstake
        vm.prank(user1);
        uint256 requestId = stakingManager.unstakeAPR(75 ether, VALIDATOR_1);
        
        // Skip unbonding period
        skip(UNBONDING_PERIOD + 1);
        
        // Change price again
        diaOracle.setPrice("XFI/USD", 0.5e8); // $0.50
        
        // Claim unstake
        vm.prank(user1);
        uint256 claimed = stakingManager.claimUnstakeAPR(requestId);
        
        // Should get back original XFI amount regardless of price changes
        assertEq(claimed, 75 ether);
        
        // Price changes should not affect staked amount
        assertEq(nativeStaking.getTotalStaked(user1), 75 ether);
    }
} 