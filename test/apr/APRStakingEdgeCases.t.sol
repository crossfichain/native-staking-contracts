// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./APRStakingBase.t.sol";

/**
 * @title APRStakingEdgeCasesTest
 * @dev Tests edge cases for the APR staking flow
 */
contract APRStakingEdgeCasesTest is APRStakingBaseTest {
    // Constants for testing
    string constant VALIDATOR_ID = "validator1";
    
    function testZeroAPR() public {
        uint256 stakeAmount = 100 ether;
        
        // Set APR to 0%
        oracle.setCurrentAPR(0);
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Skip 1 year
        skip(365 days);
        
        // No rewards should accrue with 0% APR
        uint256 rewards = nativeStaking.getUnclaimedRewards(user1);
        assertEq(rewards, 0);
    }
    
    function testMaximumAPR() public {
        uint256 stakeAmount = 100 ether;
        
        // Set APR to 100%
        oracle.setCurrentAPR(100);
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Skip 1 year
        skip(365 days);
        
        // Rewards should be 100% of stake amount
        uint256 rewards = nativeStaking.getUnclaimedRewards(user1);
        assertApproxEqAbs(rewards, stakeAmount, 1e15);
    }
    
    function testStakeUnstakeImmediately() public {
        uint256 stakeAmount = 10 ether;
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Immediately request unstake
        vm.prank(user1);
        uint256 requestId = stakingManager.unstakeAPR(stakeAmount, VALIDATOR_ID);
        
        // No rewards should be earned
        uint256 rewards = nativeStaking.getUnclaimedRewards(user1);
        assertEq(rewards, 0);
        
        // Skip unbonding period
        skip(UNBONDING_PERIOD + 1);
        
        // Claim unstake
        vm.prank(user1);
        uint256 claimed = stakingManager.claimUnstakeAPR(requestId);
        
        // Should get back original stake amount
        assertEq(claimed, stakeAmount);
    }
    
    function testMultipleUnstakeRequests() public {
        uint256 stakeAmount = 100 ether;
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Make multiple unstake requests
        vm.startPrank(user1);
        uint256 requestId1 = stakingManager.unstakeAPR(20 ether, VALIDATOR_ID);
        uint256 requestId2 = stakingManager.unstakeAPR(30 ether, VALIDATOR_ID);
        uint256 requestId3 = stakingManager.unstakeAPR(40 ether, VALIDATOR_ID);
        vm.stopPrank();
        
        // Verify all requests
        _checkUnstakeRequest(user1, requestId1, 20 ether, block.timestamp + UNBONDING_PERIOD, false);
        _checkUnstakeRequest(user1, requestId2, 30 ether, block.timestamp + UNBONDING_PERIOD, false);
        _checkUnstakeRequest(user1, requestId3, 40 ether, block.timestamp + UNBONDING_PERIOD, false);
        
        // Verify remaining stake amount
        uint256 totalStaked = nativeStaking.getTotalStaked(user1);
        assertEq(totalStaked, 10 ether);
        
        // Skip unbonding period
        skip(UNBONDING_PERIOD + 1);
        
        // Claim all unstake requests in different order
        vm.startPrank(user1);
        
        uint256 claimed2 = stakingManager.claimUnstakeAPR(requestId2);
        assertEq(claimed2, 30 ether);
        
        uint256 claimed1 = stakingManager.claimUnstakeAPR(requestId1);
        assertEq(claimed1, 20 ether);
        
        uint256 claimed3 = stakingManager.claimUnstakeAPR(requestId3);
        assertEq(claimed3, 40 ether);
        
        vm.stopPrank();
        
        // Verify all requests completed
        INativeStaking.UnstakeRequest[] memory requests = nativeStaking.getUserUnstakeRequests(user1);
        assertTrue(requests[requestId1].completed);
        assertTrue(requests[requestId2].completed);
        assertTrue(requests[requestId3].completed);
    }
    
    function testClaimingUnstakeTwice() public {
        uint256 stakeAmount = 10 ether;
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Request unstake
        vm.prank(user1);
        uint256 requestId = stakingManager.unstakeAPR(stakeAmount, VALIDATOR_ID);
        
        // Skip unbonding period
        skip(UNBONDING_PERIOD + 1);
        
        // Claim unstake
        vm.prank(user1);
        stakingManager.claimUnstakeAPR(requestId);
        
        // Try to claim again
        vm.prank(user1);
        vm.expectRevert("Already claimed");
        stakingManager.claimUnstakeAPR(requestId);
    }
    
    function testEmptyStakeList() public {
        // User has no stakes initially
        INativeStaking.StakeInfo[] memory stakes = nativeStaking.getUserStakes(user1);
        assertEq(stakes.length, 0);
        
        // No rewards should be calculated
        uint256 rewards = nativeStaking.getUnclaimedRewards(user1);
        assertEq(rewards, 0);
        
        // Total staked should be 0
        uint256 totalStaked = nativeStaking.getTotalStaked(user1);
        assertEq(totalStaked, 0);
    }
    
    function testMaxUnbondingPeriod() public {
        uint256 stakeAmount = 10 ether;
        uint256 maxUnbondingPeriod = 365 days;
        
        // Set max unbonding period
        oracle.setUnbondingPeriod(maxUnbondingPeriod);
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Request unstake
        vm.prank(user1);
        uint256 requestId = stakingManager.unstakeAPR(stakeAmount, VALIDATOR_ID);
        
        // Skip almost the unbonding period
        skip(maxUnbondingPeriod - 1);
        
        // Try to claim too early
        vm.prank(user1);
        vm.expectRevert("Still in unbonding period");
        stakingManager.claimUnstakeAPR(requestId);
        
        // Skip the last day
        skip(1 days);
        
        // Now should be able to claim
        vm.prank(user1);
        uint256 claimed = stakingManager.claimUnstakeAPR(requestId);
        assertEq(claimed, stakeAmount);
    }
    
    function testOracleFailure() public {
        uint256 stakeAmount = 100 ether;
        
        // Set up a stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Skip 1 year
        skip(365 days);
        
        // Switch to mock oracle that returns 0
        mockOracle.setAPY(0);
        
        // Update the oracle reference in the system
        oracle.setCurrentAPR(0);
        
        // Should still have the expected rewards based on past APR
        uint256 rewards = nativeStaking.getUnclaimedRewards(user1);
        
        // Let's make sure there are some rewards
        assertGt(rewards, 0);
    }
    
    function testMaximumNumberOfStakes() public {
        // Test the system with a large number of stakes
        uint256 numStakes = 10; // maximum allowed by default
        uint256 stakeAmount = 1 ether;
        
        // Create maximum number of stakes
        for (uint256 i = 0; i < numStakes; i++) {
            vm.prank(user1);
            stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        }
        
        // Verify number of stakes
        INativeStaking.StakeInfo[] memory stakes = nativeStaking.getUserStakes(user1);
        assertEq(stakes.length, numStakes);
        
        // Verify total staked
        uint256 totalStaked = nativeStaking.getTotalStaked(user1);
        assertEq(totalStaked, stakeAmount * numStakes);
    }
} 