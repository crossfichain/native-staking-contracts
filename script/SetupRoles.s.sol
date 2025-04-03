// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// import {Script} from "forge-std/Script.sol";
// import {NativeStaking} from "../src/core/NativeStaking.sol";
// import {CrossFiOracle} from "../src/periphery/CrossFiOracle.sol";
// import {console} from "forge-std/console.sol";

// contract SetupRolesScript is Script {
//     function run() external {
//         // Addresses from the deployment (replace with your actual deployed addresses)
//         address oracle = 0x619Fa7497172Fb48E77B845577c4e83FDFE15490;
//         address staking = 0xDbe735426C7DC01F0F153F9C769582a3b48784EC;

//         // Get private key from environment variables
//         uint256 privateKey = vm.envUint("DEV_PRIVATE_KEY");
//         address deployer = vm.addr(privateKey);
        
//         // Additional addresses for roles
//         address operator = vm.envAddress("OPERATOR_ADDRESS");
//         address emergency = vm.envAddress("EMERGENCY_ADDRESS");
//         address treasury = vm.envAddress("TREASURY_ADDRESS");
        
//         // Report addresses we're setting up
//         console.log("Deployer:", deployer);
//         console.log("Operator:", operator);
//         console.log("Emergency:", emergency);
//         console.log("Treasury:", treasury);
        
//         // Start broadcasting transactions
//         vm.startBroadcast(privateKey);
        
//         // Setup roles for Oracle
//         CrossFiOracle oracleContract = CrossFiOracle(oracle);
        
//         // Grant ORACLE_UPDATER_ROLE to operator
//         bytes32 ORACLE_UPDATER_ROLE = oracleContract.ORACLE_UPDATER_ROLE();
//         if (!oracleContract.hasRole(ORACLE_UPDATER_ROLE, operator)) {
//             oracleContract.grantRole(ORACLE_UPDATER_ROLE, operator);
//             console.log("Granted ORACLE_UPDATER_ROLE to operator");
//         }
        
//         // Setup roles for Staking
//         NativeStaking stakingContract = NativeStaking(staking);
        
//         // Grant OPERATOR_ROLE to operator
//         bytes32 OPERATOR_ROLE = stakingContract.OPERATOR_ROLE();
//         if (!stakingContract.hasRole(OPERATOR_ROLE, operator)) {
//             stakingContract.grantRole(OPERATOR_ROLE, operator);
//             console.log("Granted OPERATOR_ROLE to operator");
//         }
        
//         // Grant EMERGENCY_ROLE to emergency address
//         bytes32 EMERGENCY_ROLE = stakingContract.EMERGENCY_ROLE();
//         if (!stakingContract.hasRole(EMERGENCY_ROLE, emergency)) {
//             stakingContract.grantRole(EMERGENCY_ROLE, emergency);
//             console.log("Granted EMERGENCY_ROLE to emergency address");
//         }
        
//         // Set treasury address if needed
//         if (stakingContract.treasury() != treasury) {
//             stakingContract.setTreasury(treasury);
//             console.log("Set treasury address");
//         }
        
//         vm.stopBroadcast();
        
//         console.log("Role setup complete");
//     }
// } 