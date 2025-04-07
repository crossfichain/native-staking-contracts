// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title StakingUtils
 * @dev Library with utility functions for the NativeStaking contract
 */
library StakingUtils {
    // Constants
    string private constant VALIDATOR_PREFIX = "mxvaloper";
    string private constant WALLET_PREFIX = "mx";
    
    // Staking settings
    uint256 private constant MIN_STAKE_COOLDOWN = 1 hours;
    uint256 private constant MIN_VALIDATOR_ID_LENGTH = 45;
    uint256 private constant MAX_VALIDATOR_ID_LENGTH = 60;
    
    /**
     * @dev Validates if a validator ID has the correct format
     * @param validatorId The validator ID to validate
     * @return isValid Whether the validator ID is valid
     */
    function validateValidatorId(string memory validatorId) internal pure returns (bool isValid) {
        // Check that the validator ID is not empty
        if (bytes(validatorId).length == 0) return false;
        
        // Check length constraints
        bytes memory validatorBytes = bytes(validatorId);
        if (validatorBytes.length < MIN_VALIDATOR_ID_LENGTH || validatorBytes.length > MAX_VALIDATOR_ID_LENGTH) {
            return false;
        }
        
        // Check that the validator ID starts with the required prefix (case insensitive)
        bytes memory prefixBytes = bytes(VALIDATOR_PREFIX);
        
        // Must be at least as long as the prefix
        if (validatorBytes.length < prefixBytes.length) return false;
        
        // Check prefix match (case insensitive)
        for (uint i = 0; i < prefixBytes.length; i++) {
            // Convert both to lowercase for comparison
            bytes1 validatorChar = validatorBytes[i];
            bytes1 prefixChar = prefixBytes[i];
            
            // Convert uppercase to lowercase if needed
            if (validatorChar >= 0x41 && validatorChar <= 0x5A) {
                validatorChar = bytes1(uint8(validatorChar) + 32);
            }
            if (prefixChar >= 0x41 && prefixChar <= 0x5A) {
                prefixChar = bytes1(uint8(prefixChar) + 32);
            }
            
            if (validatorChar != prefixChar) return false;
        }
        
        // Additional validation for validator address format
        return validateBech32Format(validatorBytes, prefixBytes.length);
    }
    
    /**
     * @dev Validates if a wallet address has the correct format
     * @param walletAddress The wallet address to validate
     * @return isValid Whether the wallet address is valid
     */
    function validateWalletAddress(string memory walletAddress) internal pure returns (bool isValid) {
        // Check that the wallet address is not empty
        if (bytes(walletAddress).length == 0) return false;
        
        // Check maximum length
        if (bytes(walletAddress).length > 100) return false;
        
        // Check that the wallet address starts with the required prefix
        bytes memory walletBytes = bytes(walletAddress);
        bytes memory prefixBytes = bytes(WALLET_PREFIX);
        
        // Must be at least as long as the prefix
        if (walletBytes.length < prefixBytes.length) return false;
        
        // Check prefix match (case insensitive)
        for (uint i = 0; i < prefixBytes.length; i++) {
            // Convert both to lowercase for comparison
            bytes1 walletChar = walletBytes[i];
            bytes1 prefixChar = prefixBytes[i];
            
            // Convert uppercase to lowercase if needed
            if (walletChar >= 0x41 && walletChar <= 0x5A) {
                walletChar = bytes1(uint8(walletChar) + 32);
            }
            if (prefixChar >= 0x41 && prefixChar <= 0x5A) {
                prefixChar = bytes1(uint8(prefixChar) + 32);
            }
            
            if (walletChar != prefixChar) return false;
        }
        
        // Additional validation for wallet address format
        return validateBech32Format(walletBytes, prefixBytes.length);
    }
    
    /**
     * @dev Basic validation for Bech32 format
     * @param addressBytes The address bytes to validate
     * @param prefixLength The length of the prefix to skip
     * @return isValid Whether the format appears valid
     * Note: This is a simplified check; full Bech32 validation would require more complex code
     */
    function validateBech32Format(bytes memory addressBytes, uint256 prefixLength) private pure returns (bool isValid) {
        // Skip prefix
        uint256 startIndex = prefixLength;
        
        // The address part should have a reasonable length
        if (addressBytes.length - startIndex < 38 || addressBytes.length - startIndex > 59) return false;
        
        // Check that remaining characters are valid Bech32 characters
        for (uint i = startIndex; i < addressBytes.length; i++) {
            bytes1 character = addressBytes[i];
            
            // Valid characters in Bech32: a-z, 0-9
            bool isLowerAlpha = (character >= 0x61 && character <= 0x7A); // a-z
            bool isDigit = (character >= 0x30 && character <= 0x39); // 0-9
            
            if (!isLowerAlpha && !isDigit) return false;
        }
        
        return true;
    }
    
    /**
     * @dev Attempts to extract the operator part from a validator address
     * @param validatorId The validator ID (Bech32 format)
     * @return operatorPart The operator part of the address (after the prefix)
     */
    function extractOperatorPart(string memory validatorId) internal pure returns (string memory operatorPart) {
        bytes memory validatorBytes = bytes(validatorId);
        bytes memory prefixBytes = bytes(VALIDATOR_PREFIX);
        
        // If not valid or too short, return empty
        if (!validateValidatorId(validatorId)) return "";
        
        // Extract the part after the prefix
        bytes memory result = new bytes(validatorBytes.length - prefixBytes.length);
        for (uint i = 0; i < result.length; i++) {
            result[i] = validatorBytes[i + prefixBytes.length];
        }
        
        return string(result);
    }
    
    /**
     * @dev Normalizes a validator ID to lowercase
     * @param validatorId The validator ID to normalize
     * @return normalized The normalized validator ID
     */
    function normalizeValidatorId(string memory validatorId) internal pure returns (string memory normalized) {
        bytes memory validatorBytes = bytes(validatorId);
        bytes memory result = new bytes(validatorBytes.length);
        
        for (uint i = 0; i < validatorBytes.length; i++) {
            bytes1 char = validatorBytes[i];
            
            // Convert uppercase to lowercase
            if (char >= 0x41 && char <= 0x5A) {
                result[i] = bytes1(uint8(char) + 32);
            } else {
                result[i] = char;
            }
        }
        
        return string(result);
    }
    
    /**
     * @dev Checks if enough time has passed since the last stake
     * @param lastStakeTime The timestamp of the last stake
     * @return canStake Whether enough time has passed for a new stake
     */
    function canStakeAgain(uint256 lastStakeTime) internal view returns (bool) {
        // If there's no previous stake, always allow
        if (lastStakeTime == 0) {
            return true;
        }
        
        // If last stake is in the future (should never happen, but just in case)
        if (lastStakeTime > block.timestamp) {
            return false;
        }
        
        // Calculate cooldown end time
        uint256 cooldownEndTime = lastStakeTime + MIN_STAKE_COOLDOWN;
        
        // Check if current time has passed the cooldown period
        return block.timestamp >= cooldownEndTime;
    }
    
    /**
     * @dev Validates the staking parameters
     * @param amount The amount to stake
     * @param minAmount The minimum staking amount
     * @return isValid Whether the parameters are valid
     * @return errorMessage The error message if not valid
     */
    function validateStakingParams(
        uint256 amount,
        uint256 minAmount
    ) internal pure returns (bool isValid, string memory errorMessage) {
        // Check for zero amount
        if (amount == 0) {
            return (false, "Amount must be greater than 0");
        }
        
        // Check for minimum amount
        if (amount < minAmount) {
            return (false, "Amount below minimum");
        }
        
        return (true, "");
    }
} 