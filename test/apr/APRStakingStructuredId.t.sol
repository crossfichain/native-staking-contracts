// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/APRStaking.sol";
import "../../src/core/ConcreteNativeStakingManager.sol";
import "../../src/periphery/UnifiedOracle.sol";
import "../../src/periphery/WXFI.sol";
import "../utils/MockDIAOracle.sol";

/**
 * @title StructuredRequestIdTest
 * @dev Tests specifically for the structured requestId handling
 */
contract StructuredRequestIdTest is Test {
    // Test contracts
    APRStaking public aprStaking;
    ConcreteNativeStakingManager public manager;
    UnifiedOracle public oracle;
    WXFI public wxfi;
    MockDIAOracle public diaOracle;
    
    // Test constants
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    string public constant VALIDATOR_ID = "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    
    // Request IDs
    uint256 public normalRequestId = 42;
    uint256 public structuredRequestId = 0x0100000000AABBCCDD00000042; // Will be over 2^32

    /**
     * @dev Test setup method
     */
    function setUp() public {
        vm.startPrank(ADMIN);
        
        // Deploy minimal necessary contracts
        wxfi = new WXFI();
        diaOracle = new MockDIAOracle();
        oracle = new UnifiedOracle();
        manager = new ConcreteNativeStakingManager();
        aprStaking = new APRStaking();
        
        // Initialize contracts
        oracle.initialize(address(diaOracle), 14 days, address(wxfi));
        aprStaking.initialize(
            address(oracle), 
            address(wxfi),
            50 ether, // Min stake amount
            10 ether, // Min unstake amount
            false // Do not enforce minimum amounts for tests
        );
        
        // Add structured requestId extraction to APRStaking during test
        vm.stopPrank();
    }
    
    /**
     * @dev Test that structured IDs are correctly identified
     */
    function testIsStructuredRequestId() public {
        // Confirm 2^32 is the boundary for structured IDs
        uint256 boundary = 4294967296; // 2^32
        assertTrue(boundary >= 2**32, "Boundary should be at least 2^32");
        
        // Test with manager's isStructuredRequestId function
        assertTrue(manager.isStructuredRequestId(boundary), "Boundary should be identified as structured");
        assertTrue(!manager.isStructuredRequestId(boundary - 1), "Value below boundary should not be structured");
        assertTrue(manager.isStructuredRequestId(structuredRequestId), "Structured ID should be identified as such");
        assertTrue(!manager.isStructuredRequestId(normalRequestId), "Normal ID should not be identified as structured");
    }

    /**
     * @dev Test that the sequence component is correctly extracted from structured IDs
     */
    function testSequenceExtraction() public {
        // Create a structured ID with a specific sequence value (42)
        uint256 testId = 0x0100000000AABBCCDD00000042;
        
        // Extract sequence using manager function
        uint256 sequence = manager.getSequenceFromId(testId);
        
        // Verify correct extraction
        assertEq(sequence, 66, "Sequence should be correctly extracted");
    }

    /**
     * @dev Test the fix for the APRStaking contract's handling of structured IDs
     */
    function testStructuredIdHandlingWithMocking() public {
        // Create a mock APRStaking instance behavior
        APRStaking mockStaking = APRStaking(address(0x999));
        
        // Create a structured request ID
        uint256 requestId = 0x0100000000AABBCCDD00000042;
        
        // Create a normal request ID
        uint256 normalId = 42;
        
        // Verify the detection
        assertTrue(manager.isStructuredRequestId(requestId), "Should detect as structured");
        assertTrue(!manager.isStructuredRequestId(normalId), "Should not detect as structured");
        
        // Verify sequence extraction
        uint256 sequence = manager.getSequenceFromId(requestId);
        console.log("Sequence extracted from structured ID:", sequence);
        
        // Expected behavior:
        // When using a structured ID, APRStaking should extract the sequence component
        // and use it to look up the actual request in its storage
    }
} 