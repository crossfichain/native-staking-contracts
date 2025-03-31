// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "../src/periphery/UnifiedOracle.sol";
import "../src/core/NativeStaking.sol";
import "../src/core/NativeStakingVault.sol";
import "../src/core/NativeStakingManager.sol";

/**
 * @title AddOperator
 * @dev Script for adding a new operator to all contracts with all possible roles
 */
contract AddOperator is Script {
    // Target addresses
    address constant NEW_OPERATOR = 0xc35e04979A78630F16e625902283720681f2932e;

    // Contract addresses
    address public oracle;
    address public nativeStaking;
    address public nativeStakingVault;
    address public nativeStakingManager;

    // Role constants
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    bytes32 constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
    bytes32 constant COMPOUNDER_ROLE = keccak256("COMPOUNDER_ROLE");
    bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Load contract addresses from environment variables
        oracle = vm.envAddress("ORACLE_ADDRESS");
        nativeStaking = vm.envAddress("NATIVE_STAKING_ADDRESS");
        nativeStakingVault = vm.envAddress("NATIVE_STAKING_VAULT_ADDRESS");
        nativeStakingManager = vm.envAddress("NATIVE_STAKING_MANAGER_ADDRESS");

        console.log("\n==== Adding New Operator ====");
        console.log("Deployer:         ", deployer);
        console.log("New Operator:     ", NEW_OPERATOR);
        console.log("Oracle:           ", oracle);
        console.log("Native Staking:   ", nativeStaking);
        console.log("Staking Vault:    ", nativeStakingVault);
        console.log("Staking Manager:  ", nativeStakingManager);

        vm.startBroadcast(deployerPrivateKey);
        setupRoles();
        vm.stopBroadcast();

        console.log("\n==== New Operator Added Successfully ====");
    }

    function setupRoles() internal {
        // Oracle Roles
        console.log("\nSetting up Oracle roles...");
        if (!AccessControl(oracle).hasRole(DEFAULT_ADMIN_ROLE, NEW_OPERATOR)) {
            AccessControl(oracle).grantRole(DEFAULT_ADMIN_ROLE, NEW_OPERATOR);
            console.log("Granted DEFAULT_ADMIN_ROLE on Oracle");
        }
        
        if (!AccessControl(oracle).hasRole(ORACLE_UPDATER_ROLE, NEW_OPERATOR)) {
            AccessControl(oracle).grantRole(ORACLE_UPDATER_ROLE, NEW_OPERATOR);
            console.log("Granted ORACLE_UPDATER_ROLE on Oracle");
        }
        
        if (!AccessControl(oracle).hasRole(PAUSER_ROLE, NEW_OPERATOR)) {
            AccessControl(oracle).grantRole(PAUSER_ROLE, NEW_OPERATOR);
            console.log("Granted PAUSER_ROLE on Oracle");
        }
        
        if (!AccessControl(oracle).hasRole(EMERGENCY_ROLE, NEW_OPERATOR)) {
            AccessControl(oracle).grantRole(EMERGENCY_ROLE, NEW_OPERATOR);
            console.log("Granted EMERGENCY_ROLE on Oracle");
        }

        // Native Staking Roles
        console.log("\nSetting up Native Staking roles...");
        if (!AccessControl(nativeStaking).hasRole(DEFAULT_ADMIN_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStaking).grantRole(DEFAULT_ADMIN_ROLE, NEW_OPERATOR);
            console.log("Granted DEFAULT_ADMIN_ROLE on Native Staking");
        }
        
        if (!AccessControl(nativeStaking).hasRole(STAKING_MANAGER_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStaking).grantRole(STAKING_MANAGER_ROLE, NEW_OPERATOR);
            console.log("Granted STAKING_MANAGER_ROLE on Native Staking");
        }
        
        if (!AccessControl(nativeStaking).hasRole(PAUSER_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStaking).grantRole(PAUSER_ROLE, NEW_OPERATOR);
            console.log("Granted PAUSER_ROLE on Native Staking");
        }
        
        if (!AccessControl(nativeStaking).hasRole(EMERGENCY_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStaking).grantRole(EMERGENCY_ROLE, NEW_OPERATOR);
            console.log("Granted EMERGENCY_ROLE on Native Staking");
        }

        // Native Staking Vault Roles
        console.log("\nSetting up Native Staking Vault roles...");
        if (!AccessControl(nativeStakingVault).hasRole(DEFAULT_ADMIN_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStakingVault).grantRole(DEFAULT_ADMIN_ROLE, NEW_OPERATOR);
            console.log("Granted DEFAULT_ADMIN_ROLE on Native Staking Vault");
        }
        
        if (!AccessControl(nativeStakingVault).hasRole(STAKING_MANAGER_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStakingVault).grantRole(STAKING_MANAGER_ROLE, NEW_OPERATOR);
            console.log("Granted STAKING_MANAGER_ROLE on Native Staking Vault");
        }
        
        if (!AccessControl(nativeStakingVault).hasRole(PAUSER_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStakingVault).grantRole(PAUSER_ROLE, NEW_OPERATOR);
            console.log("Granted PAUSER_ROLE on Native Staking Vault");
        }
        
        if (!AccessControl(nativeStakingVault).hasRole(EMERGENCY_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStakingVault).grantRole(EMERGENCY_ROLE, NEW_OPERATOR);
            console.log("Granted EMERGENCY_ROLE on Native Staking Vault");
        }
        
        if (!AccessControl(nativeStakingVault).hasRole(COMPOUNDER_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStakingVault).grantRole(COMPOUNDER_ROLE, NEW_OPERATOR);
            console.log("Granted COMPOUNDER_ROLE on Native Staking Vault");
        }

        // Native Staking Manager Roles
        console.log("\nSetting up Native Staking Manager roles...");
        if (!AccessControl(nativeStakingManager).hasRole(DEFAULT_ADMIN_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStakingManager).grantRole(DEFAULT_ADMIN_ROLE, NEW_OPERATOR);
            console.log("Granted DEFAULT_ADMIN_ROLE on Native Staking Manager");
        }
        
        if (!AccessControl(nativeStakingManager).hasRole(FULFILLER_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStakingManager).grantRole(FULFILLER_ROLE, NEW_OPERATOR);
            console.log("Granted FULFILLER_ROLE on Native Staking Manager");
        }
        
        if (!AccessControl(nativeStakingManager).hasRole(PAUSER_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStakingManager).grantRole(PAUSER_ROLE, NEW_OPERATOR);
            console.log("Granted PAUSER_ROLE on Native Staking Manager");
        }
        
        if (!AccessControl(nativeStakingManager).hasRole(EMERGENCY_ROLE, NEW_OPERATOR)) {
            AccessControl(nativeStakingManager).grantRole(EMERGENCY_ROLE, NEW_OPERATOR);
            console.log("Granted EMERGENCY_ROLE on Native Staking Manager");
        }
    }
} 