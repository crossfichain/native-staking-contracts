// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.26;

// import {Script} from "forge-std/Script.sol";
// import {DeploymentCoordinator} from "../src/deployment/DeploymentCoordinator.sol";
// import {console} from "forge-std/console.sol";

// contract DeployScript is Script {
//     function run() external {
//         uint256 deployerPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
//         address deployer = vm.addr(deployerPrivateKey);
        
//         console.log("Deployer address:", deployer);
        
//         vm.startBroadcast(deployerPrivateKey);
        
//         // Deploy the deployment coordinator
//         DeploymentCoordinator coordinator = new DeploymentCoordinator();
        
//         // Call deploy on the coordinator
//         coordinator.deploy();
        
//         vm.stopBroadcast();
        
//         console.log("Deployment completed successfully!");
//         console.log("DeploymentCoordinator deployed at:", address(coordinator));
//     }
// } 