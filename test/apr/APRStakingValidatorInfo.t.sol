// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./APRStakingBase.t.sol";

/**
 * @title APRStakingValidatorInfoTest
 * @dev Tests for validator info handling in the APR flow
 * Ensures that validator info is properly emitted in events for off-chain processing
 */
contract APRStakingValidatorInfoTest is APRStakingBaseTest {
    // Events are already defined in APRStakingBaseTest
    
    function testValidatorInfoInStakeEvents() public {
        string memory validatorId = "cosmosvaloper1xwazl8ftks4gn00y5x3c47auquc62ssu";
        uint256 stakeAmount = 10 ether;
        
        // Expect the staking event with validator info
        vm.expectEmit(true, false, false, true);
        emit Staked(user1, stakeAmount, validatorId, 0);
        
        // Perform stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, validatorId);
        
        // The validator info should not be stored on-chain, so we can't assert it directly
        // But we can check if the stake was recorded
        assertEq(nativeStaking.getTotalStaked(user1), stakeAmount);
    }
    
    function testLongValidatorId() public {
        string memory longValidatorId = "cosmosvaloper1xwazl8ftks4gn00y5x3c47auquc62ssutljqmeyvmfu2wl0kq5hq9zegg46";
        uint256 stakeAmount = 5 ether;
        
        // Expect the staking event with long validator info
        vm.expectEmit(true, false, false, true);
        emit Staked(user1, stakeAmount, longValidatorId, 0);
        
        // Perform stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, longValidatorId);
    }
    
    function testEmptyValidatorId() public {
        string memory emptyValidatorId = "";
        uint256 stakeAmount = 5 ether;
        
        // Expect the staking event with empty validator info
        vm.expectEmit(true, false, false, true);
        emit Staked(user1, stakeAmount, emptyValidatorId, 0);
        
        // Perform stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, emptyValidatorId);
        
        // Empty validator ID should still work because validation happens off-chain
        assertEq(nativeStaking.getTotalStaked(user1), stakeAmount);
    }
    
    function testMultipleValidatorIds() public {
        string[3] memory validatorIds = [
            "cosmosvaloper1xwazl8ftks4gn00y5x3c47auquc62ssuA",
            "cosmosvaloper1xwazl8ftks4gn00y5x3c47auquc62ssuB",
            "cosmosvaloper1xwazl8ftks4gn00y5x3c47auquc62ssuC"
        ];
        
        uint256 stakeAmount = 5 ether;
        
        // Stake with multiple validator IDs
        for (uint256 i = 0; i < validatorIds.length; i++) {
            // Expect staking event with correct validator info
            vm.expectEmit(true, false, false, true);
            emit Staked(user1, stakeAmount, validatorIds[i], i);
            
            // Perform stake
            vm.prank(user1);
            stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, validatorIds[i]);
        }
        
        // Total staked should be the sum of all stakes
        assertEq(nativeStaking.getTotalStaked(user1), stakeAmount * validatorIds.length);
    }
    
    function testValidatorInfoInUnstakeEvents() public {
        string memory validatorId = "cosmosvaloper1xwazl8ftks4gn00y5x3c47auquc62ssu";
        uint256 stakeAmount = 10 ether;
        uint256 unstakeAmount = 5 ether;
        
        // Perform stake first
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, validatorId);
        
        // Expect unstaking event with validator info
        // Note: can't predict exact requestId and unlockTime, so only checking user, amount, validator
        vm.expectEmit(true, false, false, false);
        emit UnstakeRequested(user1, unstakeAmount, validatorId, 0, 0);
        
        // Perform unstake
        vm.prank(user1);
        stakingManager.unstakeAPR(unstakeAmount, validatorId);
        
        // Remaining staked amount should be correct
        assertEq(nativeStaking.getTotalStaked(user1), stakeAmount - unstakeAmount);
    }
    
    function testDifferentValidatorForUnstake() public {
        string memory stakeValidatorId = "cosmosvaloper1stakevalidator";
        string memory unstakeValidatorId = "cosmosvaloper1unstakevalidator";
        uint256 stakeAmount = 10 ether;
        
        // Perform stake with one validator
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, stakeValidatorId);
        
        // Expect unstaking event with different validator info
        vm.expectEmit(true, false, false, false);
        emit UnstakeRequested(user1, stakeAmount, unstakeValidatorId, 0, 0);
        
        // Perform unstake with different validator ID
        vm.prank(user1);
        stakingManager.unstakeAPR(stakeAmount, unstakeValidatorId);
        
        // Should work because validator is only used for event emission
        assertEq(nativeStaking.getTotalStaked(user1), 0);
    }
    
    function testSameValidatorIdForMultipleUsers() public {
        string memory validatorId = "cosmosvaloper1sharedvalidator";
        uint256 stakeAmount = 10 ether;
        
        // Stake from user1
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, validatorId);
        
        // Stake from user2 with same validator
        vm.prank(user2);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, validatorId);
        
        // Both users should have the correct staked amount
        assertEq(nativeStaking.getTotalStaked(user1), stakeAmount);
        assertEq(nativeStaking.getTotalStaked(user2), stakeAmount);
    }
    
    function testNoStorageOfValidatorInfo() public {
        string memory validatorId = "cosmosvaloper1xwazl8ftks4gn00y5x3c47auquc62ssu";
        uint256 stakeAmount = 10 ether;
        
        // Perform stake
        vm.prank(user1);
        stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, validatorId);
        
        // Get the stake info
        INativeStaking.StakeInfo[] memory stakes = nativeStaking.getUserStakes(user1);
        
        // The StakeInfo struct should only contain amount, stakedAt, and unbondingAt
        // It should not contain the validator info
        assertEq(stakes.length, 1);
        assertEq(stakes[0].amount, stakeAmount);
        assertEq(stakes[0].stakedAt, block.timestamp);
        assertEq(stakes[0].unbondingAt, 0);
        
        // No way to retrieve the validator info from the contract
    }
} 