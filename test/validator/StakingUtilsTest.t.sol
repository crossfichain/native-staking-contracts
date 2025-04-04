// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "lib/forge-std/src/Test.sol";
import "../../src/libraries/StakingUtils.sol";

contract StakingUtilsTest is Test {
    // Sample validator and wallet addresses
    string constant SAMPLE_VALIDATOR = "mxvaloper1gza5y94kal25eawsenl56th8kdyujszmcsxcgs";
    string constant SAMPLE_WALLET = "mx1gza5y94kal25eawsenl56th8kdyujszmvmlxf0";
    
    function setUp() public {}
    
    function testValidatorIdValidation() public {
        // Valid validator ID
        bool isValid = StakingUtils.validateValidatorId(SAMPLE_VALIDATOR);
        assertTrue(isValid, "Should validate correct validator ID");
        
        // Invalid prefix
        string memory invalidPrefix = "invalid1gza5y94kal25eawsenl56th8kdyujszmcsxcgs";
        isValid = StakingUtils.validateValidatorId(invalidPrefix);
        assertFalse(isValid, "Should reject ID with invalid prefix");
        
        // Empty ID
        isValid = StakingUtils.validateValidatorId("");
        assertFalse(isValid, "Should reject empty validator ID");
    }
    
    function testWalletAddressValidation() public {
        // Valid wallet address
        bool isValid = StakingUtils.validateWalletAddress(SAMPLE_WALLET);
        assertTrue(isValid, "Should validate correct wallet address");
        
        // Invalid prefix
        string memory invalidPrefix = "invalid1gza5y94kal25eawsenl56th8kdyujszmvmlxf0";
        isValid = StakingUtils.validateWalletAddress(invalidPrefix);
        assertFalse(isValid, "Should reject address with invalid prefix");
        
        // Empty address
        isValid = StakingUtils.validateWalletAddress("");
        assertFalse(isValid, "Should reject empty wallet address");
    }
    
    function testOperatorPartExtraction() public {
        // Extract operator part
        string memory operatorPart = StakingUtils.extractOperatorPart(SAMPLE_VALIDATOR);
        
        emit log_string("Original validator address:");
        emit log_string(SAMPLE_VALIDATOR);
        emit log_string("Extracted operator part:");
        emit log_string(operatorPart);
        
        // Verify not empty
        assertTrue(bytes(operatorPart).length > 0, "Extracted part should not be empty");
    }
    
    // Function referencing checkOperatorMatch, which doesn't exist in the original StakingUtils
    // Commenting this out until we update the StakingUtils library
    /*
    function testOperatorMatching() public {
        // Check if the operator parts match
        bool matches = StakingUtils.checkOperatorMatch(SAMPLE_VALIDATOR, SAMPLE_WALLET);
        
        emit log_string("Validator address:");
        emit log_string(SAMPLE_VALIDATOR);
        emit log_string("Wallet address:");
        emit log_string(SAMPLE_WALLET);
        emit log_named_bool("Operator parts match", matches);
        
        // In a real implementation with actual addresses, this would need to be verified
        // For this test, we're just checking the function structure works
    }
    */
    
    function testRequestIdGeneration() public {
        address staker = address(0x1234567890123456789012345678901234567890);
        string memory validatorId = SAMPLE_VALIDATOR;
        uint256 amount = 100 ether;
        uint256 timestamp = 1678912345;
        
        bytes memory requestId = StakingUtils.generateRequestId(
            staker,
            validatorId,
            amount,
            timestamp
        );
        
        // Verify request ID is not empty
        assertTrue(requestId.length > 0, "Request ID should not be empty");
        
        // Log for demonstration
        emit log_string("Generated request ID length:");
        emit log_uint(requestId.length);
    }
    
    function testStakingParamsValidation() public {
        // Valid parameters
        uint256 amount = 10 ether;
        uint256 minAmount = 1 ether;
        bool enforceMinimums = true;
        
        (bool isValid, string memory errorMessage) = StakingUtils.validateStakingParams(
            amount,
            minAmount,
            enforceMinimums
        );
        
        assertTrue(isValid, "Should validate parameters above minimum");
        
        // Amount below minimum
        amount = 0.5 ether;
        
        (isValid, errorMessage) = StakingUtils.validateStakingParams(
            amount,
            minAmount,
            enforceMinimums
        );
        
        assertFalse(isValid, "Should reject amount below minimum");
        assertEq(errorMessage, "Amount below minimum", "Error message mismatch");
        
        // Zero amount
        amount = 0;
        
        (isValid, errorMessage) = StakingUtils.validateStakingParams(
            amount,
            minAmount,
            enforceMinimums
        );
        
        assertFalse(isValid, "Should reject zero amount");
        assertEq(errorMessage, "Amount must be greater than 0", "Error message mismatch");
    }
    
    function testAPRRewardCalculation() public {
        uint256 amount = 100 ether;
        uint256 apr = 0.1 ether; // 10% annual rate (0.1 ether = 10^17)
        uint256 timeInSeconds = 30 days; // 30 days
        
        uint256 reward = StakingUtils.calculateAPRReward(
            amount,
            apr,
            timeInSeconds
        );
        
        // Expected reward: 100 * 0.1 * (30 days / 365 days) = ~0.822 ETH
        // with slight precision loss due to integer division
        
        emit log_string("Staking amount:");
        emit log_named_uint("Amount (wei)", amount);
        emit log_string("APR (10% with 18 decimals):");
        emit log_named_uint("APR", apr);
        emit log_string("Time period:");
        emit log_named_uint("Days", timeInSeconds / 1 days);
        emit log_string("Calculated reward:");
        emit log_named_uint("Reward (wei)", reward);
        
        // Basic verification
        assertTrue(reward > 0, "Reward should be greater than 0");
        assertTrue(reward < amount, "Reward should be less than principal for short time periods");
    }
} 