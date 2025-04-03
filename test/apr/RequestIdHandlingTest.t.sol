// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

/**
 * @title RequestIdHandlingTest
 * @dev Tests for structured requestId handling with bytes type
 */
contract RequestIdHandlingTest is Test {
    // Legacy functions for backward compatibility
    function isStructuredRequestId(uint256 requestId) public pure returns (bool) {
        return requestId >= 4294967296; // 2^32
    }
    
    function getSequenceFromId(uint256 requestId) public pure returns (uint256) {
        return uint256(uint32(requestId));
    }
    
    // New functions for bytes requestId
    function extractSequenceFromBytesId(bytes memory requestId) public pure returns (uint256) {
        require(requestId.length >= 4, "Invalid requestId format");
        
        // Extract the last 4 bytes and convert to uint32
        uint32 sequence = 0;
        for (uint i = 0; i < 4; i++) {
            sequence = (sequence << 8) | uint8(requestId[requestId.length - 4 + i]);
        }
        
        return uint256(sequence);
    }
    
    /**
     * @dev Extract the request ID index from a requestId (either bytes or uint256 encoded as bytes)
     * @param requestId The requestId in bytes format
     * @return the index to use for lookup
     */
    function extractRequestIndex(bytes memory requestId) public pure returns (uint256) {
        if (requestId.length > 32) {
            // New format - extract sequence from the last 4 bytes
            return extractSequenceFromBytesId(requestId);
        } else {
            // Legacy format - decode as uint256 and check if structured
            uint256 legacyId = abi.decode(requestId, (uint256));
            if (isStructuredRequestId(legacyId)) {
                return getSequenceFromId(legacyId);
            }
            return legacyId;
        }
    }
    
    /**
     * @dev Test identification of structured legacy request IDs
     */
    function testIsStructuredLegacyRequestId() public {
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
     * @dev Test sequence extraction from legacy structured IDs
     */
    function testLegacySequenceExtraction() public {
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
     * @dev Test the extraction of sequence from bytes requestId
     */
    function testBytesSequenceExtraction() public {
        // Create a test bytes requestId with a specific sequence in the last 4 bytes
        // Format: [2 bytes type][4 bytes timestamp][20 bytes user][32 bytes hash][4 bytes sequence]
        bytes memory testId = new bytes(62);
        
        // Set the last 4 bytes to represent sequence 42
        testId[58] = 0x00;
        testId[59] = 0x00;
        testId[60] = 0x00;
        testId[61] = 0x2A; // 42 in hex
        
        uint256 sequence = extractSequenceFromBytesId(testId);
        assertEq(sequence, 42, "Should extract 42 from bytes requestId");
        
        // Test with a different sequence value
        bytes memory testId2 = new bytes(62);
        testId2[58] = 0x00;
        testId2[59] = 0x00;
        testId2[60] = 0x00;
        testId2[61] = 0xFF; // 255 in hex
        
        uint256 sequence2 = extractSequenceFromBytesId(testId2);
        assertEq(sequence2, 255, "Should extract 255 from bytes requestId");
    }
    
    /**
     * @dev Test extraction from both bytes and legacy formats
     */
    function testRequestIndexExtraction() public {
        // Test with bytes format (new)
        bytes memory newFormatId = new bytes(62);
        newFormatId[61] = 0x2A; // Sequence 42
        
        uint256 extracted1 = extractRequestIndex(newFormatId);
        assertEq(extracted1, 42, "Should extract 42 from new format");
        
        // Test with legacy uint256 encoded as bytes
        uint256 legacyStructuredId = 0x0100000000AABBCCDD0000002A;
        bytes memory encodedLegacyId = abi.encode(legacyStructuredId);
        
        uint256 extracted2 = extractRequestIndex(encodedLegacyId);
        assertEq(extracted2, 42, "Should extract 42 from legacy structured format");
        
        // Test with old simple ID encoded as bytes
        uint256 oldId = 42;
        bytes memory encodedOldId = abi.encode(oldId);
        
        uint256 extracted3 = extractRequestIndex(encodedOldId);
        assertEq(extracted3, 42, "Should return old ID as-is");
    }
} 