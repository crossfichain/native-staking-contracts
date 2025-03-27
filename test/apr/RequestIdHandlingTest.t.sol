// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

/**
 * @title RequestIdHandlingTest
 * @dev Tests for structured requestId handling
 */
contract RequestIdHandlingTest is Test {
    // The mock implementation of the functions we're testing
    function isStructuredRequestId(uint256 requestId) public pure returns (bool) {
        return requestId >= 4294967296; // 2^32
    }
    
    function getSequenceFromId(uint256 requestId) public pure returns (uint256) {
        return uint256(uint32(requestId));
    }
    
    /**
     * @dev Extract the request ID from a structured ID
     * @param requestId The structured ID or normal ID
     * @return the actual request ID to use
     */
    function extractRequestId(uint256 requestId) public pure returns (uint256) {
        if (isStructuredRequestId(requestId)) {
            return getSequenceFromId(requestId);
        }
        return requestId;
    }
    
    /**
     * @dev Test the identification of structured request IDs
     */
    function testIsStructuredRequestId() public {
        // Boundary case
        uint256 boundary = 4294967296; // 2^32
        assertTrue(isStructuredRequestId(boundary), "Boundary should be detected as structured");
        assertTrue(!isStructuredRequestId(boundary - 1), "Value below boundary should not be structured");
        
        // Test with structured ID
        uint256 structuredId = 0x0100000000AABBCCDD0000002A; // Contains 42 (0x2A) in last 4 bytes
        assertTrue(isStructuredRequestId(structuredId), "Structured ID should be detected");
        
        // Test with normal ID
        uint256 normalId = 42;
        assertTrue(!isStructuredRequestId(normalId), "Normal ID should not be detected as structured");
    }
    
    /**
     * @dev Test sequence extraction from structured IDs
     */
    function testSequenceExtraction() public {
        // Extract from ID with value 42 (0x2A) in the lower 4 bytes
        uint256 testId = 0x0100000000AABBCCDD0000002A;
        
        uint256 sequence = getSequenceFromId(testId);
        assertEq(sequence, 42, "Should extract 42 from the ID");
        
        // Test with a different value
        uint256 testId2 = 0x0100000000AABBCCDD000000FF;
        uint256 sequence2 = getSequenceFromId(testId2);
        assertEq(sequence2, 255, "Should extract 255 from the ID");
    }
    
    /**
     * @dev Test the full extraction logic for both types of IDs
     */
    function testRequestIdExtraction() public {
        // When given a structured ID, should extract the sequence
        uint256 structuredId = 0x0100000000AABBCCDD0000002A;
        uint256 extracted1 = extractRequestId(structuredId);
        assertEq(extracted1, 42, "Should extract 42 from the structured ID");
        
        // When given a normal ID, should return it as-is
        uint256 normalId = 42;
        uint256 extracted2 = extractRequestId(normalId);
        assertEq(extracted2, 42, "Should return normal ID as-is");
    }
} 