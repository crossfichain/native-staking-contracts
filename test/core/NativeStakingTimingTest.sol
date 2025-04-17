// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {NativeStaking} from "../../src/NativeStaking.sol";
import {UnifiedOracle} from "../../src/periphery/UnifiedOracle.sol";
import {MockDIAOracle} from "../../script/mocks/MockDiaOracle.sol";
import {INativeStaking} from "../../src/interfaces/INativeStaking.sol";

/**
 * @title NativeStakingTimingTest
 * @notice Tests for timing behaviors in NativeStaking contract
 */
contract NativeStakingTimingTest is Test {
    NativeStaking public nativeStaking;
    UnifiedOracle public oracle;
    MockDIAOracle public mockDiaOracle;
    
    address public admin = address(1);
    address public operator = address(2);
    address public user1 = address(3);
    
    uint256 public constant MINIMUM_STAKE_AMOUNT = 100 ether;
    uint256 public constant MIN_STAKE_INTERVAL = 1 days;
    uint256 public constant MIN_UNSTAKE_INTERVAL = 15 days;
    uint256 public constant MIN_CLAIM_INTERVAL = 7 days;
    
    string public validator1 = "mxvaloper1gza5y94kal25eawsenl56th8kdyujszmcsxcgs";
    string public validator2 = "mxvaloper1jp0m7ynwtvrknzlmdzargmd59mh8n9gkh9yfwm";
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy and configure mock oracle
        mockDiaOracle = new MockDIAOracle();
        mockDiaOracle.setPrice("XFI/USD", 900000000); // $0.90 with 8 decimals
        
        // Deploy oracle
        oracle = new UnifiedOracle();
        oracle.initialize(address(mockDiaOracle));
        oracle.setPrice("XFI", 13 * 10**16); // $0.13 with 18 decimals
        oracle.setMPXPrice(2 * 10**16); // $0.02 with 18 decimals
        
        // Deploy native staking contract
        nativeStaking = new NativeStaking();
        nativeStaking.initialize(admin, MINIMUM_STAKE_AMOUNT, address(oracle));
        
        // Set time intervals
        nativeStaking.setMinStakeInterval(MIN_STAKE_INTERVAL);
        nativeStaking.setMinUnstakeInterval(MIN_UNSTAKE_INTERVAL);
        nativeStaking.setMinClaimInterval(MIN_CLAIM_INTERVAL);
        
        // Add validators
        nativeStaking.setValidatorStatus(validator1, INativeStaking.ValidatorStatus.Enabled);
        nativeStaking.setValidatorStatus(validator2, INativeStaking.ValidatorStatus.Enabled);
        
        // Setup operator role
        bytes32 operatorRole = nativeStaking.OPERATOR_ROLE();
        nativeStaking.grantRole(operatorRole, operator);
        
        vm.stopPrank();
        
        // Set initial timestamp to avoid timelock issues
        vm.warp(100000);
    }
    
    function testStakeUpdatesAllTimestamps() public {
        vm.startPrank(user1);
        
        // Perform stake
        deal(user1, MINIMUM_STAKE_AMOUNT);
        uint256 currentTimestamp = block.timestamp;
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validator1);
        
        // Check timestamps updated
        (
            INativeStaking.UserStake memory userStake,
            bool canStake,
            bool canUnstake,
            bool canClaim,
            uint256 stakeUnlockTime,
            uint256 unstakeUnlockTime,
            uint256 claimUnlockTime
        ) = nativeStaking.getUserStatus(user1, validator1);
        
        // Verify timestamps are correctly set
        assertEq(stakeUnlockTime, currentTimestamp + MIN_STAKE_INTERVAL);
        assertEq(claimUnlockTime, currentTimestamp + MIN_CLAIM_INTERVAL);
        
        // Check flags
        assertFalse(canStake);
        assertFalse(canUnstake);
        assertFalse(canClaim);
        
        // Advance time to check if flags change
        vm.warp(stakeUnlockTime + 1);
        
        (
            ,
            canStake,
            canUnstake,
            canClaim,
            ,
            ,
            
        ) = nativeStaking.getUserStatus(user1, validator1);
        
        assertTrue(canStake);
        
        vm.stopPrank();
    }
    
    function testStakeTimelockBehavior() public {
        vm.startPrank(user1);
        
        // Perform stake
        deal(user1, MINIMUM_STAKE_AMOUNT);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validator1);
        
        // Check staking is locked
        (
            ,
            ,
            ,
            ,
            uint256 stakeUnlockTime,
            ,
            
        ) = nativeStaking.getUserStatus(user1, validator1);
        
        // Try to stake again before timelock expires
        deal(user1, MINIMUM_STAKE_AMOUNT);
        vm.expectRevert(abi.encodeWithSignature("TimeTooShort(uint256,uint256)", MIN_STAKE_INTERVAL, 0));
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validator1);
        
        // Advance time to just after unlock
        vm.warp(stakeUnlockTime + 1);
        
        // Check if stake is now allowed
        (
            ,
            bool canStake,
            ,
            ,
            ,
            ,
            
        ) = nativeStaking.getUserStatus(user1, validator1);
        assertTrue(canStake);
        
        // Stake again should now succeed
        deal(user1, MINIMUM_STAKE_AMOUNT);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validator1);
        
        vm.stopPrank();
    }
    
    function testUnstakeProcess() public {
        vm.startPrank(user1);
        
        // Perform stake
        deal(user1, MINIMUM_STAKE_AMOUNT);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validator1);
        
        // Advance time past stake interval AND unstake interval
        vm.warp(block.timestamp + MIN_UNSTAKE_INTERVAL + 1);
        
        // Initiate unstake
        uint256 unstakeTimestamp = block.timestamp;
        nativeStaking.initiateUnstake(validator1);
        
        // Check unstake process is active
        (
            INativeStaking.UserStake memory userStake,
            bool canStake,
            bool canUnstake,
            bool canClaim,
            ,
            ,
            
        ) = nativeStaking.getUserStatus(user1, validator1);
        
        // Verify unstake process status
        assertTrue(userStake.inUnstakeProcess);
        assertFalse(canStake);
        assertFalse(canUnstake);
        assertFalse(canClaim);
        
        vm.stopPrank();
    }
    
    function testClaimProcess() public {
        vm.startPrank(user1);
        
        // Perform stake
        deal(user1, MINIMUM_STAKE_AMOUNT);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validator1);
        
        // Advance time past both claim and unstake intervals to ensure enough time has passed
        vm.warp(block.timestamp + MIN_UNSTAKE_INTERVAL + 1);
        
        // Initiate claim
        nativeStaking.initiateRewardClaim(validator1);
        
        // Check user status after claim
        (
            INativeStaking.UserStake memory userStake,
            bool canStake,
            bool canUnstake,
            bool canClaim,
            ,
            ,
            
        ) = nativeStaking.getUserStatus(user1, validator1);
        
        // Assert the claim status
        assertFalse(canClaim, "Should not be able to claim again until timelock expires");
        
        vm.stopPrank();
    }
    
    function testMultipleStakesTimestampBehavior() public {
        vm.startPrank(user1);
        
        // First stake
        deal(user1, MINIMUM_STAKE_AMOUNT * 3); // Prepare for multiple stakes
        
        uint256 initialTimestamp = block.timestamp;
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validator1);
        
        // Record initial timestamps
        (
            ,
            ,
            ,
            ,
            uint256 initialStakeUnlockTime,
            ,
            uint256 initialClaimUnlockTime
        ) = nativeStaking.getUserStatus(user1, validator1);
        
        // Advance time past stake interval
        vm.warp(initialStakeUnlockTime + 1);
        
        // Second stake
        uint256 secondStakeTimestamp = block.timestamp;
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validator1);
        
        // Check new unlock times
        (
            ,
            ,
            ,
            ,
            uint256 newStakeUnlockTime,
            ,
            uint256 newClaimUnlockTime
        ) = nativeStaking.getUserStatus(user1, validator1);
        
        // Verify both timestamps are updated
        assertEq(newStakeUnlockTime, secondStakeTimestamp + MIN_STAKE_INTERVAL);
        assertEq(newClaimUnlockTime, secondStakeTimestamp + MIN_CLAIM_INTERVAL);
        
        // Verify claiming is locked until new timestamp
        vm.warp(initialClaimUnlockTime + 1); // Time past initial claim unlock
        
        // Should still be unable to claim (new timestamp applies)
        (
            ,
            bool canStake,
            bool canUnstake,
            bool canClaim,
            ,
            ,
            
        ) = nativeStaking.getUserStatus(user1, validator1);
        assertFalse(canClaim);
        
        // Advance to new claim unlock time
        vm.warp(newClaimUnlockTime + 1);
        
        // Now claiming should be possible
        (
            ,
            canStake,
            canUnstake,
            canClaim,
            ,
            ,
            
        ) = nativeStaking.getUserStatus(user1, validator1);
        assertTrue(canClaim);
        
        vm.stopPrank();
    }
    
    function testMultiUserStakeTimelockBehavior() public {
        address user2 = address(4);
        
        // User1 stakes
        vm.startPrank(user1);
        deal(user1, MINIMUM_STAKE_AMOUNT);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validator1);
        vm.stopPrank();
        
        // Check staking is locked for user1
        (
            ,
            bool canStake,
            ,
            ,
            ,
            ,
            
        ) = nativeStaking.getUserStatus(user1, validator1);
        assertFalse(canStake);
        
        // User2 should be able to stake at any time
        vm.startPrank(user2);
        deal(user2, MINIMUM_STAKE_AMOUNT);
        nativeStaking.stake{value: MINIMUM_STAKE_AMOUNT}(validator1);
        vm.stopPrank();
        
        // Verify both users have active stakes by checking their stake amounts
        INativeStaking.UserStake memory user1Stake = nativeStaking.getUserStake(user1, validator1);
        INativeStaking.UserStake memory user2Stake = nativeStaking.getUserStake(user2, validator1);
        
        assertGt(user1Stake.amount, 0, "User1 should have an active stake");
        assertGt(user2Stake.amount, 0, "User2 should have an active stake");
    }
} 