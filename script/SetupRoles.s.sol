// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NativeStaking} from "../src/NativeStaking.sol";
import {UnifiedOracle} from "../src/UnifiedOracle.sol";
import {console} from "forge-std/console.sol";

contract SetupRolesScript is Script {
    // Deployed contract addresses (from previous deployment)
    address constant STAKING_CONTRACT = 0xDbe735426C7DC01F0F153F9C769582a3b48784EC;
    address constant UNIFIED_ORACLE = 0x619Fa7497172Fb48E77B845577c4e83FDFE15490;
    
    // Tester account that needs permissions
    address constant TESTER_ACCOUNT = 0x79F9860d48ef9dDFaF3571281c033664de05E6f5;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Setup NativeStaking roles
        NativeStaking staking = NativeStaking(payable(STAKING_CONTRACT));
        
        // Grant operator role
        bytes32 operatorRole = staking.OPERATOR_ROLE();
        if (!staking.hasRole(operatorRole, TESTER_ACCOUNT)) {
            staking.grantRole(operatorRole, TESTER_ACCOUNT);
            console.log("Granted OPERATOR_ROLE to:", TESTER_ACCOUNT);
        }

        // Grant emergency role
        bytes32 emergencyRole = staking.EMERGENCY_ROLE();
        if (!staking.hasRole(emergencyRole, TESTER_ACCOUNT)) {
            staking.grantRole(emergencyRole, TESTER_ACCOUNT);
            console.log("Granted EMERGENCY_ROLE to:", TESTER_ACCOUNT);
        }

        // Setup UnifiedOracle roles
        UnifiedOracle oracle = UnifiedOracle(UNIFIED_ORACLE);
        
        // Grant oracle admin role
        bytes32 oracleAdminRole = oracle.ORACLE_ADMIN();
        if (!oracle.hasRole(oracleAdminRole, TESTER_ACCOUNT)) {
            oracle.grantRole(oracleAdminRole, TESTER_ACCOUNT);
            console.log("Granted ORACLE_ADMIN role to:", TESTER_ACCOUNT);
        }

        vm.stopBroadcast();
        
        console.log("\nRole setup completed!");
        console.log("Tester account", TESTER_ACCOUNT, "now has all necessary permissions:");
        console.log("- NativeStaking OPERATOR_ROLE");
        console.log("- NativeStaking EMERGENCY_ROLE");
        console.log("- UnifiedOracle ORACLE_ADMIN role");
    }
} 