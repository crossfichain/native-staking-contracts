// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/NativeStaking.sol";
import "../../src/interfaces/INativeStaking.sol";
import "../mocks/MockOracle.sol";

contract NativeStakingE2ETest is Test {
    NativeStaking public staking;
    MockOracle public oracle;
    
    // Roles
    address public admin = address(1);
    address public manager = address(2);
    address public operator = address(3);
    
    // Users
    address public user1 = address(10);
    address public user2 = address(11);
    address public user3 = address(12);
    address public user4 = address(13);
    address public user5 = address(14);
    address public user6 = address(15);
    address public user7 = address(16);
    address public user8 = address(17);
    address public user9 = address(18);
    address public user10 = address(19);
    
    // Validators
    string[] public validatorIds;
    
    // Contract settings
    uint256 public minStakeAmount = 0.1 ether;
    uint256 public testStakeAmount = 1 ether;
    uint256 public testUnstakeAmount = 0.5 ether;
    uint256 public testRewardAmount = 0.05 ether;
    
    function setUp() public {
        // Setup validator IDs (10 validator test cases)
        validatorIds.push("mxvaloper1gza5y94kal25eawsenl56th8kdyujszmcsxcgs");
        validatorIds.push("mxvaloper1jp0m7ynwtvrknzlmdzargmd59mh8n9gkh9yfwm");
        validatorIds.push("mxvaloper1rfza8qfktwy46ujrundtx5s5th6dq8vfnwscp3");
        validatorIds.push("mxvaloper12w023r3vjjmhk8nss9u59np22mjsj8ykwrlxs7");
        validatorIds.push("mxvaloper1zgrx9jjqrfye8swylcmrxq3k92e9j872s9amqu");
        validatorIds.push("mxvaloper1kjr5gh0w3hrxw9r7e4pjw6vz5kywupm79t58n4");
        validatorIds.push("mxvaloper1lthswtdl3dzkppq3ee3kn4jm6dkxdp79t8xq63");
        validatorIds.push("mxvaloper1w0m48j6zejl65pwrt8d8f88jdsjfpne4g7qr5j");
        validatorIds.push("mxvaloper1qj452fr5c8r59dtv5ullke776e07x5pk6umlh4");
        validatorIds.push("mxvaloper1wsgm3jlgcxq7vftldz7hfmwfgq98hruj9yjgr5");
        
        // Deploy Oracle
        oracle = new MockOracle();
        
        // Deploy NativeStaking contract
        staking = new NativeStaking();
        
        // Initialize contract
        staking.initialize(admin, minStakeAmount, address(oracle));
        
        // Setup roles
        vm.startPrank(admin);
        bytes32 managerRole = staking.MANAGER_ROLE();
        bytes32 operatorRole = staking.OPERATOR_ROLE();
        staking.grantRole(managerRole, manager);
        staking.grantRole(operatorRole, operator);
        
        // Set smaller time intervals for testing
        staking.setMinStakeInterval(1 hours);
        staking.setMinUnstakeInterval(1 hours);
        staking.setMinClaimInterval(1 hours);
        vm.stopPrank();
        
        // Fund test accounts (10 ether each)
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
        vm.deal(user4, 10 ether);
        vm.deal(user5, 10 ether);
        vm.deal(user6, 10 ether);
        vm.deal(user7, 10 ether);
        vm.deal(user8, 10 ether);
        vm.deal(user9, 10 ether);
        vm.deal(user10, 10 ether);
        
        // Fund contract with some initial ETH for rewards
        vm.deal(address(staking), 10 ether);
        
        // Add all validators as a manager
        vm.startPrank(manager);
        for (uint i = 0; i < validatorIds.length; i++) {
            bool isEnabled = i < 8; // First 8 validators enabled, last 2 disabled
            INativeStaking.ValidatorStatus status = isEnabled ? INativeStaking.ValidatorStatus.Enabled : INativeStaking.ValidatorStatus.Disabled;
            staking.setValidatorStatus(validatorIds[i], status);
        }
        vm.stopPrank();
    }
    
    function testFullStake() public {
        // Set initial timestamp
        vm.warp(3700); // Set timestamp to allow for time intervals
        
        _testMultipleUserStaking();
    }
    
    function testValidatorStatus() public {
        // Set initial timestamp
        vm.warp(3700);
        
        _testMultipleUserStaking();
        // Move time forward to satisfy time restrictions
        vm.warp(block.timestamp + 4 hours);
        _testValidatorStatusUpdate();
    }
    
    function testUnstaking() public {
        // Set initial timestamp
        vm.warp(3700);
        
        _testMultipleUserStaking();
        // Move time forward to satisfy time restrictions
        vm.warp(block.timestamp + 4 hours);
        _testUnstakeFlow();
    }
    
    function testRewards() public {
        // Set initial timestamp
        vm.warp(3700);
        
        _testMultipleUserStaking();
        // Move time forward to satisfy time restrictions
        vm.warp(block.timestamp + 4 hours);
        _testRewardClaiming();
    }
    
    function testMigration() public {
        // Set initial timestamp
        vm.warp(3700);
        
        _testMultipleUserStaking();
        // Move time forward to satisfy time restrictions
        vm.warp(block.timestamp + 4 hours);
        _testValidatorMigration();
    }
    
    function testEmergency() public {
        // Set initial timestamp
        vm.warp(3700);
        
        _testMultipleUserStaking();
        // Move time forward to satisfy time restrictions
        vm.warp(block.timestamp + 4 hours);
        _testEmergencyWithdrawal();
    }
    
    function testParams() public {
        // Set initial timestamp
        vm.warp(3700);
        
        _testMultipleUserStaking();
        // Move time forward to satisfy time restrictions
        vm.warp(block.timestamp + 4 hours);
        _testParameterUpdates();
    }
    
    function testPause() public {
        // Set initial timestamp
        vm.warp(3700);
        
        _testMultipleUserStaking();
        // Move time forward to satisfy time restrictions
        vm.warp(block.timestamp + 4 hours);
        _testPauseUnpause();
    }
    
    function testTimeRestrictions() public {
        // Set initial timestamp to a higher value to avoid time constraint issues
        vm.warp(3700);
        
        // First stake with a user
        string memory validatorId = validatorIds[1];
        
        vm.startPrank(user7);
        staking.stake{value: 1 ether}(validatorId);
        
        // Try to unstake immediately (should fail due to time restriction)
        vm.expectRevert(abi.encodeWithSignature("TimeTooShort(uint256,uint256)", staking.getMinUnstakeInterval(), 0));
        staking.initiateUnstake(validatorId);
        vm.stopPrank();
        
        // Warp time forward past the unstake restriction
        vm.warp(block.timestamp + 2 hours);
        
        // Now unstake should work
        vm.prank(user7);
        staking.initiateUnstake(validatorId);
    }
    
    function testEdgeCases() public {
        // Set initial timestamp
        vm.warp(3700);
        
        // First stake with all users to setup state
        _testMultipleUserStaking();
        
        // Move time forward to satisfy time restrictions
        vm.warp(block.timestamp + 4 hours);
        
        // Test 1: Stake to non-existent validator
        vm.prank(user8);
        vm.expectRevert(abi.encodeWithSignature("InvalidValidatorId(string)", "nonexistentvalidator123"));
        staking.stake{value: 1 ether}("nonexistentvalidator123");
        
        // Test 2: Double unstake attempt
        // User 6 has staked to validatorIds[0] in _testMultipleUserStaking
        string memory validatorId = validatorIds[0];
        
        // Verify the user has a stake first
        INativeStaking.UserStake memory user6Stake = staking.getUserStake(user6, validatorId);
        assertEq(user6Stake.amount, testStakeAmount, "User6 should have stake to validator0");
        
        // Initiate first unstake
        vm.prank(user6);
        staking.initiateUnstake(validatorId);
        
        // Verify unstake was initiated correctly and the full amount is marked for unstaking
        (bool inProcess, uint256 unstakeAmount) = staking.getUnstakeStatus(user6, validatorId);
        assertTrue(inProcess, "Unstake should be in process");
        assertEq(unstakeAmount, testStakeAmount, "Full amount should be marked for unstaking");
        
        // We need to move time forward again to be able to test the UnstakeInProcess error
        // otherwise we'll hit the TimeTooShort error
        vm.warp(block.timestamp + 2 hours);
        
        // Try a second unstake while first is in process
        vm.prank(user6);
        vm.expectRevert(abi.encodeWithSignature("UnstakeInProcess()"));
        staking.initiateUnstake(validatorId);
    }
    
    function _testMultipleUserStaking() private {
        // Users stake to different validators
        for (uint i = 0; i < 5; i++) {
            address user = address(uint160(10 + i)); // user1 through user5
            string memory validatorId = validatorIds[i];
            
            uint256 userBalanceBefore = user.balance;
            
            vm.prank(user);
            staking.stake{value: testStakeAmount}(validatorId);
            
            // Verify stake was successful
            INativeStaking.UserStake memory userStake = staking.getUserStake(user, validatorId);
            assertEq(userStake.amount, testStakeAmount, "Stake amount incorrect");
            assertFalse(userStake.inUnstakeProcess, "Should not be in unstake process");
            
            // Verify user balance decreased
            assertEq(user.balance, userBalanceBefore - testStakeAmount, "User balance not decreased correctly");
            
            // Verify validator data updated
            {
                INativeStaking.Validator memory validatorObj = staking.getValidator(validatorId);
                assertGt(validatorObj.totalStaked, 0, "Validator total staked should be > 0");
                assertGt(validatorObj.uniqueStakers, 0, "Validator should have stakers");
            }
        }
        
        // Multiple users stake to the same validator
        string memory popularValidator = validatorIds[0];
        
        for (uint i = 5; i < 10; i++) {
            address user = address(uint160(10 + i)); // user6 through user10
            
            vm.prank(user);
            staking.stake{value: testStakeAmount}(popularValidator);
            
            // Verify stake was successful
            INativeStaking.UserStake memory userStake = staking.getUserStake(user, popularValidator);
            assertEq(userStake.amount, testStakeAmount, "Stake amount incorrect");
        }
        
        // Verify validator data reflects all stakers
        {
            INativeStaking.Validator memory validatorObj = staking.getValidator(popularValidator);
            assertEq(validatorObj.uniqueStakers, 6, "Validator should have 6 unique stakers");
            assertEq(validatorObj.totalStaked, testStakeAmount * 6, "Total staked amount incorrect");
        }
    }
    
    function _testValidatorStatusUpdate() private {
        // Enable a previously disabled validator
        string memory disabledValidator = validatorIds[8];
        
        // Verify it's currently disabled
        {
            INativeStaking.Validator memory validatorObj = staking.getValidator(disabledValidator);
            assertEq(uint8(validatorObj.status), uint8(INativeStaking.ValidatorStatus.Disabled), "Validator should be disabled");
        }
        
        // Update status to enabled
        vm.prank(manager);
        staking.setValidatorStatus(disabledValidator, INativeStaking.ValidatorStatus.Enabled);
        
        // Verify status changed
        {
            INativeStaking.Validator memory validatorObj = staking.getValidator(disabledValidator);
            assertEq(uint8(validatorObj.status), uint8(INativeStaking.ValidatorStatus.Enabled), "Validator should be enabled");
        }
        
        // Verify user can now stake to this validator
        vm.prank(user10);
        staking.stake{value: testStakeAmount}(disabledValidator);
        
        // Change a validator to deprecated
        string memory deprecateValidator = validatorIds[1];
        
        vm.prank(manager);
        staking.setValidatorStatus(deprecateValidator, INativeStaking.ValidatorStatus.Deprecated);
        
        // Verify status changed
        {
            INativeStaking.Validator memory validatorObj = staking.getValidator(deprecateValidator);
            assertEq(uint8(validatorObj.status), uint8(INativeStaking.ValidatorStatus.Deprecated), "Validator should be deprecated");
        }
    }
    
    function _testUnstakeFlow() private {
        // Test unstake flow for user1 and validatorIds[0]
        string memory validatorId = validatorIds[0];
        
        // Initiate unstake
        vm.prank(user1);
        staking.initiateUnstake(validatorId);
        
        // Verify unstake initiated
        INativeStaking.UserStake memory userStake = staking.getUserStake(user1, validatorId);
        assertTrue(userStake.inUnstakeProcess, "Should be in unstake process");
        assertGt(userStake.lastUnstakeInitiatedAt, 0, "Unstake initiated timestamp should be set");
        
        // Verify the full amount is set for unstaking
        (bool inProcess, uint256 unstakeAmount) = staking.getUnstakeStatus(user1, validatorId);
        assertTrue(inProcess, "Should be in unstake process");
        assertEq(unstakeAmount, testStakeAmount, "Full stake amount should be marked for unstaking");
        
        // Complete unstake
        uint256 user1BalanceBefore = user1.balance;
        
        vm.prank(operator);
        staking.completeUnstake(user1, validatorId, testStakeAmount);
        
        // Verify unstake completed
        userStake = staking.getUserStake(user1, validatorId);
        assertFalse(userStake.inUnstakeProcess, "Should not be in unstake process");
        assertEq(userStake.amount, 0, "Remaining stake amount should be zero");
        
        // Verify user received funds
        assertEq(user1.balance, user1BalanceBefore + testStakeAmount, "User balance not increased correctly");

        // Check validator was enabled and in the correct status
        {
            INativeStaking.Validator memory validatorObj = staking.getValidator(validatorId);
            assertTrue(bytes(validatorObj.id).length > 0, "Validator should be added");
            assertEq(uint8(validatorObj.status), uint8(INativeStaking.ValidatorStatus.Enabled), "Validator should be enabled");
        }
    }
    
    function _testRewardClaiming() private {
        string memory validatorId = validatorIds[2];
        
        // Set MPX price for proper conversion
        oracle.setMPXPrice(0.01 ether);  // 1 MPX = 0.01 XFI
        
        // Initiate reward claim
        vm.prank(user3);
        staking.initiateRewardClaim(validatorId);
        
        // Complete reward claim
        uint256 user3BalanceBefore = user3.balance;
        
        // Make sure operator has enough ETH
        vm.deal(operator, 5 ether);
        
        vm.prank(operator);
        staking.completeRewardClaim{value: testRewardAmount}(user3, validatorId, false);
        
        // Verify user received rewards
        assertEq(user3.balance, user3BalanceBefore + testRewardAmount, "User should receive reward");
    }
    
    function _testValidatorMigration() private {
        // Setup migration from validator 3 to validator 4
        string memory fromValidator = validatorIds[3];
        string memory toValidator = validatorIds[4];
        
        // Setup migration
        vm.prank(manager);
        staking.setupValidatorMigration(fromValidator, toValidator);
        
        // Warp time forward to allow migration
        vm.warp(block.timestamp + 2 hours);
        
        // User4 migrates stake
        uint256 stakeBefore = staking.getUserStake(user4, fromValidator).amount;
        
        vm.prank(user4);
        staking.migrateStake(fromValidator, toValidator);
        
        // Verify stake was migrated
        INativeStaking.UserStake memory fromStake = staking.getUserStake(user4, fromValidator);
        INativeStaking.UserStake memory toStake = staking.getUserStake(user4, toValidator);
        
        assertEq(fromStake.amount, 0, "Original stake should be 0");
        assertEq(toStake.amount, stakeBefore, "New stake should match original amount");
        
        // Verify validator stats updated
        INativeStaking.Validator memory fromVal = staking.getValidator(fromValidator);
        INativeStaking.Validator memory toVal = staking.getValidator(toValidator);
        
        assertEq(fromVal.uniqueStakers, 0, "Original validator should have 0 stakers");
        assertEq(toVal.uniqueStakers, 2, "New validator should have 2 stakers");
    }
    
    function _testEmergencyWithdrawal() private {
        // User5 initiates emergency withdrawal
        vm.prank(user5);
        staking.initiateEmergencyWithdrawal();
        
        // Verify emergency withdrawal request recorded
        assertTrue(staking.isEmergencyWithdrawalRequested(user5), "Emergency withdrawal should be requested");
        
        // Get user balance before and total staked amount
        uint256 user5BalanceBefore = user5.balance;
        uint256 totalStaked = staking.getUserTotalStaked(user5);
        
        // Complete emergency withdrawal
        vm.prank(operator);
        staking.completeEmergencyWithdrawal(user5, totalStaked);
        
        // Verify user received all staked funds
        assertEq(user5.balance, user5BalanceBefore + totalStaked, "User should receive all staked funds");
        assertEq(staking.getUserTotalStaked(user5), 0, "User total staked should be 0");
        
        // Verify validators list is cleared
        string[] memory userValidators = staking.getUserValidators(user5);
        assertEq(userValidators.length, 0, "User should have no validators after emergency withdrawal");
    }
    
    function _testParameterUpdates() private {
        // Update minimum stake amount
        uint256 newMinStake = 0.2 ether;
        
        vm.prank(admin);
        staking.setMinimumStakeAmount(newMinStake);
        
        // Verify updated
        assertEq(staking.getMinimumStakeAmount(), newMinStake, "Min stake amount should be updated");
        
        // Verify small stakes are rejected
        vm.prank(user6);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount(uint256,uint256)", 0.15 ether, 0.2 ether));
        staking.stake{value: 0.15 ether}(validatorIds[5]);
        
        // Update time intervals
        uint256 newStakeInterval = 2 days;
        uint256 newUnstakeInterval = 3 days;
        uint256 newClaimInterval = 4 days;
        
        vm.startPrank(admin);
        staking.setMinStakeInterval(newStakeInterval);
        staking.setMinUnstakeInterval(newUnstakeInterval);
        staking.setMinClaimInterval(newClaimInterval);
        vm.stopPrank();
        
        // Verify intervals updated
        assertEq(staking.getMinStakeInterval(), newStakeInterval, "Stake interval should be updated");
        assertEq(staking.getMinUnstakeInterval(), newUnstakeInterval, "Unstake interval should be updated");
        assertEq(staking.getMinClaimInterval(), newClaimInterval, "Claim interval should be updated");
    }
    
    function _testPauseUnpause() private {
        // Pause staking
        vm.prank(admin);
        staking.pauseStaking();
        
        // Verify staking is paused
        assertTrue(staking.paused(), "Contract should be paused");
        
        // Verify stake reverts when paused
        vm.prank(user7);
        vm.expectRevert("Pausable: paused");
        staking.stake{value: 1 ether}(validatorIds[6]);
        
        // Unpause staking
        vm.prank(admin);
        staking.unpauseStaking();
        
        // Verify staking is unpaused
        assertFalse(staking.paused(), "Contract should be unpaused");
        
        // Verify staking works again
        vm.prank(user7);
        staking.stake{value: 1 ether}(validatorIds[6]);
    }
} 