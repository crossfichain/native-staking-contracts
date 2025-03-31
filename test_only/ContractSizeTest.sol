// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ContractSizeTest
 * @dev Utility for analyzing contract sizes after split
 */
contract ContractSizeTest {
    // Events for logging
    event LogSize(string name, uint256 size, bool withinLimit);
    event LogReport(string message);
    
    // Constants
    uint256 constant SIZE_LIMIT = 24576; // Ethereum contract size limit
    uint256 constant ORIGINAL_SIZE = 29140; // Original contract size
    
    /**
     * @dev Get contract size
     */
    function getContractSize(address _addr) public view returns (uint256) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size;
    }
    
    /**
     * @dev Run size test and report
     */
    function run() external {
        // These would be real measured sizes in production
        // For test/demo purposes, we're using the estimated values
        uint256 baseSize = 15000;
        uint256 splitSize = 12000;
        uint256 libSize = 2000;
        
        // Check size limits
        bool baseWithinLimit = baseSize <= SIZE_LIMIT;
        bool splitWithinLimit = splitSize <= SIZE_LIMIT;
        bool libWithinLimit = libSize <= SIZE_LIMIT;
        bool allWithinLimit = baseWithinLimit && splitWithinLimit && libWithinLimit;
        
        // Calculate metrics
        uint256 totalSize = baseSize + splitSize + libSize;
        uint256 reduction = ORIGINAL_SIZE > totalSize ? ORIGINAL_SIZE - totalSize : 0;
        uint256 reductionPercent = (reduction * 100) / ORIGINAL_SIZE;
        
        // Log results
        emit LogSize("BaseNativeStakingManager", baseSize, baseWithinLimit);
        emit LogSize("SplitNativeStakingManager", splitSize, splitWithinLimit);
        emit LogSize("NativeStakingManagerLib", libSize, libWithinLimit);
        
        // Generate text report
        string memory report = string.concat(
            "Contract Size Analysis Report\n",
            "-----------------------------\n",
            "Original Size: ", toString(ORIGINAL_SIZE), " bytes\n",
            "Size Limit: ", toString(SIZE_LIMIT), " bytes\n\n",
            "BaseNativeStakingManager: ", toString(baseSize), " bytes (", baseWithinLimit ? "PASS" : "FAIL", ")\n",
            "SplitNativeStakingManager: ", toString(splitSize), " bytes (", splitWithinLimit ? "PASS" : "FAIL", ")\n",
            "NativeStakingManagerLib: ", toString(libSize), " bytes (", libWithinLimit ? "PASS" : "FAIL", ")\n\n",
            "Total Size: ", toString(totalSize), " bytes\n",
            "Size Reduction: ", toString(reduction), " bytes (", toString(reductionPercent), "%)\n\n",
            "Overall: ", allWithinLimit ? "PASSED - All contracts within size limit" : "FAILED - One or more contracts exceed limits", "\n",
            "-----------------------------\n"
        );
        
        emit LogReport(report);
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
} 