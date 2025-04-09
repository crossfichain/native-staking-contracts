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
    uint256 public constant MIN_TIME_INTERVAL = 1 hours;
    
    function setUp() public {
        // Deploy Oracle contract
        oracle = new MockOracle();
        
        // Deploy NativeStaking contract
        staking = new NativeStaking();
        
        // Set initial block timestamp to be far in the past
        // This allows us to fast forward time without issues
        vm.warp(MIN_TIME_INTERVAL * 10);
        
        // Initialize contract
        staking.initialize(admin, 0.1 ether, address(oracle));
        
        // Set time restrictions to 1 hour for testing
        vm.startPrank(admin);
        staking.setMinStakeInterval(MIN_TIME_INTERVAL);
        staking.setMinUnstakeInterval(MIN_TIME_INTERVAL);
        staking.setMinClaimInterval(MIN_TIME_INTERVAL);
        
        // Setup roles
        staking.grantRole(staking.OPERATOR_ROLE(), operator);
        vm.stopPrank();
        
        // Fund test accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        
        // Fund contract with some initial ETH for rewards
        vm.deal(address(staking), 5 ether);
    }
    
    function test_Initialize_CorrectSetup() public view {
        // Check roles
        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE");
        assertTrue(staking.hasRole(staking.MANAGER_ROLE(), admin), "Admin should have MANAGER_ROLE");
        assertTrue(staking.hasRole(staking.OPERATOR_ROLE(), operator), "Operator should have OPERATOR_ROLE");
        
        // Check minimum stake amount
        assertEq(staking.getMinimumStakeAmount(), minStakeAmount, "Minimum stake amount should be set correctly");
        
        // Check oracle address
        assertEq(staking.getOracle(), address(oracle), "Oracle address should be set correctly");
        
        // Check time intervals are 1 hour
        assertEq(staking.getMinStakeInterval(), MIN_TIME_INTERVAL, "Min stake interval should be 1 hour");
        assertEq(staking.getMinUnstakeInterval(), MIN_TIME_INTERVAL, "Min unstake interval should be 1 hour");
        assertEq(staking.getMinClaimInterval(), MIN_TIME_INTERVAL, "Min claim interval should be 1 hour");
    }
    
    function test_stake_BasicFunctionality() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
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
    
    function test_stake_RevertWhen_DisabledValidator() public {
        // Add validator but set it as disabled
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Disabled);
        
        uint256 stakeAmount = 1 ether;
        
        // Try to stake to disabled validator
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("ValidatorNotEnabled(string)", validatorId1));
        staking.stake{value: stakeAmount}(validatorId1);
        vm.stopPrank();
    }
    
    function test_stake_RevertWhen_InsufficientAmount() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Try to stake less than minimum amount
        uint256 stakeAmount = 0.05 ether; // Less than minimum (0.1 ether)
        
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount(uint256,uint256)", stakeAmount, minStakeAmount));
        staking.stake{value: stakeAmount}(validatorId1);
        vm.stopPrank();
    }
    
    function testFuzz_stake_ValidAmounts(uint256 amount) public {
        // Bound amount to reasonable values (between min and 5 ETH)
        vm.assume(amount >= minStakeAmount && amount <= 5 ether);
        
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Ensure user has enough balance
        vm.deal(user1, amount);
        
        // Stake to validator
        vm.prank(user1);
        staking.stake{value: amount}(validatorId1);
        
        // Check user stake
        INativeStaking.UserStake memory userStake = staking.getUserStake(user1, validatorId1);
        assertEq(userStake.amount, amount, "User stake amount should match");
    }
    
    function test_initiateUnstake_BasicProcess() public {
        // Add validator first
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Stake first
        uint256 stakeAmount = 1 ether;
        vm.deal(user1, stakeAmount);
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Wait for unstake interval
        vm.warp(block.timestamp + MIN_TIME_INTERVAL);
        
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
    
    function test_initiateUnstake_RevertWhen_TooEarly() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Stake
        uint256 stakeAmount = 1 ether;
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Try to unstake immediately (before min time interval)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("TimeTooShort(uint256,uint256)", MIN_TIME_INTERVAL, 0));
        staking.initiateUnstake(validatorId1);
    }
    
    function test_initiateRewardClaim_Process() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        uint256 stakeAmount = 1 ether;
        uint256 rewardAmount = 0.1 ether;
        
        // Set MPX price for proper conversion
        oracle.setMPXPrice(0.01 ether);  // 1 MPX = 0.01 XFI
        
        // Stake to validator
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Wait for claim interval
        vm.warp(block.timestamp + MIN_TIME_INTERVAL);
        
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
    
    function test_initiateRewardClaim_RevertWhen_TooEarly() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        uint256 stakeAmount = 1 ether;
        
        // Stake to validator
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Try to claim immediately (before min time interval)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("TimeTooShort(uint256,uint256)", MIN_TIME_INTERVAL, 0));
        staking.initiateRewardClaim(validatorId1);
    }
    
    function test_migrateStake_ValidMigration() public {
        // Add validators
        vm.startPrank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        staking.setValidatorStatus(validatorId2, INativeStaking.ValidatorStatus.Enabled);
        vm.stopPrank();
        
        uint256 stakeAmount = 1 ether;
        
        // Stake to first validator
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Setup migration
        vm.prank(admin);
        staking.setupValidatorMigration(validatorId1, validatorId2);
        
        // Warp time to be able to migrate (stake time interval)
        vm.warp(block.timestamp + MIN_TIME_INTERVAL);
        
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
    
    function test_migrateStake_RevertWhen_MigrationNotSetup() public {
        // Add validators
        vm.startPrank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        staking.setValidatorStatus(validatorId2, INativeStaking.ValidatorStatus.Enabled);
        vm.stopPrank();
        
        uint256 stakeAmount = 1 ether;
        
        // Stake to first validator
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Wait for proper time
        vm.warp(block.timestamp + MIN_TIME_INTERVAL);
        
        // Try to migrate without setup
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("ValidatorNotDeprecated(string)", validatorId1));
        staking.migrateStake(validatorId1, validatorId2);
    }

    function test_CompleteStakingWorkflow() public {
        // Use a properly formatted validator ID
        string memory validatorId = validatorId1;
        
        // Enable validator
        vm.startPrank(admin);
        staking.setValidatorStatus(validatorId, INativeStaking.ValidatorStatus.Enabled);
        vm.stopPrank();
        
        // Stake
        uint256 stakeAmount = 1 ether;
        vm.startPrank(user1);
        staking.stake{value: stakeAmount}(validatorId);
        vm.stopPrank();
        
        // Verify stake
        INativeStaking.UserStake memory userStake = staking.getUserStake(user1, validatorId);
        assertEq(userStake.amount, stakeAmount);
        
        // Wait for unstake interval
        vm.warp(block.timestamp + MIN_TIME_INTERVAL);
        
        // Initiate unstake
        vm.startPrank(user1);
        staking.initiateUnstake(validatorId);
        vm.stopPrank();
        
        // Verify unstake initiated
        assertTrue(staking.isUnstakeInProcess(user1, validatorId));
        
        // Complete unstake by operator
        vm.startPrank(operator);
        staking.completeUnstake(user1, validatorId, stakeAmount);
        vm.stopPrank();
        
        // Verify stake is now 0
        userStake = staking.getUserStake(user1, validatorId);
        assertEq(userStake.amount, 0);
    }
    
    function test_TimeConstraints_SkippingTime() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Set user balance
        vm.deal(user1, 5 ether);
        
        // Skip ahead in time to avoid any time-too-short errors
        vm.warp(block.timestamp + MIN_TIME_INTERVAL * 2);
        
        // Stake should work
        vm.prank(user1);
        staking.stake{value: 1 ether}(validatorId1);
        
        // Skip ahead in time to allow unstaking
        vm.warp(block.timestamp + MIN_TIME_INTERVAL * 2);
        
        // Unstake should work after time passes
        vm.prank(user1);
        staking.initiateUnstake(validatorId1);
        
        // Verify unstake is in process
        assertTrue(staking.isUnstakeInProcess(user1, validatorId1));
        
        // Complete unstake as operator
        vm.prank(operator);
        staking.completeUnstake(user1, validatorId1, 1 ether);
        
        // Verify stake is now 0
        INativeStaking.UserStake memory userStake = staking.getUserStake(user1, validatorId1);
        assertEq(userStake.amount, 0);
    }
    
    function test_completeUnstake_RevertWhen_UnauthorizedOperator() public {
        // Add validator
        vm.prank(admin);
        staking.setValidatorStatus(validatorId1, INativeStaking.ValidatorStatus.Enabled);
        
        // Stake
        uint256 stakeAmount = 1 ether;
        vm.prank(user1);
        staking.stake{value: stakeAmount}(validatorId1);
        
        // Wait minimum interval and initiate unstake
        vm.warp(block.timestamp + MIN_TIME_INTERVAL);
        vm.prank(user1);
        staking.initiateUnstake(validatorId1);
        
        // Try to complete unstake with unauthorized account (user2)
        vm.prank(user2);
        
        // Use direct string assertion instead of encoding the error
        vm.expectRevert("AccessControl: account 0x0000000000000000000000000000000000000004 is missing role 0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929");
        staking.completeUnstake(user1, validatorId1, stakeAmount);
    }
} 