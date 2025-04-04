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
    
    /**
     * @dev Validates if a validator ID has the correct format
     * @param validatorId The validator ID to validate
     * @return isValid Whether the validator ID is valid
     */
    function validateValidatorId(string memory validatorId) internal pure returns (bool isValid) {
        // Check that the validator ID is not empty
        if (bytes(validatorId).length == 0) return false;
        
        // Check maximum length (should be reasonable for a validator address)
        if (bytes(validatorId).length > 100) return false;
        
        // Check that the validator ID starts with the required prefix
        bytes memory validatorBytes = bytes(validatorId);
        bytes memory prefixBytes = bytes(VALIDATOR_PREFIX);
        
        // Must be at least as long as the prefix
        if (validatorBytes.length < prefixBytes.length) return false;
        
        // Check prefix match
        for (uint i = 0; i < prefixBytes.length; i++) {
            if (validatorBytes[i] != prefixBytes[i]) return false;
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
        
        // Check prefix match
        for (uint i = 0; i < prefixBytes.length; i++) {
            if (walletBytes[i] != prefixBytes[i]) return false;
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
     * @dev Check if a validator address and a wallet address could correspond
     * @param validatorId The validator address
     * @param walletAddress The wallet address
     * @return matches Whether the addresses potentially match
     */
    function checkAddressCorrespondence(string memory validatorId, string memory walletAddress) internal pure returns (bool matches) {
        // Basic validation
        if (!validateValidatorId(validatorId) || !validateWalletAddress(walletAddress)) return false;
        
        // Extract operator parts
        string memory validatorOperator = extractOperatorPart(validatorId);
        
        // For wallet, skip the "mx" prefix
        bytes memory walletBytes = bytes(walletAddress);
        bytes memory walletPrefixBytes = bytes(WALLET_PREFIX);
        
        // Wallet must be at least as long as its prefix
        if (walletBytes.length <= walletPrefixBytes.length) return false;
        
        bytes memory walletOperatorBytes = new bytes(walletBytes.length - walletPrefixBytes.length);
        for (uint i = 0; i < walletOperatorBytes.length; i++) {
            walletOperatorBytes[i] = walletBytes[i + walletPrefixBytes.length];
        }
        
        // In CrossFi, we would need to decode both addresses and check if they share
        // the same underlying public key hash. Since we can't do a full Bech32 decode in Solidity,
        // we'll perform a simple string comparison of parts after the prefix
        
        // If the wallet address starts with "mx1" and the validator with "mxvaloper1",
        // they might correspond even with different checksum parts
        
        // Check if the first part matches (the "1" separator character)
        bytes memory validatorOpBytes = bytes(validatorOperator);
        if (validatorOpBytes.length > 0 && validatorOpBytes[0] == bytes1('1') &&
            walletOperatorBytes.length > 0 && walletOperatorBytes[0] == bytes1('1')) {
            
            // Start checking from the second character (after "1")
            uint256 minLength = validatorOpBytes.length < walletOperatorBytes.length ? 
                validatorOpBytes.length : walletOperatorBytes.length;
            
            // Compare a reasonable number of characters (the pubkey portion)
            uint256 checkLength = minLength > 20 ? 20 : minLength;
            
            // Skip the first character ("1") in the comparison
            uint256 matchCount = 0;
            for (uint i = 1; i < checkLength; i++) {
                if (validatorOpBytes[i] == walletOperatorBytes[i]) {
                    matchCount++;
                }
            }
            
            // Allow for a partial match (80% similarity)
            return matchCount >= (checkLength - 1) * 8 / 10;
        }
        
        return false;
    }
    
    /**
     * @dev Generates a request ID for unstake requests
     * @param staker The address of the staker
     * @param validatorId The validator ID
     * @param amount The unstake amount
     * @param timestamp The request timestamp
     * @return requestId The generated request ID
     */
    function generateRequestId(
        address staker,
        string memory validatorId,
        uint256 amount,
        uint256 timestamp
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(staker, validatorId, amount, timestamp);
    }
    
    /**
     * @dev Validates the staking parameters
     * @param amount The amount to stake
     * @param minAmount The minimum staking amount
     * @param enforceMinimums Whether to enforce minimum amounts
     * @return isValid Whether the parameters are valid
     * @return errorMessage The error message if not valid
     */
    function validateStakingParams(
        uint256 amount,
        uint256 minAmount,
        bool enforceMinimums
    ) internal pure returns (bool isValid, string memory errorMessage) {
        // Check for zero amount
        if (amount == 0) {
            return (false, "Amount must be greater than 0");
        }
        
        // Check for minimum amount if enforced
        if (enforceMinimums && amount < minAmount) {
            return (false, "Amount below minimum");
        }
        
        return (true, "");
    }
    
    /**
     * @dev Calculates the APR reward for a staking amount over a period
     * @param amount The staked amount
     * @param apr The annual percentage rate (18 decimals)
     * @param timeInSeconds Time in seconds
     * @return The reward amount
     */
    function calculateAPRReward(
        uint256 amount,
        uint256 apr,
        uint256 timeInSeconds
    ) internal pure returns (uint256) {
        uint256 secondsInYear = 365 days;
        
        // Calculate: amount * apr * (timeInSeconds / secondsInYear)
        return (amount * apr * timeInSeconds) / (secondsInYear * 1e18);
    }
    
    /**
     * @dev Checks if a request ID is valid (non-empty)
     * @param requestId The request ID to validate
     * @return isValid Whether the request ID is valid
     */
    function isValidRequestId(bytes memory requestId) internal pure returns (bool isValid) {
        return requestId.length > 0;
    }
} 