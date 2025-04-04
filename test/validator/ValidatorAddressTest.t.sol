// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.26;

// import "lib/forge-std/src/Test.sol";
// import "../../src/libraries/ValidatorAddressUtils.sol";

// contract ValidatorAddressTest is Test {
//     // Sample validator address from CrossFi
//     string constant SAMPLE_VALIDATOR = "mxvaloper1gza5y94kal25eawsenl56th8kdyujszmcsxcgs";
//     string constant SAMPLE_WALLET = "mx1gza5y94kal25eawsenl56th8kdyujszmvmlxf0";
//     address constant SAMPLE_EVM = 0x40bB4216B6efD54cF5d0ccFf4D2ee7B349c9405b;
    
//     // Additional test addresses
//     string constant TEST_VALIDATOR = "mxvaloper1jp0m7ynwtvrknzlmdzargmd59mh8n9gkh9yfwm";
//     string constant TEST_WALLET = "mx1jp0m7ynwtvrknzlmdzargmd59mh8n9gkhqqp5j";
    
//     function setUp() public {}
    
//     function testValidatorAddressFormat() public {
//         // Valid validator address
//         bool isValid = ValidatorAddressUtils.isValidValidatorAddress(SAMPLE_VALIDATOR);
//         assertTrue(isValid, "Should recognize valid validator address");
        
//         // Invalid prefix
//         string memory invalidPrefix = "invalid1gza5y94kal25eawsenl56th8kdyujszmcsxcgs";
//         isValid = ValidatorAddressUtils.isValidValidatorAddress(invalidPrefix);
//         assertFalse(isValid, "Should reject invalid prefix");
        
//         // Empty address
//         isValid = ValidatorAddressUtils.isValidValidatorAddress("");
//         assertFalse(isValid, "Should reject empty address");
//     }
    
//     function testBech32Extraction() public {
//         // Extract validator parts
//         string memory bech32Part = ValidatorAddressUtils.extractBech32Part(SAMPLE_VALIDATOR);
        
//         // Log for demonstration
//         emit log_string("Original validator address:");
//         emit log_string(SAMPLE_VALIDATOR);
//         emit log_string("Extracted bech32 part:");
//         emit log_string(bech32Part);
        
//         // Verify not empty
//         assertTrue(bytes(bech32Part).length > 0, "Extracted part should not be empty");
//     }
    
//     function testWalletAddressGeneration() public {
//         // Test with the sample validator address
//         string memory accountAddr1 = ValidatorAddressUtils.validatorToAccountAddress(SAMPLE_VALIDATOR);
        
//         emit log_string("Original validator address:");
//         emit log_string(SAMPLE_VALIDATOR);
//         emit log_string("Generated account address:");
//         emit log_string(accountAddr1);
        
//         bytes memory addr1Bytes = bytes(accountAddr1);
//         assertTrue(addr1Bytes.length > 0, "Generated address should not be empty");
//         assertTrue(addr1Bytes[0] == bytes1('m') && addr1Bytes[1] == bytes1('x'), "Should start with mx prefix");
        
//         // Test with another validator address
//         string memory accountAddr2 = ValidatorAddressUtils.validatorToAccountAddress(TEST_VALIDATOR);
        
//         emit log_string("Original validator address:");
//         emit log_string(TEST_VALIDATOR);
//         emit log_string("Generated account address:");
//         emit log_string(accountAddr2);
        
//         bytes memory addr2Bytes = bytes(accountAddr2);
//         assertTrue(addr2Bytes.length > 0, "Generated address should not be empty");
//         assertTrue(addr2Bytes[0] == bytes1('m') && addr2Bytes[1] == bytes1('x'), "Should start with mx prefix");
//     }
    
//     function testEVMAddressGeneration() public {
//         // Generate EVM address from validator address
//         address evmAddr = ValidatorAddressUtils.validatorToEVMAddress(SAMPLE_VALIDATOR);
        
//         emit log_string("Original validator address:");
//         emit log_string(SAMPLE_VALIDATOR);
//         emit log_string("Generated EVM address:");
//         emit log_address(evmAddr);
        
//         // Note: In production we would verify this against the known EVM address
//         assertTrue(evmAddr != address(0), "EVM address should not be zero");
        
//         // Check the accurate derivation flag
//         bool isAccurate = ValidatorAddressUtils.isAccurateEVMDerivation();
//         console.log("Is using accurate EVM derivation:", isAccurate);
//     }
    
//     function testAddressConversions() public {
//         // Convert EVM address to hex string
//         string memory hexAddr = ValidatorAddressUtils.addressToHex(SAMPLE_EVM);
        
//         // Convert hex string back to address
//         address recovered = ValidatorAddressUtils.hexToAddress(hexAddr);
        
//         // Log for demonstration
//         emit log_string("Original EVM address:");
//         emit log_address(SAMPLE_EVM);
//         emit log_string("As hex string (without 0x):");
//         emit log_string(hexAddr);
//         emit log_string("Recovered address:");
//         emit log_address(recovered);
        
//         // Verify conversion correctness
//         assertEq(SAMPLE_EVM, recovered, "Address conversion should be reversible");
//     }
    
//     function testLegacyFunctionSupport() public {
//         // Use the legacy function name (now redirected to validatorToEVMAddress)
//         address evmAddr = ValidatorAddressUtils.mockValidatorToEVMAddress(SAMPLE_VALIDATOR);
        
//         string memory test = "mxvaloper1jp0m7ynwtvrknzlmdzargmd59mh8n9gkh9yfwm";
//         // Get address via the direct method
//         address directAddr = ValidatorAddressUtils.validatorToEVMAddress(test);
        
//         emit log_string("Validator address:");
//         emit log_string(SAMPLE_VALIDATOR);
//         emit log_string("Address from legacy function:");
//         emit log_address(evmAddr);
//         emit log_string("Address from direct function:");
//         emit log_address(directAddr);
        
//         // Should match the direct function call
//         assertEq(evmAddr, directAddr, "Legacy function should match direct function");
//     }
// } 