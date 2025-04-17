// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/NativeStaking.sol";
import "../../src/interfaces/INativeStaking.sol";
import "../mocks/MockOracle.sol";

contract NativeStakingTest is Test {
    NativeStaking public staking;
    MockOracle public oracle;
    
    address public admin = address(1);
    address public operator = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    
    string public validatorId1 = "mxvaloper1gza5y94kal25eawsenl56th8kdyujszmcsxcgs";
    string public validatorId2 = "mxvaloper1jp0m7ynwtvrknzlmdzargmd59mh8n9gkh9yfwm";
    
    uint256 public minStakeAmount = 0.1 ether;
    uint256 public timeBuffer = 1 days + 1;
    
    function setUp() public {
        // Deploy Oracle contract
        oracle = new MockOracle();
        
        // Deploy NativeStaking contract
        staking = new NativeStaking();
        
        // Initialize contract
        staking.initialize(admin, minStakeAmount, address(oracle));
        
        // Setup roles
        vm.startPrank(admin);
        staking.grantRole(staking.OPERATOR_ROLE(), operator);
        vm.stopPrank();
        
        // Fund test accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        
        // Fund contract with some initial ETH for rewards
        vm.deal(address(staking), 5 ether);
        
        // Set time intervals for testing
        vm.startPrank(admin);
        staking.setMinStakeInterval(1 hours);
        staking.setMinUnstakeInterval(1 hours);
        staking.setMinClaimInterval(1 hours);
        vm.stopPrank();
    }
    
    function testInitialization() public view {
        // Check roles
        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE");
        assertTrue(staking.hasRole(staking.MANAGER_ROLE(), admin), "Admin should have MANAGER_ROLE");
        assertTrue(staking.hasRole(staking.OPERATOR_ROLE(), operator), "Operator should have OPERATOR_ROLE");
        
        // Check minimum stake amount
        assertEq(staking.getMinStakeAmount(), minStakeAmount, "Minimum stake amount should be set correctly");
        
        // Check oracle address
        assertEq(staking.getOracle(), address(oracle), "Oracle address should be set correctly");
    }
    
    function testAddValidator() public {
        vm.startPrank(admin);
        
        // Add first validator
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Check validator was added
        INativeStaking.Validator memory validator = staking.getValidator(validatorId1);
        assertEq(validator.id, validatorId1, "Validator ID should match");
        assertEq(uint8(validator.status), uint8(INativeStaking.ValidatorStatus.Enabled), "Validator should be enabled");
        assertEq(validator.totalStaked, 0, "Total staked should be 0");
        assertEq(validator.uniqueStakers, 0, "Unique stakers should be 0");
        
        // Add second validator
        staking.setValidatorStatus(validatorId2, INativeStaking.ValidatorStatus.Disabled);
        
        // Check validator count
        assertEq(staking.getValidatorCount(), 2, "Should have 2 validators");
        
        // Check validator list
        INativeStaking.Validator[] memory validators = staking.getValidators();
        assertEq(validators.length, 2, "Should return 2 validators");
        
        vm.stopPrank();
    }
    
    function testUpdateValidatorStatus() public {
        vm.startPrank(admin);
        
        // Add validator
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Update validator status
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Disabled);
        
        // Check updated status
        INativeStaking.Validator memory validator = staking.getValidator(validatorId1);
        assertEq(uint8(validator.status), uint8(INativeStaking.ValidatorStatus.Disabled), "Validator should be disabled");
        
        vm.stopPrank();
    }
    
    function testBasicStaking() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Set initial timestamp to a higher value to avoid time constraint issues
        vm.warp(3700);
        
        uint256 stakeAmount = 1 ether;
        
        // Stake to validator
        vm.startPrank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        vm.stopPrank();
        
        // Check user stake
        INativeStaking.UserStake memory userStake = staking.getUserStake(user1, validatorId1);
        assertEq(userStake.amount, stakeAmount, "User stake amount should match");
        assertFalse(userStake.inUnstakeProcess, "Should not be in unstake process");
        
        // Check validator data
        INativeStaking.Validator memory validator = staking.getValidator(validatorId1);
        assertEq(validator.totalStaked, stakeAmount, "Validator total staked should match");
        assertEq(validator.uniqueStakers, 1, "Should have 1 unique staker");
        
        // Check user total staked
        assertEq(staking.getUserTotalStaked(user1), stakeAmount, "User total staked should match");
        
        // Check user validators
        string[] memory userValidators = staking.getUserValidators(user1);
        assertEq(userValidators.length, 1, "User should have 1 validator");
        assertEq(userValidators[0], validatorId1, "User validator should match");
    }
    
    function testStakingRevertsForDisabledValidator() public {
        // Add validator as disabled
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Disabled);
        
        // Attempt to stake to disabled validator
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(INativeStaking.ValidatorNotEnabled.selector, validatorId1));
        staking.stake{value: 1 ether}(validatorId1);
        vm.stopPrank();
    }
    
    function testUnstake() public {
        // Add validator first
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Set initial timestamp
        vm.warp(3700);
        
        // Stake first
        uint256 stakeAmount = 1 ether;
        vm.deal(user1, stakeAmount);
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Wait for unstake interval
        vm.warp(block.timestamp + 4 hours);
        
        // Initiate unstake
        vm.prank(user1);
        staking.initiateUnstake(validatorId1);
        
        // Check if unstake initiated
        assertTrue(staking.isUnstakeInProcess(user1, validatorId1));
        
        // Get unstake status
        (bool inProcess, uint256 unstakeAmount) = staking.getUnstakeStatus(user1, validatorId1);
        assertTrue(inProcess, "Unstake should be in process");
        assertEq(unstakeAmount, stakeAmount, "Unstake amount should match stake amount");
        
        // Complete unstake
        vm.prank(operator);
        staking.completeUnstake(user1, validatorId1, unstakeAmount);
        
        // Check if unstake completed
        assertFalse(staking.isUnstakeInProcess(user1, validatorId1));
        assertEq(user1.balance, unstakeAmount);
    }
    
    function testRewardClaiming() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Set initial timestamp
        vm.warp(3700);
        
        uint256 stakeAmount = 1 ether;
        uint256 rewardAmount = 0.1 ether;
        
        // Set MPX price for proper conversion
        oracle.setMPXPrice(0.01 ether);  // 1 MPX = 0.01 XFI
        
        // Stake to validator
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Set time to pass minimum claim interval
        vm.warp(block.timestamp + 4 hours);
        
        // Initiate reward claim
        vm.prank(user1);
        staking.initiateRewardClaim(validatorId1);
        
        // Complete reward claim
        uint256 userBalanceBefore = user1.balance;
        
        // Make sure operator has enough ETH to pay rewards
        vm.deal(operator, 1 ether);
        
        vm.prank(operator);
        staking.completeRewardClaim{value: rewardAmount}(user1, validatorId1, false);
        
        // Check user received reward
        assertEq(user1.balance, userBalanceBefore + rewardAmount, "User should receive reward amount");
    }
    
    function testEmergencyWithdrawal() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Set initial timestamp
        vm.warp(3700);
        
        uint256 stakeAmount = 1 ether;
        
        // Stake to validator
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Move time forward to avoid time restrictions
        vm.warp(block.timestamp + 4 hours);
        
        // Initiate emergency withdrawal
        vm.prank(user1);
        staking.initiateEmergencyWithdrawal();
        
        // Verify emergency withdrawal was initiated
        assertTrue(staking.isEmergencyWithdrawalRequested(user1), "Emergency withdrawal should be requested");
        
        // Complete emergency withdrawal
        uint256 userBalanceBefore = user1.balance;
        
        vm.prank(operator);
        staking.completeEmergencyWithdrawal(user1, stakeAmount);
        
        // Check user balance increased
        assertEq(user1.balance, userBalanceBefore + stakeAmount, "User balance should increase by staked amount");
        
        // Check user stake cleared
        assertEq(staking.getUserTotalStaked(user1), 0, "User total staked should be 0");
        
        // Check user validators cleared
        string[] memory userValidators = staking.getUserValidators(user1);
        assertEq(userValidators.length, 0, "User should have no validators after emergency withdrawal");
    }
    
    function testValidatorMigration() public {
        // Add validators
        vm.startPrank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        staking.setValidatorStatus(validatorId2, INativeStaking.ValidatorStatus.Enabled);
        vm.stopPrank();
        
        // Set initial timestamp
        vm.warp(3700);
        
        uint256 stakeAmount = 1 ether;
        
        // Stake to first validator
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Warp time to allow migration
        vm.warp(block.timestamp + 4 hours);
        
        // Setup migration
        vm.prank(admin);
        staking.setupValidatorMigration(validatorId1, validatorId2);
        
        // Migrate stake
        vm.prank(user1);
        staking.migrateStake(validatorId1, validatorId2);
        
        // Check stakes after migration
        INativeStaking.UserStake memory fromStake = staking.getUserStake(user1, validatorId1);
        INativeStaking.UserStake memory toStake = staking.getUserStake(user1, validatorId2);
        
        assertEq(fromStake.amount, 0, "Source stake should be 0");
        assertEq(toStake.amount, stakeAmount, "Destination stake should match original amount");
        
        // Check validator stats
        INativeStaking.Validator memory fromValidator = staking.getValidator(validatorId1);
        INativeStaking.Validator memory toValidator = staking.getValidator(validatorId2);
        
        assertEq(fromValidator.totalStaked, 0, "Source validator total staked should be 0");
        assertEq(fromValidator.uniqueStakers, 0, "Source validator should have 0 stakers");
        assertEq(toValidator.totalStaked, stakeAmount, "Destination validator total staked should match");
        assertEq(toValidator.uniqueStakers, 1, "Destination validator should have 1 staker");
    }
    
    function testGetUserStatus() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Set initial timestamp to a higher value to avoid time constraint issues
        vm.warp(3700);
        
        uint256 stakeAmount = 1 ether;
        
        // Stake to validator
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Check user status
        (
            INativeStaking.UserStake memory userStake,
            bool canStake,
            bool canUnstake,
            bool canClaim,
            uint256 stakeUnlockTime,
            uint256 unstakeUnlockTime,
            uint256 claimUnlockTime
        ) = staking.getUserStatus(user1, validatorId1);
        
        assertEq(userStake.amount, stakeAmount, "User stake amount should match");
        assertFalse(canStake, "User should not be able to stake again to the same validator");
        assertFalse(canUnstake, "User should not be able to unstake yet");
        assertFalse(canClaim, "User should not be able to claim yet");
        
        // Advance time past unstake unlock time
        vm.warp(unstakeUnlockTime + 1);
        
        // Check user status again
        (
            ,
            ,
            bool canUnstakeNow,
            ,
            ,
            ,
            
        ) = staking.getUserStatus(user1, validatorId1);
        
        assertTrue(canUnstakeNow, "User should be able to unstake now");
    }
    
    function testPauseAndUnpauseStaking() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Set initial timestamp
        vm.warp(3700);
        
        // Pause staking
        vm.prank(admin);
        staking.pauseStaking();
        
        // Try to stake when paused
        vm.startPrank(user1);
        vm.expectRevert("Pausable: paused");
        staking.stake{value: 1 ether}(validatorId1);
        vm.stopPrank();
        
        // Unpause staking
        vm.prank(admin);
        staking.unpauseStaking();
        
        // Move time forward to avoid time restrictions
        vm.warp(block.timestamp + 4 hours);
        
        // Stake after unpausing
        vm.prank(user1);
        staking.stake{value: 1 ether}(validatorId1);
        
        // Verify stake was successful
        INativeStaking.UserStake memory userStake = staking.getUserStake(user1, validatorId1);
        assertEq(userStake.amount, 1 ether, "User stake amount should match");
    }
    
    function testPauseAndUnpauseUnstaking() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Set initial timestamp
        vm.warp(3700);
        
        // Stake first
        uint256 stakeAmount = 1 ether;
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Wait for unstake interval
        vm.warp(block.timestamp + 4 hours);
        
        // Pause unstaking
        vm.prank(admin);
        staking.pauseUnstake();
        
        // Try to unstake when paused
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(INativeStaking.UnstakingPaused.selector));
        staking.initiateUnstake(validatorId1);
        vm.stopPrank();
        
        // Unpause unstaking
        vm.prank(admin);
        staking.unpauseUnstake();
        
        // Unstake after unpausing
        vm.prank(user1);
        staking.initiateUnstake(validatorId1);
        
        // Verify unstake was initiated
        assertTrue(staking.isUnstakeInProcess(user1, validatorId1), "Unstake should be in process");
    }
} 