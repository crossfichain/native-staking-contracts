// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// import {Script, console} from "forge-std/Script.sol";
// import "../../src/periphery/UnifiedOracle.sol";
// import "../../src/core/NativeStaking.sol";
// import "../../src/core/NativeStakingVault.sol";
// import "../../src/core/NativeStakingManager.sol";
// import "../../src/periphery/WXFI.sol";

// /**
//  * @title PostDeploymentSetup
//  * @dev Script for setting up contracts after deployment
//  * This includes granting roles, setting initial values, and other configurations
//  */
// contract PostDeploymentSetup is Script {
//     // Address variables - set in .env or passed as parameters
//     address public wxfi;
//     address public oracleProxy;
//     address public aprStakingProxy;
//     address public apyStakingProxy;
//     address public stakingManagerProxy;
//     address public adminAddress;
//     address public operatorAddress;
//     address public treasuryAddress;
//     address public emergencyAddress;
    
//     // Define role constants - these should match the exact role definitions in the contracts
//     bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
//     bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
//     bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
//     bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
//     bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
//     bytes32 public constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
//     bytes32 public constant COMPOUNDER_ROLE = keccak256("COMPOUNDER_ROLE");
//     bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
//     function run() public {
//         // Load deploy key
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
//         // Load addresses from environment
//         wxfi = vm.envAddress("WXFI_ADDRESS");
//         oracleProxy = vm.envAddress("ORACLE_PROXY_ADDRESS");
//         aprStakingProxy = vm.envAddress("APR_STAKING_PROXY_ADDRESS");
//         apyStakingProxy = vm.envAddress("APY_STAKING_PROXY_ADDRESS");
//         stakingManagerProxy = vm.envAddress("STAKING_MANAGER_PROXY_ADDRESS");
        
//         // Load role addresses
//         adminAddress = vm.envAddress("ADMIN_ADDRESS");
//         operatorAddress = vm.envAddress("OPERATOR_ADDRESS");
//         treasuryAddress = vm.envAddress("TREASURY_ADDRESS");
//         emergencyAddress = vm.envAddress("EMERGENCY_ADDRESS");
        
//         // Log addresses
//         console.log("Setting up roles for the following addresses:");
//         console.log("Admin:", adminAddress);
//         console.log("Operator:", operatorAddress);
//         console.log("Treasury:", treasuryAddress);
//         console.log("Emergency:", emergencyAddress);
        
//         // Run setup functions
//         vm.startBroadcast(deployerPrivateKey);
        
//         setupRoles();
//         configureOracle();
        
//         vm.stopBroadcast();
        
//         console.log("Post-deployment setup completed successfully");
//     }
    
//     function setupRoles() internal {
//         console.log("\nSetting up roles...");
        
//         // Cast to contracts
//         UnifiedOracle oracle = UnifiedOracle(oracleProxy);
//         NativeStaking aprStaking = NativeStaking(aprStakingProxy);
//         NativeStakingVault apyStaking = NativeStakingVault(apyStakingProxy);
//         NativeStakingManager stakingManager = NativeStakingManager(payable(stakingManagerProxy));
        
//         // 1. Set up admin roles
//         console.log("Setting up admin roles");
//         // Admin already has admin role from deployment, but let's verify
//         require(oracle.hasRole(DEFAULT_ADMIN_ROLE, adminAddress), "Admin missing admin role in Oracle");
//         require(aprStaking.hasRole(DEFAULT_ADMIN_ROLE, adminAddress), "Admin missing admin role in APR Staking");
//         require(apyStaking.hasRole(DEFAULT_ADMIN_ROLE, adminAddress), "Admin missing admin role in APY Staking");
//         require(stakingManager.hasRole(DEFAULT_ADMIN_ROLE, adminAddress), "Admin missing admin role in Manager");
        
//         // 2. Set up operator roles
//         console.log("Setting up operator roles");
//         // Oracle updater role
//         if (!oracle.hasRole(ORACLE_UPDATER_ROLE, operatorAddress)) {
//             oracle.grantRole(ORACLE_UPDATER_ROLE, operatorAddress);
//         }
        
//         // Pauser role
//         if (!oracle.hasRole(PAUSER_ROLE, operatorAddress)) {
//             oracle.grantRole(PAUSER_ROLE, operatorAddress);
//         }
        
//         // Staking manager role in APR and APY contracts
//         if (!aprStaking.hasRole(STAKING_MANAGER_ROLE, stakingManagerProxy)) {
//             aprStaking.grantRole(STAKING_MANAGER_ROLE, stakingManagerProxy);
//         }
        
//         if (!apyStaking.hasRole(STAKING_MANAGER_ROLE, stakingManagerProxy)) {
//             apyStaking.grantRole(STAKING_MANAGER_ROLE, stakingManagerProxy);
//         }
        
//         // Fulfiller role in Manager
//         if (!stakingManager.hasRole(FULFILLER_ROLE, operatorAddress)) {
//             stakingManager.grantRole(FULFILLER_ROLE, operatorAddress);
//         }
        
//         // Compounder role in APY Staking
//         if (!apyStaking.hasRole(COMPOUNDER_ROLE, operatorAddress)) {
//             apyStaking.grantRole(COMPOUNDER_ROLE, operatorAddress);
//         }
        
//         // 3. Set up emergency roles
//         console.log("Setting up emergency roles");
//         if (!aprStaking.hasRole(EMERGENCY_ROLE, emergencyAddress)) {
//             aprStaking.grantRole(EMERGENCY_ROLE, emergencyAddress);
//         }
        
//         if (!apyStaking.hasRole(EMERGENCY_ROLE, emergencyAddress)) {
//             apyStaking.grantRole(EMERGENCY_ROLE, emergencyAddress);
//         }
        
//         // 4. Set up treasury
//         console.log("Setting treasury address");
//         // Not all contract has treasury management, but some might
        
//         console.log("Roles setup completed");
//     }
    
//     function configureOracle() internal {
//         console.log("\nConfiguring Oracle settings...");
        
//         UnifiedOracle oracle = UnifiedOracle(oracleProxy);
        
//         // Example: Set initial parameters
//         // Values should be configured according to deployment requirements
//         oracle.setCurrentAPR(10); // 10% APR
//         oracle.setCurrentAPY(8);  // 8% APY
//         oracle.setUnbondingPeriod(21 days);
        
//         // Check if Oracle has a valid XFI price
//         (uint256 xfiPrice, uint256 timestamp) = oracle.getXFIPrice();
//         bool needsFallbackPrice = (xfiPrice == 0 || block.timestamp - timestamp > 1 days);
        
//         // Set fallback price if needed
//         if (needsFallbackPrice) {
//             oracle.setPrice("XFI", 1 ether); // $1
//             console.log("Set fallback XFI price: $1");
//         } else {
//             console.log("Oracle has fresh XFI price:", xfiPrice);
//         }
        
//         console.log("Oracle configuration completed");
//     }
// } 