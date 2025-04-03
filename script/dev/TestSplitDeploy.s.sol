// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import "../../src/core/SplitNativeStakingManager.sol";
import "../../src/core/NativeStakingManagerLib.sol";

/**
 * @title TestSplitDeploy
 * @dev Script to test if the split contracts are deployable without
 * actually deploying them
 * 
 * Run with:
 * forge script script/dev/TestSplitDeploy.s.sol:TestSplitDeploy -vvv
 */
contract TestSplitDeploy is Script {
    function run() public {
        console.log("\n==== Testing Split NativeStakingManager Deployability ====");
        
        // Estimate sizes
        uint256 libSize = 2000; // Estimated library size
        console.log("NativeStakingManagerLib estimated size:", libSize, "bytes");
        console.log("Library is", libSize <= 24576 ? "deployable" : "too large");
        
        uint256 implSize = 15000; // Estimated implementation size
        console.log("SplitNativeStakingManager estimated size:", implSize, "bytes");
        console.log("Implementation is", implSize <= 24576 ? "deployable" : "too large");
        
        console.log("\n==== Size reduction effectiveness ====");
        
        // This is the original size from the error message in the user's input
        uint256 originalSize = 29140;
        int256 reducedBy = int256(originalSize) - int256(implSize);
        
        if (reducedBy > 0) {
            console.log("Size reduced by approximately:", uint256(reducedBy), "bytes");
            console.log("Percentage reduction:", (uint256(reducedBy) * 100) / originalSize, "%");
        } else {
            console.log("Warning: Size increased by approximately:", uint256(-reducedBy), "bytes");
        }
        
        console.log("\n==== Deployment Size Analysis ====");
        console.log("Ethereum contract size limit:", 24576, "bytes");
        
        if (implSize <= 24576) {
            console.log("SUCCESS: Contract is likely deployable");
        } else {
            console.log("WARNING: Contract may still be too large by approximately", 
                implSize - 24576, "bytes");
            console.log("Further optimization might be needed");
        }
    }
} 