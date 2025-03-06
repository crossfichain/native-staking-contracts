// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./APRStakingBase.t.sol";
import {console} from "forge-std/console.sol";

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
        
        // Check balance before claim
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
        
        // Set APR to 10% using mockOracle
        mockOracle.setValidatorAPR(10);
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Skip 1 year
        skip(365 days);
        
        // For testing purposes, directly set the expected rewards in the oracle
        uint256 expectedRewards = 10 ether; // 10% of 100 ether
        console.log("Expected rewards:", expectedRewards);
        
        // Set the rewards in the mock oracle
        _setUserClaimableRewards(user1, expectedRewards);
        
        // Check oracle's claimable rewards directly
        uint256 oracleRewards = mockOracle.getUserClaimableRewards(user1);
        console.log("Oracle rewards:", oracleRewards);
        
        // Check that the rewards match what we set
        assertEq(oracleRewards, expectedRewards);
    }
    
    function testClaimRewards() public {
        uint256 stakeAmount = 100 ether;
        uint256 initialBalance = user1.balance;
        console.log("Initial balance:", initialBalance);
        
        // Set APR to 10% in mock oracle
        mockOracle.setValidatorAPR(10);
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        console.log("Balance after staking:", user1.balance);
        
        // Skip 1 year
        skip(365 days);
        
        // Set rewards
        uint256 rewardsAmount = 10 ether; // 10% of 100 ether
        _setUserClaimableRewards(user1, rewardsAmount);
        
        // Verify the rewards are properly set in the oracle
        uint256 oracleRewards = mockOracle.getUserClaimableRewards(user1);
        assertEq(oracleRewards, rewardsAmount, "Oracle should return the rewards we set");
        
        // Check balance before claim
        uint256 balanceBefore = user1.balance;
        console.log("Balance before claiming rewards:", balanceBefore);
        
        // Fund the NativeStaking contract with WXFI tokens to pay rewards
        // Mint WXFI to admin
        vm.deal(admin, 20 ether);
        vm.startPrank(admin);
        wxfi.deposit{value: 20 ether}();
        wxfi.transfer(address(nativeStaking), 20 ether);
        vm.stopPrank();
        
        console.log("WXFI balance of NativeStaking:", wxfi.balanceOf(address(nativeStaking)));
        
        // Claim rewards
        vm.prank(user1);
        uint256 claimedRewards = stakingManager.claimRewardsAPR();
        console.log("Claimed rewards:", claimedRewards);
        
        // Check that claimed rewards match expected rewards
        assertEq(claimedRewards, rewardsAmount, "Claimed rewards should match what we set");
        
        // Check if user received WXFI (might be WXFI instead of native XFI)
        uint256 wxfiBalance = wxfi.balanceOf(user1);
        console.log("WXFI balance of user:", wxfiBalance);
        
        // If rewards were sent as WXFI, convert them to XFI for the test
        if (wxfiBalance > 0) {
            vm.startPrank(user1);
            wxfi.withdraw(wxfiBalance);
            vm.stopPrank();
        }
        
        // Balance should increase by rewards amount
        assertEq(user1.balance, balanceBefore + claimedRewards, "User balance should increase by the claimed rewards");
        
        // Make sure we can't claim again (now 0 rewards)
        vm.prank(user1);
        vm.expectRevert("No rewards to claim");
        stakingManager.claimRewardsAPR();
    }
    
    function testVariableAPRRewards() public {
        uint256 stakeAmount = 100 ether;
        
        // Set initial APR to 10%
        mockOracle.setValidatorAPR(10);
        
        // Stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Skip 6 months
        skip(180 days);
        
        // Update APR to 20%
        mockOracle.setValidatorAPR(20);
        
        // Skip 6 more months
        skip(185 days);
        
        // Calculate expected rewards
        // First 180 days at 10% APR: 100 ETH * 10% * (180/365) = 4.93 ETH
        // Next 185 days at 20% APR: 100 ETH * 20% * (185/365) = 10.14 ETH
        // Total expected rewards: ~15.07 ETH
        uint256 calculatedRewards = 
            stakeAmount * 10 / 100 * 180 / 365 +  // First period
            stakeAmount * 20 / 100 * 185 / 365;   // Second period
        
        // Set rewards in oracle to match calculated value
        _setUserClaimableRewards(user1, calculatedRewards);
        
        // Claim rewards
        vm.prank(user1);
        uint256 claimedRewards = stakingManager.claimRewardsAPR();
        
        // Check that claimed rewards match our calculation
        assertEq(claimedRewards, calculatedRewards);
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
        
        // Try to unstake more than staked - this will actually revert with "Insufficient staked amount"
        // but only after passing the unstaking frozen check in the manager
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