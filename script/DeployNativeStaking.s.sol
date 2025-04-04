// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "lib/forge-std/src/Script.sol";
import "../src/core/NativeStaking.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract DeployNativeStaking is Script {
    // Define the OPERATOR_ROLE constant to match the one in NativeStaking
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    function run() external {
        // Get deployment parameters from environment variables
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        uint256 minStakeAmount = vm.envUint("MIN_STAKE_AMOUNT");
        
        // Ensure required parameters are set
        require(admin != address(0), "ADMIN_ADDRESS not set");
        
        // Begin recording transactions for deployment
        vm.startBroadcast();
        
        // Deploy implementation contract
        NativeStaking stakingImpl = new NativeStaking();
        
        // Initialize data for proxy
        bytes memory initData = abi.encodeWithSelector(
            NativeStaking.initialize.selector,
            admin,
            minStakeAmount
        );
        
        // Deploy proxy with implementation
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(stakingImpl),
            initData
        );
        
        // Get the deployed proxy address
        address proxyAddress = address(proxy);
        
        // Setup operator role if provided
        if (operator != address(0)) {
            // Call the proxy with the correct function signature for grantRole
            (bool success, ) = proxyAddress.call(
                abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector,
                    OPERATOR_ROLE,
                    operator
                )
            );
            require(success, "Failed to grant operator role");
        }
        
        // End recording transactions
        vm.stopBroadcast();
        
        // Log deployed addresses
        console.log("NativeStaking Implementation deployed at:", address(stakingImpl));
        console.log("NativeStaking Proxy deployed at:", proxyAddress);
    }
} 