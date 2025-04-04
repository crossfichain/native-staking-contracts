// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ValidatorAddressUtils
 * @dev Utilities for validating and working with Cosmos validator addresses in Solidity
 */
library ValidatorAddressUtils {
    // Address prefixes
    string constant VALIDATOR_PREFIX = "mxvaloper";
    string constant WALLET_PREFIX = "mx";
    
    /**
     * @dev Checks if a validator address is valid
     * @param validatorAddr The validator address to check
     * @return isValid Whether the address is valid
     */
    function isValidValidatorAddress(string memory validatorAddr) internal pure returns (bool isValid) {
        bytes memory addrBytes = bytes(validatorAddr);
        
        // Check for minimum valid length (prefix + at least 1 character)
        if (addrBytes.length < bytes(VALIDATOR_PREFIX).length + 1) {
            return false;
        }
        
        // Check prefix
        for (uint i = 0; i < bytes(VALIDATOR_PREFIX).length; i++) {
            if (addrBytes[i] != bytes(VALIDATOR_PREFIX)[i]) {
                return false;
            }
        }
        
        // Check for valid Bech32 format (basic validation)
        // Bech32 addresses should be mostly alphanumeric
        // A full implementation would decode the Bech32 format
        bool hasValidChars = true;
        for (uint i = bytes(VALIDATOR_PREFIX).length; i < addrBytes.length; i++) {
            bytes1 char = addrBytes[i];
            // Allow only alphanumeric characters
            if (!((char >= bytes1('a') && char <= bytes1('z')) ||
                  (char >= bytes1('0') && char <= bytes1('9')) ||
                  (char == bytes1('1')))) {
                hasValidChars = false;
                break;
            }
        }
        
        // Typical validator address length is around 48-50 chars
        bool hasValidLength = addrBytes.length >= 40 && addrBytes.length <= 60;
        
        return hasValidChars && hasValidLength;
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
        
        bytes memory addrBytes = bytes(validatorAddr);
        bytes memory prefixBytes = bytes(VALIDATOR_PREFIX);
        bytes memory result = new bytes(addrBytes.length - prefixBytes.length);
        
        for (uint i = 0; i < result.length; i++) {
            result[i] = addrBytes[i + prefixBytes.length];
        }
        
        return string(result);
    }
    
    /**
     * @dev Converts a validator address to its corresponding wallet address
     * @param validatorAddr The validator address (mxvaloper...)
     * @return accountAddr The corresponding wallet address (mx...)
     */
    function validatorToAccountAddress(string memory validatorAddr) internal pure returns (string memory accountAddr) {
        if (!isValidValidatorAddress(validatorAddr)) {
            return "";
        }
        
        string memory bech32Part = extractBech32Part(validatorAddr);

        // In a full implementation, we would:
        // 1. Decode the Bech32 address
        // 2. Change the HRP (human readable part) from "mxvaloper" to "mx"
        // 3. Re-encode as Bech32

        // For now, we provide a compatibility conversion that changes the prefix
        // but preserves the rest of the components
        bytes memory bech32Bytes = bytes(bech32Part);
        
        // Make sure the first character is '1' as expected in Bech32
        if (bech32Bytes.length > 0 && bech32Bytes[0] == bytes1('1')) {
            return string(abi.encodePacked(WALLET_PREFIX, bech32Part));
        }
        
        return "";
    }
    
    /**
     * @dev Converts a validator address to its corresponding EVM address
     * @notice This is a deterministic mapping for CrossFi
     * @param validatorAddr The validator address (mxvaloper...)
     * @return evmAddr The corresponding EVM address
     */
    function validatorToEVMAddress(string memory validatorAddr) internal pure returns (address evmAddr) {
        if (!isValidValidatorAddress(validatorAddr)) return address(0);
        
        // In CrossFi, EVM addresses are derived deterministically from validator addresses
        // Since we can't implement the full cryptographic conversion in pure Solidity,
        // we provide a deterministic mapping based on the input string
        
        // To make this more robust, we hash both the full validator address 
        // and the extracted bech32 part for better uniqueness
        string memory bech32Part = extractBech32Part(validatorAddr);
        bytes32 hash = keccak256(abi.encodePacked(validatorAddr, bech32Part));
        
        // Use the hash to generate a deterministic EVM address
        return address(uint160(uint256(hash)));
    }

    /**
     * @dev Indicates whether validatorToEVMAddress uses the actual CrossFi derivation
     * @return isAccurate Whether the derivation is accurate for production
     */
    function isAccurateEVMDerivation() internal pure returns (bool isAccurate) {
        // Return false to indicate this is not using the actual derivation algorithm
        // This should be overridden in a production environment
        return false;
    }
    
    /**
     * @dev Converts a hex string to the corresponding address
     * @param hexStr The hex string (without 0x prefix)
     * @return addr The address
     */
    function hexToAddress(string memory hexStr) internal pure returns (address addr) {
        bytes memory strBytes = bytes(hexStr);
        
        // Check for valid hex string of appropriate length
        if (strBytes.length != 40) return address(0);
        
        uint160 iaddr = 0;
        uint8 b;
        
        for (uint i = 0; i < 40; i++) {
            b = uint8(strBytes[i]);
            
            if (b >= 48 && b <= 57) {
                // 0-9
                b -= 48;
            } else if (b >= 65 && b <= 70) {
                // A-F
                b -= 55;
            } else if (b >= 97 && b <= 102) {
                // a-f
                b -= 87;
            } else {
                // Invalid character
                return address(0);
            }
            
            iaddr = iaddr * 16 + uint160(b);
        }
        
        return address(iaddr);
    }
    
    /**
     * @dev Converts an address to its hex string representation
     * @param addr The address
     * @return hexStr The hex string (without 0x prefix)
     */
    function addressToHex(address addr) internal pure returns (string memory hexStr) {
        bytes memory result = new bytes(40);
        uint160 value = uint160(addr);
        
        // Convert to hex, starting from the rightmost character
        for (uint i = 0; i < 40; i++) {
            uint8 digit = uint8(value & 0xf);
            
            if (digit < 10) {
                result[39 - i] = bytes1(uint8(48 + digit)); // 0-9
            } else {
                result[39 - i] = bytes1(uint8(87 + digit)); // a-f
            }
            
            value >>= 4;
        }
        
        return string(result);
    }

    /**
     * @dev A legacy function name. Use validatorToEVMAddress instead.
     */
    function mockValidatorToEVMAddress(string memory validatorAddr) internal pure returns (address addr) {
        return validatorToEVMAddress(validatorAddr);
    }
} 