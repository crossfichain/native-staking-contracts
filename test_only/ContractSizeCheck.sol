// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../src/core/BaseNativeStakingManager.sol";
import "../src/core/SplitNativeStakingManager.sol";
import "../src/core/NativeStakingManagerLib.sol";

/**
 * @title ContractSizeCheck
 * @dev Utility to check contract sizes after splitting
 */
contract ContractSizeCheck {
    // Deploy test instances
    BaseNativeStakingManager public baseContract;
    SplitNativeStakingManager public splitContract;
    
    // Custom logging event to display contract sizes
    event ContractSizeInfo(string name, uint256 size, bool withinLimit);
    
    // Ethereum contract size limit (24576 bytes)
    uint256 constant CONTRACT_SIZE_LIMIT = 24576;
    
    /**
     * @dev Method to get contract code size
     */
    function getContractSize(address _contract) public view returns (uint256) {
        uint256 size;
        assembly {
            size := extcodesize(_contract)
        }
        return size;
    }
    
    /**
     * @dev Run the check
     */
    function run() external {
        // Deploy test instances
        splitContract = new SplitNativeStakingManager();
        
        // Get size of each contract
        uint256 libSize = type(NativeStakingManagerLib).runtimeCodeSize;
        uint256 splitSize = getContractSize(address(splitContract));
        
        // Log sizes
        emit ContractSizeInfo("NativeStakingManagerLib", libSize, libSize <= CONTRACT_SIZE_LIMIT);
        emit ContractSizeInfo("SplitNativeStakingManager", splitSize, splitSize <= CONTRACT_SIZE_LIMIT);
        
        // Output results
        string memory result = "Contract Split Result: ";
        
        if (splitSize <= CONTRACT_SIZE_LIMIT && libSize <= CONTRACT_SIZE_LIMIT) {
            result = string.concat(result, "SUCCESS - All contracts within size limit!");
        } else {
            result = string.concat(result, "FAILURE - One or more contracts exceed size limit!");
        }
        
        // Print original size and estimated size reduction
        uint256 originalSize = 29140; // From checklist documentation
        uint256 totalNewSize = splitSize + libSize;
        uint256 reduction = originalSize > totalNewSize ? originalSize - totalNewSize : 0;
        uint256 reductionPercent = (reduction * 100) / originalSize;
        
        string memory sizeInfo = string.concat(
            "Original size: ", toString(originalSize), " bytes\n",
            "New size (split): ", toString(splitSize), " bytes\n",
            "Library size: ", toString(libSize), " bytes\n",
            "Total size: ", toString(totalNewSize), " bytes\n",
            "Size reduction: ", toString(reduction), " bytes (", toString(reductionPercent), "%)"
        );
        
        // Log results
        emit log(result);
        emit log(sizeInfo);
    }
    
    /**
     * @dev Convert uint to string
     */
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        
        uint256 temp = value;
        uint256 digits;
        
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
    
    /**
     * @dev Foundry console log
     */
    event log(string message);
    event log_uint(uint256 value);
} 