// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/APRStaking.sol";
import "../../src/interfaces/INativeStaking.sol";
import "../utils/MockDIAOracle.sol";
import "../../src/periphery/UnifiedOracle.sol";
import "../../src/periphery/WXFI.sol";

/**
 * @title MockAPRStaking
 * @dev Minimal mock of APRStaking for testing the structured requestId fix
 */
contract MockAPRStaking is Test {
    struct UnstakeRequest {
        address user;
        uint256 amount;
        string validator;
        uint256 timestamp;
        bool claimed;
    }
    
    mapping(uint256 => UnstakeRequest) public _unstakeRequests;
    address public stakingToken;

    function initialize(address tokenAddress) external {
        stakingToken = tokenAddress;
    }
    
    /**
     * @dev Setup a test unstake request
     */
    function setupUnstakeRequest(
        uint256 requestId, 
        address user, 
        uint256 amount,
        string memory validator,
        uint256 timestamp,
        bool claimed
    ) external {
        _unstakeRequests[requestId] = UnstakeRequest({
            user: user,
            amount: amount,
            validator: validator,
            timestamp: timestamp,
            claimed: claimed
        });
    }
    
    /**
     * @dev Claims unstaked XFI tokens - the function we're testing for structured ID handling
     */
    function claimUnstake(
        address user,
        uint256 requestId
    ) 
        external
        returns (uint256 amount) 
    {
        // Extract the actual request ID when it's a structured ID
        uint256 actualRequestId = requestId;
        
        // Check if this is a structured requestId (using same threshold as NativeStaking)
        if (requestId >= 4294967296) { // 2^32
            // Extract the sequence number from the last 4 bytes (same as in NativeStaking)
            actualRequestId = uint256(uint32(requestId));
            console.log("Structured ID detected. Using actualRequestId:", actualRequestId);
        } else {
            console.log("Regular ID, using as-is:", actualRequestId);
        }
        
        UnstakeRequest storage request = _unstakeRequests[actualRequestId];
        
        // Verify the request
        require(request.user == user, "Not request owner");
        require(!request.claimed, "Already claimed");
        
        amount = request.amount;
        request.claimed = true;
        
        return amount;
    }
}

/**
 * @title APRStakingFixTest
 * @dev Tests specifically for the APRStaking structured requestId fix
 */
contract APRStakingFixTest is Test {
    // Test contracts
    MockAPRStaking public mockStaking;
    WXFI public wxfi;
    
    // Test constants
    address public constant USER = address(0x1);
    string public constant VALIDATOR_ID = "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    
    // Request data
    uint256 public normalRequestId = 42;
    uint256 public structuredRequestId = 0x0100000000AABBCCDD0000002A; // Contains 42 (0x2A) in last 4 bytes
    uint256 public amount = 100 ether;
    
    function setUp() public {
        // Deploy tokens
        wxfi = new WXFI();
        
        // Deploy mock APRStaking
        mockStaking = new MockAPRStaking();
        mockStaking.initialize(address(wxfi));
        
        // Set up test data - create unstake request with ID 42
        mockStaking.setupUnstakeRequest(
            normalRequestId, // Raw requestId 42
            USER,
            amount,
            VALIDATOR_ID,
            block.timestamp - 1 days,
            false
        );
        
        // Mint WXFI to the mock contract for claim testing
        deal(address(wxfi), address(mockStaking), amount);
    }
    
    /**
     * @dev Test regular non-structured requestId claim
     */
    function testRegularRequestId() public {
        // Direct claim with normal request ID
        uint256 claimed = mockStaking.claimUnstake(USER, normalRequestId);
        
        // Verify correct amount claimed
        assertEq(claimed, amount, "Should claim correct amount with regular ID");
    }
    
    /**
     * @dev Test structured requestId claim with the fix
     * This tests the core fix for the "Invalid requestId" issue
     */
    function testStructuredRequestId() public {
        // Attempt to claim with structured ID that contains the same sequence (42)
        uint256 claimed = mockStaking.claimUnstake(USER, structuredRequestId);
        
        // This should now work due to the fix - it extracts 42 from the structured ID
        assertEq(claimed, amount, "Should claim correct amount with structured ID");
    }
} 