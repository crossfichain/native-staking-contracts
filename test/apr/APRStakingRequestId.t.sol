// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./APRStakingBase.t.sol";
import "../../src/core/APRStaking.sol";

/**
 * @title APRStakingRequestIdTest
 * @dev Tests for the APRStaking contract's requestId handling
 * Focuses on verifying that structured requestIds are correctly handled
 */
contract APRStakingRequestIdTest is APRStakingBase {
    // Test globals
    uint256 public stakeAmount = 100 ether;
    uint256 public unstakeAmount = 50 ether;
    uint256 public requestId;

    function setUp() public override {
        super.setUp();
        
        // Set a reasonable unbonding period for tests (5 seconds)
        vm.startPrank(ADMIN);
        oracle.setUnbondingPeriod(5);
        
        // Set validator stake for the test
        oracle.setValidatorStake(USER, VALIDATOR_ID, stakeAmount);
        vm.stopPrank();
        
        // Stake some tokens with USER for testing
        stake(USER, stakeAmount);
    }
    
    /**
     * @dev Test unstaking and claiming with a structured requestId
     * Verifies the fix for the "Invalid requestId" issue
     */
    function testStructuredRequestIdHandling() public {
        // Request to unstake
        vm.startPrank(USER);
        requestId = manager.unstakeAPR(unstakeAmount, VALIDATOR_ID);
        vm.stopPrank();
        
        // Verify that the requestId is structured (greater than 2^32)
        assertTrue(manager.isStructuredRequestId(requestId), "RequestId should be structured");
        
        // Extract sequence from the structured ID
        uint256 sequence = manager.getSequenceFromId(requestId);
        
        // Log the requestId and its sequence component for debugging
        console.log("Structured RequestId:", requestId);
        console.log("Sequence component:", sequence);
        
        // Advance time past the unbonding period
        advanceTime(6); // 6 seconds, just past the 5-second unbonding period
        
        // Try to claim with the structured requestId (this would have failed before the fix)
        vm.startPrank(USER);
        uint256 claimed = manager.claimUnstakeAPR(requestId);
        vm.stopPrank();
        
        // Verify successful claim
        assertEq(claimed, unstakeAmount, "Should claim the correct unstake amount");
    }
    
    /**
     * @dev Test multiple sequential unstake requests
     * Ensures multiple requestIds are handled correctly
     */
    function testMultipleRequestIds() public {
        // First unstake request
        vm.startPrank(USER);
        uint256 requestId1 = manager.unstakeAPR(20 ether, VALIDATOR_ID);
        vm.stopPrank();
        
        // Wait until out of unbonding period for the validator
        advanceTime(6);
        
        // Second unstake request
        vm.startPrank(USER);
        uint256 requestId2 = manager.unstakeAPR(20 ether, VALIDATOR_ID);
        vm.stopPrank();
        
        // Log both requestIds
        console.log("RequestId 1:", requestId1);
        console.log("RequestId 2:", requestId2);
        
        advanceTime(6);
        
        // Claim both requests (should succeed with the fix)
        vm.startPrank(USER);
        uint256 claimed1 = manager.claimUnstakeAPR(requestId1);
        uint256 claimed2 = manager.claimUnstakeAPR(requestId2);
        vm.stopPrank();
        
        assertEq(claimed1, 20 ether, "First claim should be 20 ether");
        assertEq(claimed2, 20 ether, "Second claim should be 20 ether");
    }
    
    /**
     * @dev Test the edge case where requestId is exactly 2^32
     * This is the boundary between structured and non-structured IDs
     */
    function testRequestIdBoundary() public {
        // Create a mock scenario with a manually crafted requestId at the boundary
        uint256 boundaryId = 4294967296; // 2^32
        
        // Verify detection of structured ID
        assertTrue(manager.isStructuredRequestId(boundaryId), "Boundary ID should be detected as structured");
        assertTrue(!manager.isStructuredRequestId(boundaryId - 1), "Below boundary should not be structured");
        
        // Request to unstake with normal flow to get a real structured ID
        vm.startPrank(USER);
        uint256 realRequestId = manager.unstakeAPR(unstakeAmount, VALIDATOR_ID);
        vm.stopPrank();
        
        // Verify structured ID detection
        assertTrue(manager.isStructuredRequestId(realRequestId), "Real request ID should be structured");
        
        // Log the IDs
        console.log("Boundary ID:", boundaryId);
        console.log("Real Request ID:", realRequestId);
    }
} 