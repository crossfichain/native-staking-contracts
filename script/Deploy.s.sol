// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/deployment/DeploymentCoordinator.sol";

contract DeployScript is Script {
    function run() external {
        // Get deployment parameters from environment
        address admin = vm.envAddress("ADMIN_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the entire system using the coordinator
        DeploymentCoordinator coordinator = new DeploymentCoordinator();
        address managerProxy = coordinator.deploySystem(admin);
        
        // Log important addresses
        console.log("--- CrossFi Native Staking Deployment ---");
        console.log("WXFI Address:", coordinator.wxfi());
        console.log("Oracle Proxy:", coordinator.oracleProxy());
        console.log("Native Staking (APR) Proxy:", coordinator.nativeStakingProxy());
        console.log("Native Staking Vault (APY) Proxy:", coordinator.nativeStakingVaultProxy());
        console.log("Native Staking Manager Proxy:", managerProxy);
        console.log("Proxy Admin:", coordinator.proxyAdmin());
        console.log("--------------------------------------");
        
        vm.stopBroadcast();
    }
} 