// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "lib/forge-std/src/Test.sol";
import "../../src/libraries/ValidatorAddressUtils.sol";
import "../../src/libraries/StakingUtils.sol";

contract ValidatorAddressTest is Test {
    string constant VALIDATOR_ADDR = "mxvaloper1gza5y94kal25eawsenl56th8kdyujszmcsxcgs";
    
    function testValidatorAddressFormat() public {
        // Validate format
        bool isValid = ValidatorAddressUtils.isValidValidatorAddress(VALIDATOR_ADDR);
        assertTrue(isValid, "Should validate validator address format");
        
        // Invalid format
        isValid = ValidatorAddressUtils.isValidValidatorAddress("invalid");
        assertFalse(isValid, "Should reject invalid format");
        
        // Empty string
        isValid = ValidatorAddressUtils.isValidValidatorAddress("");
        assertFalse(isValid, "Should reject empty string");
    }
    
    function testBech32Extraction() public {
        // Extract Bech32 part
        string memory bech32Part = ValidatorAddressUtils.extractBech32Part(VALIDATOR_ADDR);
        
        console.log("Original validator address:");
        console.log(VALIDATOR_ADDR);
        console.log("Extracted bech32 part:");
        console.log(bech32Part);
        
        // Validate not empty
        assertTrue(bytes(bech32Part).length > 0, "Extracted part should not be empty");
        
        // Invalid address should return empty string
        string memory invalidPart = ValidatorAddressUtils.extractBech32Part("invalid");
        assertEq(invalidPart, "", "Invalid address should return empty string");
    }
    
    function testAddressConversions() public {
        // Test validators from the examples
        string[5] memory validators = [
            "mxvaloper1gza5y94kal25eawsenl56th8kdyujszmcsxcgs",
            "mxvaloper15vaxer4jfr2mhg6qaqspr0z44aj3jvfepw9kf4",
            "mxvaloper1pfyz7tyk297p3cfl78fgt9esud4eclceu0smj7",
            "mxvaloper1jp0m7ynwtvrknzlmdzargmd59mh8n9gkh9yfwm",
            "mxvaloper1qr26qzu8qxcksk452ymr0720ntd7lwlzh7n4m5"
        ];
        
        for (uint i = 0; i < validators.length; i++) {
            // Validate format
            bool isValid = ValidatorAddressUtils.isValidValidatorAddress(validators[i]);
            assertTrue(isValid, "Should validate validator address format");
            
            // Extract Bech32 part
            string memory bech32Part = ValidatorAddressUtils.extractBech32Part(validators[i]);
            assertTrue(bytes(bech32Part).length > 0, "Extracted part should not be empty");
            
            // Test normalization
            string memory normalized = ValidatorAddressUtils.normalizeValidatorAddress(validators[i]);
            assertTrue(
                ValidatorAddressUtils.compareValidatorAddresses(normalized, validators[i]), 
                "Normalized address should be equal"
            );
            
            // Test case-insensitive comparison
            string memory upperCase = string(abi.encodePacked("MXVALOPER", bech32Part));
            assertTrue(
                ValidatorAddressUtils.compareValidatorAddresses(upperCase, validators[i]), 
                "Case-insensitive comparison should match"
            );
        }
    }
} 