// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "lib/forge-std/src/Test.sol";
import "../../src/core/NativeStaking.sol";
import "../../src/interfaces/INativeStaking.sol";

contract NativeStakingTest is Test {
    NativeStaking public staking;
    
    address public admin = address(1);
    address public operator = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    
    string public validatorId1 = "mxvaloper1gza5y94kal25eawsenl56th8kdyujszmcsxcgs";
    string public validatorId2 = "mxvaloper1jp0m7ynwtvrknzlmdzargmd59mh8n9gkh9yfwm";
    
    uint256 public minStakeAmount = 0.1 ether;
    
    event ValidatorAdded(string indexed validatorId, INativeStaking.ValidatorStatus status);
    event ValidatorUpdated(string indexed validatorId, INativeStaking.ValidatorStatus status);
    event Staked(address indexed staker, string indexed validatorId, uint256 amount);
    event UnstakeInitiated(address indexed staker, string indexed validatorId, uint256 amount);
    event UnstakeCompleted(address indexed staker, string indexed validatorId, uint256 amount);
    
    function setUp() public {
        // Deploy NativeStaking contract
        staking = new NativeStaking();
        
        // Initialize contract
        staking.initialize(admin, minStakeAmount);
        
        // Setup roles
        vm.startPrank(admin);
        staking.grantRole(staking.OPERATOR_ROLE(), operator);
        vm.stopPrank();
        
        // Fund test accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        
        // Fund contract with some initial ETH for rewards
        vm.deal(address(staking), 5 ether);
    }
    
    function testInitialization() public {
        // Check roles
        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE");
        assertTrue(staking.hasRole(staking.MANAGER_ROLE(), admin), "Admin should have MANAGER_ROLE");
        assertTrue(staking.hasRole(staking.OPERATOR_ROLE(), operator), "Operator should have OPERATOR_ROLE");
        
        // Check minimum stake amount
        assertEq(staking.getMinimumStakeAmount(), minStakeAmount, "Minimum stake amount should be set correctly");
    }
    
    function testAddValidator() public {
        vm.startPrank(admin);
        
        // Add first validator
        vm.expectEmit(true, true, false, true);
        emit ValidatorAdded(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        staking.addValidator(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Check validator was added
        INativeStaking.Validator memory validator = staking.getValidator(validatorId1);
        assertEq(validator.id, validatorId1, "Validator ID should match");
        assertEq(uint8(validator.status), uint8(INativeStaking.ValidatorStatus.Enabled), "Validator should be enabled");
        assertEq(validator.totalStaked, 0, "Total staked should be 0");
        assertEq(validator.uniqueStakers, 0, "Unique stakers should be 0");
        
        // Add second validator
        staking.addValidator(validatorId2, INativeStaking.ValidatorStatus.Disabled);
        
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
        staking.addValidator(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Update validator status
        vm.expectEmit(true, true, false, true);
        emit ValidatorUpdated(validatorId1, INativeStaking.ValidatorStatus.Disabled);
        staking.updateValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Disabled);
        
        // Check updated status
        INativeStaking.Validator memory validator = staking.getValidator(validatorId1);
        assertEq(uint8(validator.status), uint8(INativeStaking.ValidatorStatus.Disabled), "Validator should be disabled");
        
        vm.stopPrank();
    }
    
    function testBasicStaking() public {
        // Add validator
        vm.prank(admin);
        staking.addValidator(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        uint256 stakeAmount = 1 ether;
        
        // Stake to validator
        vm.startPrank(user1);
        vm.expectEmit(true, true, false, true);
        emit Staked(user1, validatorId1, stakeAmount);
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
        staking.addValidator(validatorId1, INativeStaking.ValidatorStatus.Disabled);
        
        // Attempt to stake to disabled validator
        vm.startPrank(user1);
        vm.expectRevert("Validator is not enabled");
        staking.stake{value: 1 ether}(validatorId1);
        vm.stopPrank();
    }
    
    function testUnstakeFlow() public {
        // Add validator
        vm.prank(admin);
        staking.addValidator(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        uint256 stakeAmount = 1 ether;
        uint256 unstakeAmount = 0.5 ether;
        
        // Stake to validator
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Initiate unstake
        vm.startPrank(user1);
        vm.expectEmit(true, true, false, true);
        emit UnstakeInitiated(user1, validatorId1, unstakeAmount);
        staking.initiateUnstake(validatorId1, unstakeAmount);
        vm.stopPrank();
        
        // Check unstake in process
        INativeStaking.UserStake memory userStake = staking.getUserStake(user1, validatorId1);
        assertTrue(userStake.inUnstakeProcess, "Should be in unstake process");
        assertTrue(staking.isUnstakeInProcess(user1, validatorId1), "isUnstakeInProcess should return true");
        
        // Complete unstake
        uint256 userBalanceBefore = user1.balance;
        
        vm.startPrank(operator);
        vm.expectEmit(true, true, false, true);
        emit UnstakeCompleted(user1, validatorId1, unstakeAmount);
        staking.completeUnstake(user1, validatorId1, unstakeAmount);
        vm.stopPrank();
        
        // Check user balance increased
        assertEq(user1.balance, userBalanceBefore + unstakeAmount, "User balance should increase by unstake amount");
        
        // Check user stake updated
        userStake = staking.getUserStake(user1, validatorId1);
        assertEq(userStake.amount, stakeAmount - unstakeAmount, "User stake amount should be reduced");
        assertFalse(userStake.inUnstakeProcess, "Should not be in unstake process anymore");
        
        // Check validator data updated
        INativeStaking.Validator memory validator = staking.getValidator(validatorId1);
        assertEq(validator.totalStaked, stakeAmount - unstakeAmount, "Validator total staked should be reduced");
        assertEq(validator.uniqueStakers, 1, "Should still have 1 unique staker");
    }
} 