// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./StakingUtils.sol";

/**
 * @title ValidatorAddressUtils
 * @dev Utilities for validating and working with Cosmos validator addresses in Solidity
 * @notice This library is streamlined to focus on validator address validation
 */
library ValidatorAddressUtils {
    // Address prefixes
    string constant VALIDATOR_PREFIX = "mxvaloper";
    
    /**
     * @dev Checks if a validator address is valid
     * @param validatorAddr The validator address to check
     * @return isValid Whether the address is valid
     */
    function isValidValidatorAddress(string memory validatorAddr) internal pure returns (bool isValid) {
        // Delegate to StakingUtils for consistent validation
        return StakingUtils.validateValidatorId(validatorAddr);
    }
    
    /**
     * @dev Extracts the Bech32 part of a validator address (after the prefix)
     * @param validatorAddr The validator address
     * @return bech32Part The Bech32 part of the address
     */
    function extractBech32Part(string memory validatorAddr) internal pure returns (string memory bech32Part) {
        if (!isValidValidatorAddress(validatorAddr)) {
            return "";
        }
        
        // Delegate to StakingUtils for consistent extraction
        return StakingUtils.extractOperatorPart(validatorAddr);
    }
    
    /**
     * @dev Normalizes a validator address to lowercase
     * @param validatorAddr The validator address to normalize
     * @return normalized The normalized validator address
     */
    function normalizeValidatorAddress(string memory validatorAddr) internal pure returns (string memory normalized) {
        // Delegate to StakingUtils for consistent normalization
        return StakingUtils.normalizeValidatorId(validatorAddr);
    }
    
    /**
     * @dev Compares two validator addresses for equality (case insensitive)
     * @param validator1 The first validator address
     * @param validator2 The second validator address
     * @return areEqual Whether the addresses are equal
     */
    function compareValidatorAddresses(string memory validator1, string memory validator2) internal pure returns (bool areEqual) {
        // Normalize both addresses to lowercase for case-insensitive comparison
        string memory normalized1 = normalizeValidatorAddress(validator1);
        string memory normalized2 = normalizeValidatorAddress(validator2);
        
        // Compare normalized addresses
        return keccak256(bytes(normalized1)) == keccak256(bytes(normalized2));
    }
} 