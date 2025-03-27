// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../src/core/NativeStaking.sol";
import "../src/core/NativeStakingManager.sol";
import "../src/core/NativeStakingVault.sol";
import "../src/oracle/UnifiedOracle.sol";
import "../src/periphery/WXFI.sol";
import "../src/core/ConcreteNativeStakingManager.sol";

contract DeployDev is Script {
    // Configuration constants
    uint256 public constant MIN_STAKE_AMOUNT = 50 ether;
    uint256 public constant MIN_UNSTAKE_AMOUNT = 10 ether;
    uint256 public constant MIN_REWARD_CLAIM = 1 ether;
    uint256 public constant INITIAL_FREEZE_TIME = 30 days;
    bool public constant ENFORCE_MINIMUMS = true;

    function run() external {
        // Get deployment private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy WXFI token
        WXFI wxfi = new WXFI();

        // Deploy Oracle
        UnifiedOracle oracle = new UnifiedOracle();
        oracle.initialize(msg.sender, 14 days);
        
        // Set initial APR to 10%
        oracle.updateAPR(10 * 1e16);
        
        // Optional: Set up oracle values
        oracle.updateAPY(8 * 1e16); // 8% APY

        // Deploy APR Staking contract
        NativeStaking aprStaking = new NativeStaking();
        aprStaking.initialize(address(oracle), address(wxfi));

        // Deploy APY Staking Vault
        NativeStakingVault apyVault = new NativeStakingVault();
        apyVault.initialize(
            address(wxfi),
            address(oracle),
            "XFI Staking Vault",
            "xXFI"
        );

        // Deploy Manager
        ConcreteNativeStakingManager manager = new ConcreteNativeStakingManager();
        manager.initialize(
            address(aprStaking),
            address(apyVault),
            address(wxfi),
            address(oracle),
            ENFORCE_MINIMUMS,
            INITIAL_FREEZE_TIME,
            MIN_STAKE_AMOUNT,
            MIN_UNSTAKE_AMOUNT,
            MIN_REWARD_CLAIM
        );

        // Setup roles
        bytes32 STAKING_MANAGER_ROLE = aprStaking.STAKING_MANAGER_ROLE();
        bytes32 COMPOUNDER_ROLE = apyVault.COMPOUNDER_ROLE();
        bytes32 ORACLE_MANAGER_ROLE = oracle.ORACLE_MANAGER_ROLE();

        // Grant roles
        aprStaking.grantRole(STAKING_MANAGER_ROLE, address(manager));
        apyVault.grantRole(STAKING_MANAGER_ROLE, address(manager));
        oracle.grantRole(ORACLE_MANAGER_ROLE, msg.sender);

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("Deployment completed:");
        console.log("WXFI:", address(wxfi));
        console.log("Oracle:", address(oracle));
        console.log("APR Staking:", address(aprStaking));
        console.log("APY Vault:", address(apyVault));
        console.log("Manager:", address(manager));
    }
} 