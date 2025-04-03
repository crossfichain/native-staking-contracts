// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// import {Script, console} from "forge-std/Script.sol";
// import "../../src/periphery/UnifiedOracle.sol";
// import "../../src/core/NativeStaking.sol";
// import "../../src/core/NativeStakingVault.sol";
// import "../../src/core/NativeStakingManager.sol";
// import "../../src/periphery/WXFI.sol";
// import "../../src/deployment/DeploymentCoordinator.sol";
// import "../utils/MockDIAOracle.sol";

// /**
//  * @title MasterDeployment
//  * @dev Single entry point for deployment of the Native Staking system
//  * Handles both production and development environments
//  */
// contract MasterDeployment is Script {
//     // Configuration 
//     struct DeploymentConfig {
//         // Environment
//         bool isProduction;
//         string networkName;
        
//         // Pre-deployed contract addresses (for production)
//         address existingWXFI;
//         address existingDIAOracle;
        
//         // Role addresses
//         address adminAddress;
//         address operatorAddress;
//         address treasuryAddress;
//         address emergencyAddress;
        
//         // Initial settings
//         uint256 initialAPR;     // with 18 decimals (e.g., 10 * 1e18 = 10%)
//         uint256 initialAPY;     // with 18 decimals
//         uint256 unbondingPeriod; // in seconds
//         uint256 xfiInitialPrice; // with 18 decimals
//         bool setLaunchTimestamp; // whether to set launch timestamp to current block time
//     }
    
//     // Deployed contract addresses
//     address public wxfi;
//     address public diaOracle;
//     address public oracleProxy;
//     address public aprStakingProxy;
//     address public apyStakingProxy;
//     address payable public stakingManagerProxy;
//     address public proxyAdmin;
    
//     function run() public {
//         // Get configuration from environment or initialize with defaults
//         DeploymentConfig memory config = getDeploymentConfig();
        
//         // Load deployment private key
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         address deployer = vm.addr(deployerPrivateKey);
        
//         console.log("\n=== CrossFi Native Staking Deployment ===");
//         console.log("Network:", config.networkName);
//         console.log("Environment:", config.isProduction ? "Production" : "Development");
//         console.log("Deployer:", deployer);
//         console.log("Admin:", config.adminAddress);
//         console.log("Operator:", config.operatorAddress);
        
//         // Handle different deployment scenarios
//         if (config.isProduction) {
//             // Production: Use existing contracts when available
//             handleProductionDeployment(config, deployerPrivateKey);
//         } else {
//             // Development: Deploy everything from scratch
//             handleDevelopmentDeployment(config, deployerPrivateKey);
//         }
        
//         // Final step: Save deployment info and display summary
//         saveDeploymentInfo();
//         displaySummary();
//     }
    
//     function getDeploymentConfig() internal returns (DeploymentConfig memory) {
//         DeploymentConfig memory config;
        
//         // Check if we're in production mode
//         config.isProduction = vm.envOr("PRODUCTION", false);
        
//         // Get network name for logging
//         string memory network = vm.envOr("NETWORK", string("development"));
//         config.networkName = network;
        
//         // Get existing contract addresses for production
//         if (config.isProduction) {
//             if (vm.envExists("WXFI_ADDRESS")) {
//                 config.existingWXFI = vm.envAddress("WXFI_ADDRESS");
//             }
            
//             if (vm.envExists("DIA_ORACLE_ADDRESS")) {
//                 config.existingDIAOracle = vm.envAddress("DIA_ORACLE_ADDRESS");
//             } else {
//                 require(false, "Production deployment requires DIA_ORACLE_ADDRESS");
//             }
//         }
        
//         // Role addresses
//         config.adminAddress = vm.envAddress("ADMIN_ADDRESS");
//         require(config.adminAddress != address(0), "ADMIN_ADDRESS must be set");
        
//         config.operatorAddress = vm.envAddress("OPERATOR_ADDRESS");
//         require(config.operatorAddress != address(0), "OPERATOR_ADDRESS must be set");
        
//         config.treasuryAddress = vm.envAddress("TREASURY_ADDRESS");
//         require(config.treasuryAddress != address(0), "TREASURY_ADDRESS must be set");
        
//         config.emergencyAddress = vm.envAddress("EMERGENCY_ADDRESS");
//         require(config.emergencyAddress != address(0), "EMERGENCY_ADDRESS must be set");
        
//         // Initial settings with defaults
//         config.initialAPR = vm.envOr("INITIAL_APR", 10e18); // 10% default
//         config.initialAPY = vm.envOr("INITIAL_APY", 8e18);  // 8% default
//         config.unbondingPeriod = vm.envOr("UNBONDING_PERIOD", 21 days);
//         config.xfiInitialPrice = vm.envOr("XFI_INITIAL_PRICE", 1 ether); // $1 default
//         config.setLaunchTimestamp = vm.envOr("SET_LAUNCH_TIMESTAMP", true);
        
//         return config;
//     }
    
//     function handleProductionDeployment(DeploymentConfig memory config, uint256 deployerPrivateKey) internal {
//         console.log("\n=== Starting Production Deployment ===");
//         vm.startBroadcast(deployerPrivateKey);
        
//         // 1. Set the DIA Oracle address
//         diaOracle = config.existingDIAOracle;
//         console.log("Using existing DIA Oracle at:", diaOracle);
        
//         // 2. Handle WXFI deployment or use existing
//         if (config.existingWXFI != address(0)) {
//             wxfi = config.existingWXFI;
//             console.log("Using existing WXFI at:", wxfi);
//         } else {
//             // Deploy new WXFI contract
//             WXFI wxfiContract = new WXFI();
//             wxfi = address(wxfiContract);
//             console.log("Deployed new WXFI at:", wxfi);
//         }
        
//         // 3. Deploy the main system
//         deployMainSystem(config);
        
//         // 4. Configure roles and settings
//         configureSystem(config);
        
//         vm.stopBroadcast();
//     }
    
//     function handleDevelopmentDeployment(DeploymentConfig memory config, uint256 deployerPrivateKey) internal {
//         console.log("\n=== Starting Development Deployment ===");
//         vm.startBroadcast(deployerPrivateKey);
        
//         // 1. Deploy Mock DIA Oracle
//         MockDIAOracle mockDiaOracleContract = new MockDIAOracle();
//         diaOracle = address(mockDiaOracleContract);
        
//         // Initialize the mock with test data
//         mockDiaOracleContract.setPrice("XFI/USD", 1e8); // $1 with 8 decimals
//         console.log("Deployed Mock DIA Oracle at:", diaOracle);
        
//         // 2. Deploy WXFI
//         WXFI wxfiContract = new WXFI();
//         wxfi = address(wxfiContract);
//         console.log("Deployed WXFI at:", wxfi);
        
//         // 3. Deploy the main system
//         deployMainSystem(config);
        
//         // 4. Configure roles and settings
//         configureSystem(config);
        
//         vm.stopBroadcast();
//     }
    
//     function deployMainSystem(DeploymentConfig memory config) internal {
//         console.log("\n=== Deploying Main System ===");
        
//         // Deploy the system using the coordinator
//         DeploymentCoordinator coordinator = new DeploymentCoordinator();
//         stakingManagerProxy = payable(coordinator.deploySystem(config.adminAddress, diaOracle));
        
//         // Get deployed addresses
//         wxfi = coordinator.wxfi();
//         oracleProxy = coordinator.oracleProxy();
//         aprStakingProxy = coordinator.nativeStakingProxy();
//         apyStakingProxy = coordinator.nativeStakingVaultProxy();
//         proxyAdmin = coordinator.proxyAdmin();
        
//         console.log("Main system deployed successfully");
//         console.log("Staking Manager at:", stakingManagerProxy);
//     }
    
//     function configureSystem(DeploymentConfig memory config) internal {
//         console.log("\n=== Configuring System ===");
        
//         // Cast to interfaces
//         UnifiedOracle oracle = UnifiedOracle(oracleProxy);
//         NativeStaking aprStaking = NativeStaking(aprStakingProxy);
//         NativeStakingVault apyStaking = NativeStakingVault(apyStakingProxy);
//         NativeStakingManager stakingManager = NativeStakingManager(payable(stakingManagerProxy));
        
//         // 1. Set up Oracle initial values
//         oracle.setCurrentAPR(config.initialAPR);
//         oracle.setCurrentAPY(config.initialAPY);
//         oracle.setUnbondingPeriod(config.unbondingPeriod);
//         oracle.setPrice("XFI", config.xfiInitialPrice);
//         oracle.setTotalStakedXFI(0); // Start with 0 staked
        
//         if (config.setLaunchTimestamp) {
//             oracle.setLaunchTimestamp(block.timestamp);
//             console.log("Launch timestamp set to:", block.timestamp);
//         }
        
//         // 2. Set up roles
//         // Admin roles are already set in the deployment
        
//         // Oracle roles
//         bytes32 oracleUpdaterRole = oracle.ORACLE_UPDATER_ROLE();
//         bytes32 pauserRole = oracle.PAUSER_ROLE();
        
//         oracle.grantRole(oracleUpdaterRole, config.operatorAddress);
//         oracle.grantRole(pauserRole, config.operatorAddress);
//         oracle.grantRole(pauserRole, config.emergencyAddress);
        
//         // APR Staking roles
//         bytes32 stakingManagerRole = aprStaking.STAKING_MANAGER_ROLE();
        
//         // Make sure operator has necessary roles
//         if (aprStaking.hasRole(bytes32(0), config.adminAddress)) {
//             // Use admin to grant roles (admin role is bytes32(0))
//             vm.startPrank(config.adminAddress);
            
//             // Give operator and emergency roles
//             aprStaking.grantRole(stakingManagerRole, address(stakingManager));
            
//             // Same for APY staking
//             apyStaking.grantRole(stakingManagerRole, address(stakingManager));
            
//             vm.stopPrank();
//         }
        
//         console.log("System configuration completed");
//     }
    
//     function saveDeploymentInfo() internal {
//         string memory networkName = vm.envOr("NETWORK", string("unknown"));
//         string memory timestamp = vm.toString(block.timestamp);
        
//         // Format: network,timestamp,chainId,wxfi,diaOracle,oracleProxy,aprStakingProxy,apyStakingProxy,stakingManagerProxy,proxyAdmin
//         string memory deploymentInfo = string.concat(
//             networkName, ",",
//             timestamp, ",",
//             vm.toString(block.chainid), ",",
//             vm.toString(wxfi), ",",
//             vm.toString(diaOracle), ",",
//             vm.toString(oracleProxy), ",",
//             vm.toString(aprStakingProxy), ",",
//             vm.toString(apyStakingProxy), ",",
//             vm.toString(stakingManagerProxy), ",",
//             vm.toString(proxyAdmin)
//         );
        
//         // Save to network-specific file
//         string memory filename = string.concat(
//             "deployments/", 
//             networkName, 
//             "-", 
//             vm.toString(block.chainid), 
//             "-deployment.csv"
//         );
        
//         vm.writeFile(filename, deploymentInfo);
//         console.log("Deployment info saved to:", filename);
//     }
    
//     function displaySummary() internal view {
//         console.log("\n========= DEPLOYMENT SUMMARY =========");
//         console.log("WXFI:", wxfi);
//         console.log("DIA Oracle:", diaOracle);
//         console.log("Oracle Proxy:", oracleProxy);
//         console.log("APR Staking Proxy:", aprStakingProxy);
//         console.log("APY Staking Proxy:", apyStakingProxy);
//         console.log("Staking Manager Proxy:", stakingManagerProxy);
//         console.log("Proxy Admin:", proxyAdmin);
//         console.log("=======================================");
//         console.log("\nNOTE: Use these addresses to update your .env file for verification and post-deployment scripts.");
//     }
// } 