// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/NativeStaking.sol";
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
    }
    
    function testInitialization() public view {
        // Check roles
        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE");
        assertTrue(staking.hasRole(staking.MANAGER_ROLE(), admin), "Admin should have MANAGER_ROLE");
        assertTrue(staking.hasRole(staking.OPERATOR_ROLE(), operator), "Operator should have OPERATOR_ROLE");
        
        // Check minimum stake amount
        assertEq(staking.getMinimumStakeAmount(), minStakeAmount, "Minimum stake amount should be set correctly");
        
        // Check oracle address
        assertEq(staking.getOracle(), address(oracle), "Oracle address should be set correctly");
    }
    
    function testAddValidator() public {
        vm.startPrank(admin);
        
        // Add first validator
        staking.addValidator(validatorId1, true); // Set to enabled
        
        // Check validator was added
        INativeStaking.Validator memory validator = staking.getValidator(validatorId1);
        assertEq(validator.id, validatorId1, "Validator ID should match");
        assertEq(uint8(validator.status), uint8(INativeStaking.ValidatorStatus.Enabled), "Validator should be enabled");
        assertEq(validator.totalStaked, 0, "Total staked should be 0");
        assertEq(validator.uniqueStakers, 0, "Unique stakers should be 0");
        
        // Add second validator
        staking.addValidator(validatorId2, false); // Set to disabled
        
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
        staking.addValidator(validatorId1, true);
        
        // Update validator status
        staking.updateValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Disabled);
        
        // Check updated status
        INativeStaking.Validator memory validator = staking.getValidator(validatorId1);
        assertEq(uint8(validator.status), uint8(INativeStaking.ValidatorStatus.Disabled), "Validator should be disabled");
        
        vm.stopPrank();
    }
    
    function testBasicStaking() public {
        // Add validator
        vm.prank(admin);
        staking.addValidator(validatorId1, true);
        
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
        staking.addValidator(validatorId1, false);
        
        // Attempt to stake to disabled validator
        vm.startPrank(user1);
        vm.expectRevert("Validator is not enabled");
        staking.stake{value: 1 ether}(validatorId1);
        vm.stopPrank();
    }
    
    function testUnstake() public {
        // Add validator first
        vm.prank(admin);
        staking.addValidator(validatorId1, true);
        
        // Stake first
        uint256 stakeAmount = 1 ether;
        vm.deal(user1, stakeAmount);
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Wait for unstake interval
        vm.warp(block.timestamp + staking.getMinUnstakeInterval() + 1);
        
        // Initiate unstake
        uint256 unstakeAmount = stakeAmount; // Full amount will be unstaked now
        vm.prank(user1);
        staking.initiateUnstake(validatorId1);
        
        // Check if unstake initiated
        assertTrue(staking.isUnstakeInProcess(user1, validatorId1));
        
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
        staking.addValidator(validatorId1, true);
        
        uint256 stakeAmount = 1 ether;
        uint256 rewardAmount = 0.1 ether;
        
        // Set MPX price for proper conversion
        oracle.setMPXPrice(0.01 ether);  // 1 MPX = 0.01 XFI
        
        // Stake to validator
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Set time to pass minimum claim interval
        vm.warp(block.timestamp + 2 days);
        
        // Initiate reward claim
        vm.prank(user1);
        staking.initiateRewardClaim(validatorId1);
        
        // Complete reward claim
        uint256 userBalanceBefore = user1.balance;
        
        // Make sure operator has enough ETH to pay rewards
        vm.deal(operator, 1 ether);
        
        vm.prank(operator);
        staking.completeRewardClaim{value: rewardAmount}(user1, validatorId1, rewardAmount, false);
        
        // Check user received reward
        assertEq(user1.balance, userBalanceBefore + rewardAmount, "User should receive reward amount");
    }
    
    function testEmergencyWithdrawal() public {
        // Add validator
        vm.prank(admin);
        staking.addValidator(validatorId1, true);
        
        uint256 stakeAmount = 1 ether;
        
        // Stake to validator
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Initiate emergency withdrawal
        vm.prank(user1);
        staking.initiateEmergencyWithdrawal();
        
        // Verify emergency withdrawal was initiated
        assertTrue(staking.isEmergencyWithdrawalRequested(user1), "Emergency withdrawal should be requested");
        
        // Complete emergency withdrawal
        uint256 userBalanceBefore = user1.balance;
        
        // Calculate MPX amount for event (unused but kept for clarity)
        uint256 mpxAmount = oracle.convertXFItoMPX(stakeAmount);
        
        // Complete the withdrawal - this should clean up all user validators and stakes
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
        staking.addValidator(validatorId1, true);
        staking.addValidator(validatorId2, true);
        vm.stopPrank();
        
        uint256 stakeAmount = 1 ether;
        
        // Stake to first validator
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Warp time to allow migration (must be in a different block)
        vm.warp(block.timestamp + 1 days);
        
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
} 