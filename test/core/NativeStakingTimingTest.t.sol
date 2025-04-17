// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/NativeStaking.sol";
import "../../src/interfaces/INativeStaking.sol";
import "../mocks/MockOracle.sol";

contract NativeStakingTimingTest is Test {
    NativeStaking public nativeStaking;
    MockOracle public oracle;
    
    address public admin = address(1);
    address public operator = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    
    string public validatorId = "mxvaloper1gza5y94kal25eawsenl56th8kdyujszmcsxcgs";
    
    uint256 public constant MINIMUM_STAKE_AMOUNT = 100 ether;
    uint256 public constant MIN_STAKE_INTERVAL = 1 days;
    uint256 public constant MIN_UNSTAKE_INTERVAL = 15 days;
    uint256 public constant MIN_CLAIM_INTERVAL = 7 days;
    
    function setUp() public {
        // Deploy Oracle contract
        oracle = new MockOracle();
        
        // Deploy NativeStaking contract
        nativeStaking = new NativeStaking();
        
        // Initialize contract
        nativeStaking.initialize(admin, MINIMUM_STAKE_AMOUNT, address(oracle));
        
        // Setup roles
        vm.startPrank(admin);
        nativeStaking.grantRole(nativeStaking.OPERATOR_ROLE(), operator);
        
        // Set time intervals
        nativeStaking.setMinStakeInterval(MIN_STAKE_INTERVAL);
        nativeStaking.setMinUnstakeInterval(MIN_UNSTAKE_INTERVAL);
        nativeStaking.setMinClaimInterval(MIN_CLAIM_INTERVAL);
        
        // Add validator
        nativeStaking.setValidatorStatus(validatorId, INativeStaking.ValidatorStatus.Enabled);
        vm.stopPrank();
        
        // Fund test accounts
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        
        // Set initial timestamp to avoid underflow issues
        vm.warp(100000);
    }
    
    function testStakeTimelockBehavior() public {
        // Initial stake
        vm.prank(user1);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validatorId);
        
        // Try to stake again immediately, should fail
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("TimeTooShort(uint256,uint256)", MIN_STAKE_INTERVAL, 0));
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validatorId);
        
        // Warp forward to just before the min stake interval
        vm.warp(block.timestamp + MIN_STAKE_INTERVAL - 1);
        
        // User2 should be able to stake at any time
        vm.prank(user2);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validatorId);
    }
    
    function testUnstakeProcess() public {
        // Initial stake
        vm.prank(user1);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validatorId);
        
        // Attempt to unstake too soon
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("TimeTooShort(uint256,uint256)", MIN_UNSTAKE_INTERVAL, 0));
        nativeStaking.initiateUnstake(validatorId);
        
        // Warp forward past the min unstake interval
        vm.warp(block.timestamp + MIN_UNSTAKE_INTERVAL + 1);
        
        // Now unstake should work
        vm.prank(user1);
        nativeStaking.initiateUnstake(validatorId);
        
        // Verify unstake initiated
        assertTrue(nativeStaking.isUnstakeInProcess(user1, validatorId));
    }
    
    function testClaimProcess() public {
        // Set MPX price
        oracle.setMPXPrice(0.01 ether);
        
        // Initial stake
        vm.prank(user1);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validatorId);
        
        // Attempt to claim too soon
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("TimeTooShort(uint256,uint256)", MIN_CLAIM_INTERVAL, 0));
        nativeStaking.initiateRewardClaim(validatorId);
        
        // Warp forward past the min claim interval
        vm.warp(block.timestamp + MIN_CLAIM_INTERVAL + 1);
        
        // Now claim should work
        vm.prank(user1);
        nativeStaking.initiateRewardClaim(validatorId);
        
        // Complete claim by operator
        vm.deal(operator, 10 ether);
        vm.prank(operator);
        nativeStaking.completeRewardClaim{value: 1 ether}(user1, validatorId, false);
    }
    
    function testStakeUpdatesAllTimestamps() public {
        // Initial stake
        vm.prank(user1);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validatorId);
        
        // Get timestamps after initial stake
        INativeStaking.UserStake memory stake = nativeStaking.getUserStake(user1, validatorId);
        uint256 initialStakeTime = stake.stakedAt;
        uint256 initialUnstakeTime = stake.lastUnstakeInitiatedAt;
        uint256 initialClaimTime = stake.lastClaimInitiatedAt;
        
        // Ensure all timestamps are initially set
        assertEq(initialStakeTime, block.timestamp);
        assertEq(initialUnstakeTime, 0);
        assertEq(initialClaimTime, 0);
    }
    
    function testMultipleStakesTimestampBehavior() public {
        // Initial stake with user1
        vm.prank(user1);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validatorId);
        
        // Initial timestamp
        uint256 user1InitialStakeTime = nativeStaking.getUserStake(user1, validatorId).stakedAt;
        
        // Move time forward
        vm.warp(block.timestamp + MIN_STAKE_INTERVAL + 1);
        
        // Second stake with user2
        vm.prank(user2);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validatorId);
        
        // Second timestamp
        uint256 user2StakeTime = nativeStaking.getUserStake(user2, validatorId).stakedAt;
        
        // Verify timestamps are different
        assertGt(user2StakeTime, user1InitialStakeTime);
        assertEq(user2StakeTime, block.timestamp);
    }
} 