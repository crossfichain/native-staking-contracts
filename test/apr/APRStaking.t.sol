// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./APRStakingBase.t.sol";

/**
 * @title APRStakingTest
 * @dev Tests for the APR staking flow
 */
contract APRStakingTest is APRStakingBaseTest {
    // Constants for testing
    string constant VALIDATOR_ID = "validator1";
    
    function testInitialState() public {
        // Check initial state of contracts
        assertEq(nativeStaking.minStakeAmount(), MIN_STAKE_AMOUNT);
        assertEq(nativeStaking.maxStakesPerUser(), 10);
        assertEq(stakingManager.getAPRContract(), address(nativeStaking));
        assertEq(stakingManager.getAPYContract(), address(stakingVault));
        assertEq(oracle.isOracleFresh(), true);
        assertEq(oracle.getUnbondingPeriod(), UNBONDING_PERIOD);
    }
    
    function testStakingAPR() public {
        uint256 stakeAmount = 10 ether;
        
        // Check initial balances
        uint256 initialBalance = user1.balance;
        uint256 initialStaked = nativeStaking.getTotalStaked(user1);
        assertEq(initialStaked, 0);
        
        // Perform staking
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Verify stake was recorded
        uint256 newStaked = nativeStaking.getTotalStaked(user1);
        assertEq(newStaked, stakeAmount);
        assertEq(user1.balance, initialBalance - stakeAmount);
        
        // Check stake details
        _checkStake(user1, 0, stakeAmount, block.timestamp, 0);
    }
    
    function testMultipleStakes() public {
        uint256 firstStakeAmount = 5 ether;
        uint256 secondStakeAmount = 7 ether;
        
        // First stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: firstStakeAmount}(firstStakeAmount, VALIDATOR_ID);
        
        // Second stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: secondStakeAmount}(secondStakeAmount, VALIDATOR_ID);
        
        // Verify total staked
        uint256 totalStaked = nativeStaking.getTotalStaked(user1);
        assertEq(totalStaked, firstStakeAmount + secondStakeAmount);
        
        // Check individual stakes
        _checkStake(user1, 0, firstStakeAmount, block.timestamp, 0);
        _checkStake(user1, 1, secondStakeAmount, block.timestamp, 0);
    }
    
    function testStakingMinimumAmount() public {
        uint256 belowMinimum = MIN_STAKE_AMOUNT - 1;
        
        // Attempt to stake below minimum
        vm.prank(user1);
        vm.expectRevert("Amount below minimum");
        stakingManager.stakeAPR{value: belowMinimum}(belowMinimum, VALIDATOR_ID);
        
        // Stake at minimum amount should succeed
        vm.prank(user1);
        stakingManager.stakeAPR{value: MIN_STAKE_AMOUNT}(MIN_STAKE_AMOUNT, VALIDATOR_ID);
        
        // Verify stake
        uint256 totalStaked = nativeStaking.getTotalStaked(user1);
        assertEq(totalStaked, MIN_STAKE_AMOUNT);
    }
    
    function testStakingMaxStakesPerUser() public {
        // Set max stakes to a lower value for testing
        uint256 maxStakes = 3;
        nativeStaking.setMaxStakesPerUser(maxStakes);
        
        // Create maximum number of stakes
        for (uint256 i = 0; i < maxStakes; i++) {
            vm.prank(user1);
            stakingManager.stakeAPR{value: MIN_STAKE_AMOUNT}(MIN_STAKE_AMOUNT, VALIDATOR_ID);
        }
        
        // Attempt to create one more stake
        vm.prank(user1);
        vm.expectRevert("Max stakes reached");
        stakingManager.stakeAPR{value: MIN_STAKE_AMOUNT}(MIN_STAKE_AMOUNT, VALIDATOR_ID);
    }
    
    function testUnstakeRequest() public {
        uint256 stakeAmount = 10 ether;
        uint256 unstakeAmount = 5 ether;
        
        // Stake first
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Request unstake
        vm.prank(user1);
        uint256 requestId = stakingManager.unstakeAPR(unstakeAmount, VALIDATOR_ID);
        
        // Verify request
        uint256 expectedUnlockTime = block.timestamp + UNBONDING_PERIOD;
        _checkUnstakeRequest(user1, requestId, unstakeAmount, expectedUnlockTime, false);
        
        // Verify staked amount reduced
        uint256 totalStaked = nativeStaking.getTotalStaked(user1);
        assertEq(totalStaked, stakeAmount - unstakeAmount);
    }
    
    function testUnstakeRequestFullAmount() public {
        uint256 stakeAmount = 10 ether;
        
        // Stake first
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Request unstake full amount
        vm.prank(user1);
        uint256 requestId = stakingManager.unstakeAPR(stakeAmount, VALIDATOR_ID);
        
        // Verify request
        uint256 expectedUnlockTime = block.timestamp + UNBONDING_PERIOD;
        _checkUnstakeRequest(user1, requestId, stakeAmount, expectedUnlockTime, false);
        
        // Verify staked amount is zero
        uint256 totalStaked = nativeStaking.getTotalStaked(user1);
        assertEq(totalStaked, 0);
        
        // Original stake should be marked as unbonding
        INativeStaking.StakeInfo[] memory stakes = nativeStaking.getUserStakes(user1);
        assertEq(stakes[0].unbondingAt, block.timestamp);
    }
    
    function testClaimUnstake() public {
        uint256 stakeAmount = 10 ether;
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Request unstake
        vm.prank(user1);
        uint256 requestId = stakingManager.unstakeAPR(stakeAmount, VALIDATOR_ID);
        
        // Try to claim before unlock time - should revert
        vm.prank(user1);
        vm.expectRevert("Still in unbonding period");
        stakingManager.claimUnstakeAPR(requestId);
        
        // Skip to after unlock time
        vm.warp(block.timestamp + oracle.getUnbondingPeriod() + 1);
        
        // Claim unstake
        vm.prank(user1);
        uint256 balanceBefore = user1.balance;
        
        // Claim unstake
        vm.prank(user1);
        uint256 claimedAmount = stakingManager.claimUnstakeAPR(requestId);
        
        // Verify claim
        assertEq(claimedAmount, stakeAmount);
        assertEq(user1.balance, 990 ether); // User started with 1000 ether, staked 10 ether, claiming returns the 10 ether back
        
        // Verify request marked as completed
        INativeStaking.UnstakeRequest[] memory requests = nativeStaking.getUserUnstakeRequests(user1);
        assertTrue(requests[requestId].completed);
    }
    
    function testRewardCalculation() public {
        uint256 stakeAmount = 100 ether;
        
        // Set APR to 10%
        oracle.setCurrentAPR(10);
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Skip 1 year
        skip(365 days);
        
        // Calculate expected rewards (10% of 100 ether)
        uint256 expectedRewards = 10 ether;
        uint256 calculatedRewards = nativeStaking.getUnclaimedRewards(user1);
        
        // Allow for small rounding differences
        assertApproxEqAbs(calculatedRewards, expectedRewards, 1e15);
    }
    
    function testClaimRewards() public {
        uint256 stakeAmount = 100 ether;
        
        // Set APR to 10%
        oracle.setCurrentAPR(10);
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Skip 1 year
        skip(365 days);
        
        // Check balance before claim
        uint256 balanceBefore = user1.balance;
        
        // Claim rewards
        vm.prank(user1);
        uint256 claimedRewards = stakingManager.claimRewardsAPR();
        
        // Expected rewards (10% of 100 ether)
        uint256 expectedRewards = 10 ether;
        
        // Allow for small rounding differences
        assertApproxEqAbs(claimedRewards, expectedRewards, 1e15);
        assertApproxEqAbs(user1.balance, balanceBefore + expectedRewards, 1e15);
        
        // Verify rewards reset
        uint256 remainingRewards = nativeStaking.getUnclaimedRewards(user1);
        assertEq(remainingRewards, 0);
    }
    
    function testVariableAPRRewards() public {
        uint256 stakeAmount = 100 ether;
        
        // Set initial APR to 10%
        oracle.setCurrentAPR(10);
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Skip 6 months
        skip(182 days);
        
        // Change APR to 20%
        oracle.setCurrentAPR(20);
        
        // Skip another 6 months
        skip(183 days);
        
        // Calculate expected rewards
        // First 6 months: 100 ether * 10% * (182/365) ~= 4.986 ether
        // Next 6 months: 100 ether * 20% * (183/365) ~= 10.027 ether
        // Total: ~15.013 ether
        uint256 expectedRewards = 15.013 ether;
        uint256 calculatedRewards = nativeStaking.getUnclaimedRewards(user1);
        
        // Allow for calculation differences
        assertApproxEqAbs(calculatedRewards, expectedRewards, 5 ether);
    }
    
    function testMultipleUsersStaking() public {
        // User 1 stakes
        vm.prank(user1);
        stakingManager.stakeAPR{value: 50 ether}(50 ether, "validator1");
        
        // User 2 stakes
        vm.prank(user2);
        stakingManager.stakeAPR{value: 100 ether}(100 ether, "validator2");
        
        // User 3 stakes
        vm.prank(user3);
        stakingManager.stakeAPR{value: 75 ether}(75 ether, "validator3");
        
        // Verify individual staked amounts
        assertEq(nativeStaking.getTotalStaked(user1), 50 ether);
        assertEq(nativeStaking.getTotalStaked(user2), 100 ether);
        assertEq(nativeStaking.getTotalStaked(user3), 75 ether);
        
        // Skip time and accumulate rewards
        skip(365 days);
        
        // Each user should get rewards proportional to their stake
        uint256 user1Rewards = nativeStaking.getUnclaimedRewards(user1);
        uint256 user2Rewards = nativeStaking.getUnclaimedRewards(user2);
        uint256 user3Rewards = nativeStaking.getUnclaimedRewards(user3);
        
        // Sanity check: user with more stake gets more rewards
        assertGt(user2Rewards, user1Rewards);
        assertGt(user2Rewards, user3Rewards);
        assertGt(user3Rewards, user1Rewards);
        
        // Check proportions (allow for small rounding differences)
        assertApproxEqRel(user2Rewards, user1Rewards * 2, 0.01e18); // user2 should get ~2x user1
        assertApproxEqRel(user3Rewards, user1Rewards * 3 / 2, 0.01e18); // user3 should get ~1.5x user1
    }
    
    function testPartialUnstake() public {
        uint256 stakeAmount = 100 ether;
        uint256 unstakeAmount = 30 ether;
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Skip time to accrue rewards
        skip(365 days);
        
        // Request partial unstake
        vm.prank(user1);
        uint256 requestId = stakingManager.unstakeAPR(unstakeAmount, VALIDATOR_ID);
        
        // Verify remaining stake amount
        uint256 expectedRemaining = stakeAmount - unstakeAmount;
        assertEq(nativeStaking.getTotalStaked(user1), expectedRemaining);
        
        // Skip unbonding period
        skip(UNBONDING_PERIOD + 1);
        
        // Claim unstake
        vm.prank(user1);
        uint256 claimed = stakingManager.claimUnstakeAPR(requestId);
        assertEq(claimed, unstakeAmount);
        
        // Verify rewards still accrue on remaining stake
        uint256 rewardsBefore = nativeStaking.getUnclaimedRewards(user1);
        skip(30 days);
        uint256 rewardsAfter = nativeStaking.getUnclaimedRewards(user1);
        assertGt(rewardsAfter, rewardsBefore);
    }
    
    function testInvalidUnstakeRequests() public {
        uint256 stakeAmount = 10 ether;
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Try to unstake more than staked
        vm.prank(user1);
        vm.expectRevert("Insufficient staked amount");
        stakingManager.unstakeAPR(stakeAmount + 1 ether, VALIDATOR_ID);
        
        // Try to unstake 0
        vm.prank(user1);
        vm.expectRevert("Amount must be > 0");
        stakingManager.unstakeAPR(0, VALIDATOR_ID);
        
        // Try to claim non-existent request
        vm.prank(user1);
        vm.expectRevert("Invalid request ID");
        stakingManager.claimUnstakeAPR(999);
    }
} 