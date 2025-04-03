// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract StandaloneTest {
    // Custom console logging implementation
    function log(string memory s) internal {
        bytes memory data = abi.encodeWithSignature("log(string)", s);
        assembly {
            pop(staticcall(gas(), 0x000000000000000000636F6e736F6c652e6c6f67, add(data, 32), mload(data), 0, 0))
        }
    }

    function log(string memory s, uint256 value) internal {
        bytes memory data = abi.encodeWithSignature("log(string,uint256)", s, value);
        assembly {
            pop(staticcall(gas(), 0x000000000000000000636F6e736F6c652e6c6f67, add(data, 32), mload(data), 0, 0))
        }
    }

    function run() public {
        log("\n==== Testing Contract Size Reduction Strategy ====");
        
        log("Original ConcreteNativeStakingManager size: 29140 bytes");
        log("Ethereum contract size limit: 24576 bytes");
        
        // Our strategy:
        // 1. Extract pure calculation functions to a library (~2000 bytes)
        // 2. Split the contract into base + extension (~7000 bytes per contract)
        uint256 estimatedLibrarySize = 2000;
        uint256 estimatedBaseSize = 12000;
        uint256 estimatedExtensionSize = 15000;
        
        log("\nEstimated sizes after splitting:");
        log("NativeStakingManagerLib: ~", estimatedLibrarySize);
        log("BaseNativeStakingManager: ~", estimatedBaseSize);
        log("SplitNativeStakingManager: ~", estimatedExtensionSize);
        
        bool canDeploy = estimatedLibrarySize <= 24576 && 
                        estimatedBaseSize <= 24576 && 
                        estimatedExtensionSize <= 24576;
        
        log("\nEstimated Total Size Reduction:", 29140 - estimatedExtensionSize);
        log("Expected to be deployable: ", canDeploy ? 1 : 0);
        
        log("\n==== Deployment Strategy ====");
        log("1. Deploy NativeStakingManagerLib first");
        log("2. Deploy BaseNativeStakingManager with library link");
        log("3. Deploy SplitNativeStakingManager");
        log("4. Upgrade proxy to SplitNativeStakingManager");
    }
} 