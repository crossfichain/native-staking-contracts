// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Verify
 * @dev Helper script for verifying deployed contracts on block explorers
 */
contract Verify is Script {
    using Strings for address;
    
    // Configuration
    address public wxfi;
    address public oracleProxy;
    address public nativeStakingProxy;
    address public nativeStakingVaultProxy;
    address public nativeStakingManagerProxy;
    
    function run() external {
        // Fetch addresses from environment variables
        wxfi = vm.envAddress("WXFI_ADDRESS");
        oracleProxy = vm.envAddress("ORACLE_PROXY_ADDRESS");
        nativeStakingProxy = vm.envAddress("NATIVE_STAKING_PROXY_ADDRESS");
        nativeStakingVaultProxy = vm.envAddress("NATIVE_STAKING_VAULT_PROXY_ADDRESS");
        nativeStakingManagerProxy = vm.envAddress("NATIVE_STAKING_MANAGER_PROXY_ADDRESS");
        
        // Log addresses for verification
        console.log("Contract addresses for verification:");
        console.log("WXFI:", wxfi);
        console.log("Oracle Proxy:", oracleProxy);
        console.log("NativeStaking Proxy:", nativeStakingProxy);
        console.log("NativeStakingVault Proxy:", nativeStakingVaultProxy);
        console.log("NativeStakingManager Proxy:", nativeStakingManagerProxy);
        
        // Instructions for verifying contracts
        console.log("\nTo verify contracts, run:");
        console.log("forge verify-contract --chain [CHAIN_ID]", wxfi, "src/periphery/WXFI.sol:WXFI");
        
        console.log("\nFor proxy contracts, you need to verify their implementations. Look at the contract interfaces to understand the initialization parameters.");
    }
} 