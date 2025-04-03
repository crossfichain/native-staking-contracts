// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// import {Script, console} from "forge-std/Script.sol";
// import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
// import "../../src/core/NativeStaking.sol";
// import "../../src/core/NativeStakingVault.sol";
// import "../../src/core/NativeStakingManager.sol";
// import "../../src/periphery/UnifiedOracle.sol";
// import "../../src/periphery/WXFI.sol";
// import "../../src/interfaces/INativeStakingManager.sol";
// import "../../src/interfaces/IDIAOracle.sol";
// import "../../src/deployment/DeploymentCoordinator.sol";

// /**
//  * @title DeploymentScript
//  * @dev Script for deploying the Native Staking system
//  * Supports both testnet and mainnet deployments
//  */
// contract DeploymentScript is Script {
//     // Deployment addresses - will be populated during deployment
//     address public wxfi;
//     address public oracleProxy;
//     address public aprStakingProxy;
//     address public apyStakingProxy;
//     address payable public stakingManagerProxy;
//     address public proxyAdmin;
//     address public diaOracleAddress;

//     function run() public {
//         // Load configuration from environment or config file
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         address adminAddress = vm.envAddress("ADMIN_ADDRESS");
        
//         // Check if DIA Oracle address is provided, otherwise deploy mock for testing
//         bool hasDiaOracle = vm.envExists("DIA_ORACLE_ADDRESS");
//         if (hasDiaOracle) {
//             diaOracleAddress = vm.envAddress("DIA_ORACLE_ADDRESS");
//             console.log("Using existing DIA Oracle at:", diaOracleAddress);
//         } else {
//             console.log("No DIA Oracle address provided, deploying a mock for testing");
//             diaOracleAddress = deployMockDIAOracle();
//         }
        
//         // Start broadcasting transactions
//         vm.startBroadcast(deployerPrivateKey);
        
//         // Deploy the system using the coordinator
//         DeploymentCoordinator coordinator = new DeploymentCoordinator();
//         stakingManagerProxy = payable(coordinator.deploySystem(adminAddress, diaOracleAddress));
        
//         // Get deployed addresses
//         wxfi = coordinator.wxfi();
//         oracleProxy = coordinator.oracleProxy();
//         aprStakingProxy = coordinator.nativeStakingProxy();
//         apyStakingProxy = coordinator.nativeStakingVaultProxy();
//         proxyAdmin = coordinator.proxyAdmin();
        
//         // Log deployed addresses
//         console.log("\n==== Native Staking System Deployed ====");
//         console.log("WXFI:", wxfi);
//         console.log("Oracle Proxy:", oracleProxy);
//         console.log("APR Staking Proxy:", aprStakingProxy);
//         console.log("APY Staking Proxy:", apyStakingProxy);
//         console.log("Staking Manager Proxy:", stakingManagerProxy);
//         console.log("Proxy Admin:", proxyAdmin);
//         console.log("DIA Oracle:", diaOracleAddress);
//         console.log("======================================\n");
        
//         // Save deployment addresses to a file
//         string memory deploymentInfo = vm.toString(block.chainid);
//         deploymentInfo = string.concat(deploymentInfo, ",", vm.toString(wxfi));
//         deploymentInfo = string.concat(deploymentInfo, ",", vm.toString(oracleProxy));
//         deploymentInfo = string.concat(deploymentInfo, ",", vm.toString(aprStakingProxy));
//         deploymentInfo = string.concat(deploymentInfo, ",", vm.toString(apyStakingProxy));
//         deploymentInfo = string.concat(deploymentInfo, ",", vm.toString(stakingManagerProxy));
//         deploymentInfo = string.concat(deploymentInfo, ",", vm.toString(proxyAdmin));
//         deploymentInfo = string.concat(deploymentInfo, ",", vm.toString(diaOracleAddress));
        
//         vm.writeFile(
//             string.concat("deployments/", vm.toString(block.chainid), "-deployment.csv"),
//             deploymentInfo
//         );
        
//         // Set initial values - can be customized per deployment
//         configureInitialSettings();
        
//         vm.stopBroadcast();
//     }
    
//     function deployMockDIAOracle() internal returns (address) {
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
//         vm.startBroadcast(deployerPrivateKey);
        
//         // Deploy a mock DIA Oracle for testing purposes
//         address mockDiaOracle = address(new MockDIAOracle());
        
//         // Set an initial price for XFI/USD
//         MockDIAOracle(mockDiaOracle).setPrice("XFI/USD", 1e8); // $1 with 8 decimals
        
//         vm.stopBroadcast();
        
//         return mockDiaOracle;
//     }
    
//     function configureInitialSettings() internal {
//         // Configure the Oracle with initial values
//         UnifiedOracle oracle = UnifiedOracle(oracleProxy);
        
//         // Set initial values - adjust as needed for specific deployments
//         oracle.setCurrentAPR(10);                // 10% APR
//         oracle.setCurrentAPY(8);                 // 8% APY
//         oracle.setTotalStakedXFI(0);             // Start with 0 staked
//         oracle.setUnbondingPeriod(21 days);      // 21 days unbonding
//         oracle.setPrice("XFI", 1 ether);         // $1 fallback price
        
//         // Set launch timestamp to current time
//         oracle.setLaunchTimestamp(block.timestamp);
        
//         console.log("Initial oracle settings configured");
//     }
// }

// /**
//  * @dev Minimal mock implementation of DIA Oracle for testing deployments
//  */
// contract MockDIAOracle {
//     mapping(string => uint128) private prices;
//     mapping(string => uint128) private timestamps;
    
//     event PriceSet(string key, uint128 price);
    
//     function getValue(string memory key) external view returns (uint128 price, uint128 timestamp) {
//         return (prices[key], timestamps[key]);
//     }
    
//     function setPrice(string memory key, uint128 value) external {
//         prices[key] = value;
//         timestamps[key] = uint128(block.timestamp);
//         emit PriceSet(key, value);
//     }
// } 