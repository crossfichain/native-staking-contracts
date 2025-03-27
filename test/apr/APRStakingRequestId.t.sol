// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./APRStakingBase.t.sol";
import "../../src/core/APRStaking.sol";

/**
 * @title APRStakingRequestIdTest
 * @dev Tests for the APRStaking contract's requestId handling
 * Focuses on verifying that bytes requestIds are correctly handled
 */
contract APRStakingRequestIdTest is APRStakingBase {
    // Test globals
    uint256 public stakeAmount = 100 ether;
    uint256 public unstakeAmount = 50 ether;
    bytes public requestId;

    function setUp() public override {
        super.setUp();
        
        // Set a reasonable unbonding period for tests (5 seconds)
        vm.startPrank(ADMIN);
        oracle.setUnbondingPeriod(5);
        vm.stopPrank();
        
        // Set validator stake for the test
        vm.startPrank(ADMIN);
        oracle.setValidatorStake(USER, VALIDATOR_ID, stakeAmount);
        vm.stopPrank();
        
        // Make sure USER has enough tokens
        vm.startPrank(ADMIN);
        deal(address(wxfi), USER, stakeAmount * 2);
        deal(address(wxfi), address(manager), stakeAmount * 10); // Ensure manager has enough tokens for tests
        vm.stopPrank();
        
        // Stake some tokens with USER for testing
        vm.startPrank(USER);
        wxfi.approve(address(manager), stakeAmount);
        vm.stopPrank();
        
        stake(USER, stakeAmount);
    }
    
    /**
     * @dev Test unstaking and claiming with a bytes requestId
     * Verifies the new bytes requestId functionality
     */
    function testBytesRequestIdHandling() public {
        // Request to unstake
        vm.startPrank(USER);
        requestId = manager.unstakeAPR(unstakeAmount, VALIDATOR_ID);
        vm.stopPrank();
        
        // Verify that the requestId is not empty
        assertGt(requestId.length, 0, "RequestId should not be empty");
        
        // Print requestId length and hex representation for debugging
        console.log("Bytes RequestId length:", requestId.length);
        console.logBytes(requestId);
        
        // Advance time past the unbonding period
        advanceTime(6); // 6 seconds, just past the 5-second unbonding period
        
        // Try to claim with the bytes requestId
        vm.startPrank(USER);
        uint256 claimed = manager.claimUnstakeAPR(requestId);
        vm.stopPrank();
        
        // Verify successful claim
        assertEq(claimed, unstakeAmount, "Should claim the correct unstake amount");
    }
    
    /**
     * @dev Test multiple sequential unstake requests with bytes requestIds
     * Ensures multiple bytes requestIds are handled correctly
     */
    function testMultipleBytesRequestIds() public {
        // First unstake request
        vm.startPrank(USER);
        bytes memory requestId1 = manager.unstakeAPR(20 ether, VALIDATOR_ID);
        vm.stopPrank();
        
        // Wait until out of unbonding period for the validator
        advanceTime(6);
        
        // Second unstake request
        vm.startPrank(USER);
        bytes memory requestId2 = manager.unstakeAPR(20 ether, VALIDATOR_ID);
        vm.stopPrank();
        
        // Log requestId details
        console.log("RequestId 1 length:", requestId1.length);
        console.logBytes(requestId1);
        console.log("RequestId 2 length:", requestId2.length);
        console.logBytes(requestId2);
        
        advanceTime(6);
        
        // Claim both requests with bytes requestIds
        vm.startPrank(USER);
        uint256 claimed1 = manager.claimUnstakeAPR(requestId1);
        uint256 claimed2 = manager.claimUnstakeAPR(requestId2);
        vm.stopPrank();
        
        assertEq(claimed1, 20 ether, "First claim should be 20 ether");
        assertEq(claimed2, 20 ether, "Second claim should be 20 ether");
    }
    
    /**
     * @dev Test the structure of the bytes requestId
     * Verifies the expected format of the bytes requestId
     */
    function testBytesRequestIdStructure() public {
        // Request to unstake to get a real bytes requestId
        vm.startPrank(USER);
        bytes memory bytesRequestId = manager.unstakeAPR(unstakeAmount, VALIDATOR_ID);
        vm.stopPrank();
        
        // Expected format is now an ABI-encoded uint256 with the structured format internally
        // Check the length is correct (should be 32 bytes for abi.encode)
        assertEq(bytesRequestId.length, 32, "Bytes requestId should be 32 bytes long");
        
        // For debugging
        console.log("Bytes RequestId length:", bytesRequestId.length);
        console.logBytes(bytesRequestId);
        
        // Extract the numeric value for verification
        uint256 numericId = abi.decode(bytesRequestId, (uint256));
        console.log("Decoded numeric ID:", numericId);
        
        // Verify the ID is in the structured format (above 2^32)
        assertTrue(numericId >= 4294967296, "Numeric ID should be in structured format");
        
        // Advance time and claim to verify functionality
        advanceTime(6);
        vm.startPrank(USER);
        uint256 claimed = manager.claimUnstakeAPR(bytesRequestId);
        vm.stopPrank();
        
        assertEq(claimed, unstakeAmount, "Should claim the correct amount");
    }
    
    /**
     * @dev Test backward compatibility with legacy uint256 requestIds
     */
    function testLegacyRequestIdCompatibility() public {
        // Create a simple legacy requestId (just a number)
        uint256 legacyId = 42;
        bytes memory encodedLegacyId = abi.encode(legacyId);
        
        // We would need to set up a manual test case since we can't generate
        // legacy requestIds with the updated contracts
        
        // Log the encoded legacy ID
        console.log("Encoded legacy ID length:", encodedLegacyId.length);
        console.logBytes(encodedLegacyId);
        
        // NOTE: This test is mostly for illustration since we can't directly test
        // legacy compatibility without modifying the contracts or mock data
    }
} 