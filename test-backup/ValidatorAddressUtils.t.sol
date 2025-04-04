// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "lib/forge-std/src/Test.sol";
import "../src/libraries/ValidatorAddressUtils.sol";

contract ValidatorAddressUtilsTest is Test {
    // Sample validator address from CrossFi
    string constant SAMPLE_VALIDATOR = "mxvaloper1gza5y94kal25eawsenl56th8kdyujszmcsxcgs";
    string constant SAMPLE_WALLET = "mx1gza5y94kal25eawsenl56th8kdyujszmvmlxf0";
    address constant SAMPLE_EVM = 0x40bB4216B6efD54cF5d0ccFf4D2ee7B349c9405b;
    
    function setUp() public {}
    
    function testValidatorAddressValidation() public {
        // Valid validator address
        bool isValid = ValidatorAddressUtils.isValidValidatorAddress(SAMPLE_VALIDATOR);
        assertTrue(isValid, "Should recognize valid validator address");
        
        // Invalid prefix
        string memory invalidPrefix = "invalid1gza5y94kal25eawsenl56th8kdyujszmcsxcgs";
        isValid = ValidatorAddressUtils.isValidValidatorAddress(invalidPrefix);
        assertFalse(isValid, "Should reject invalid prefix");
        
        // Empty address
        isValid = ValidatorAddressUtils.isValidValidatorAddress("");
        assertFalse(isValid, "Should reject empty address");
    }
    
    function testWalletToValidatorCorrespondence() public {
        // Extract validator parts
        string memory bech32Part = ValidatorAddressUtils.extractBech32Part(SAMPLE_VALIDATOR);
        string memory accountAddr = ValidatorAddressUtils.validatorToAccountAddress(SAMPLE_VALIDATOR);
        
        // Log for demonstration
        emit log_string("Original validator address:");
        emit log_string(SAMPLE_VALIDATOR);
        emit log_string("Extracted bech32 part:");
        emit log_string(bech32Part);
        emit log_string("Generated account address:");
        emit log_string(accountAddr);
        
        // In a real test, we'd verify the actual correspondence, but this is a simplified demo
        // Note: This doesn't confirm cryptographic correctness, only demonstrates the utility functions
    }
    
    function testAddressConversions() public {
        // Convert EVM address to hex string
        string memory hexAddr = ValidatorAddressUtils.addressToHex(SAMPLE_EVM);
        
        // Convert hex string back to address
        address recovered = ValidatorAddressUtils.hexToAddress(hexAddr);
        
        // Log for demonstration
        emit log_string("Original EVM address:");
        emit log_address(SAMPLE_EVM);
        emit log_string("As hex string (without 0x):");
        emit log_string(hexAddr);
        emit log_string("Recovered address:");
        emit log_address(recovered);
        
        // Verify conversion correctness
        assertEq(SAMPLE_EVM, recovered, "Address conversion should be reversible");
    }
    
    function testMockValidatorToEVMMapping() public {
        // This is only a demo of the utility function structure
        // In a real system, the actual mapping would use proper cryptographic derivation
        
        address mockEVM = ValidatorAddressUtils.mockValidatorToEVMAddress(SAMPLE_VALIDATOR);
        
        emit log_string("Validator address:");
        emit log_string(SAMPLE_VALIDATOR);
        emit log_string("Actual corresponding EVM address:");
        emit log_address(SAMPLE_EVM);
        emit log_string("Mock derived EVM address (demonstration only):");
        emit log_address(mockEVM);
        
        // Note: We don't expect these to match as our mock implementation is not the actual derivation
    }
} 