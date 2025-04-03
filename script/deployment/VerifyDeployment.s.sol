// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// import {Script, console} from "forge-std/Script.sol";
// import "../../src/periphery/UnifiedOracle.sol";
// import "../../src/core/NativeStaking.sol";
// import "../../src/core/NativeStakingVault.sol";
// import "../../src/core/NativeStakingManager.sol";
// import "../../src/periphery/WXFI.sol";
// import "../../src/interfaces/IDIAOracle.sol";
// import "../../src/interfaces/IOracle.sol";

// /**
//  * @title VerifyDeployment
//  * @dev Script for verifying the deployed Native Staking system
//  * This performs a series of read-only checks to ensure the system is correctly set up
//  */
// contract VerifyDeployment is Script {
//     // Deployment addresses
//     address public wxfi;
//     address public oracleProxy;
//     address public aprStakingProxy;
//     address public apyStakingProxy;
//     address public stakingManagerProxy;
//     address public proxyAdmin;
//     address public diaOracleAddress;
//     address public adminAddress;
    
//     // Contract instances
//     WXFI public wxfiContract;
//     UnifiedOracle public oracle;
//     NativeStaking public aprStaking;
//     NativeStakingVault public apyStaking;
//     NativeStakingManager public stakingManager;
    
//     function run() public {
//         // Load addresses from environment variables or deployment file
//         loadAddresses();
        
//         // Initialize contract instances
//         wxfiContract = WXFI(wxfi);
//         oracle = UnifiedOracle(oracleProxy);
//         aprStaking = NativeStaking(payable(aprStakingProxy));
//         apyStaking = NativeStakingVault(apyStakingProxy);
//         stakingManager = NativeStakingManager(payable(stakingManagerProxy));
        
//         // Verify system configuration
//         verifyContracts();
//         verifyRoles();
//         verifyOracleSettings();
        
//         console.log("\nDeployment verification completed successfully!");
//     }
    
//     function loadAddresses() internal {
//         // Try to load from environment variables
//         if (vm.envExists("WXFI_ADDRESS")) {
//             wxfi = vm.envAddress("WXFI_ADDRESS");
//             oracleProxy = vm.envAddress("ORACLE_PROXY_ADDRESS");
//             aprStakingProxy = vm.envAddress("APR_STAKING_PROXY_ADDRESS");
//             apyStakingProxy = vm.envAddress("APY_STAKING_PROXY_ADDRESS");
//             stakingManagerProxy = vm.envAddress("STAKING_MANAGER_PROXY_ADDRESS");
//             proxyAdmin = vm.envAddress("PROXY_ADMIN_ADDRESS");
//             diaOracleAddress = vm.envAddress("DIA_ORACLE_ADDRESS");
//             adminAddress = vm.envAddress("ADMIN_ADDRESS");
//         } 
//         // Alternatively, try to load from a deployment file
//         else {
//             string memory deploymentFile = string.concat("deployments/", vm.toString(block.chainid), "-deployment.csv");
//             string memory deploymentData = vm.readFile(deploymentFile);
//             string[] memory values = split(deploymentData, ",");
            
//             require(values.length >= 8, "Invalid deployment data");
            
//             // First value is chain id, skip it
//             wxfi = vm.parseAddress(values[1]);
//             oracleProxy = vm.parseAddress(values[2]);
//             aprStakingProxy = vm.parseAddress(values[3]);
//             apyStakingProxy = vm.parseAddress(values[4]);
//             stakingManagerProxy = vm.parseAddress(values[5]);
//             proxyAdmin = vm.parseAddress(values[6]);
//             diaOracleAddress = vm.parseAddress(values[7]);
            
//             // Admin is not stored in the file, try to get it from env
//             if (vm.envExists("ADMIN_ADDRESS")) {
//                 adminAddress = vm.envAddress("ADMIN_ADDRESS");
//             }
//         }
        
//         console.log("\n==== Loaded Contract Addresses ====");
//         console.log("WXFI:", wxfi);
//         console.log("Oracle Proxy:", oracleProxy);
//         console.log("APR Staking Proxy:", aprStakingProxy);
//         console.log("APY Staking Proxy:", apyStakingProxy);
//         console.log("Staking Manager Proxy:", stakingManagerProxy);
//         console.log("Proxy Admin:", proxyAdmin);
//         console.log("DIA Oracle:", diaOracleAddress);
//         console.log("Admin Address:", adminAddress);
//         console.log("==================================\n");
//     }
    
//     function verifyContracts() internal {
//         console.log("\n==== Verifying Contract Connections ====");
        
//         // Verify WXFI
//         string memory wxfiName = wxfiContract.name();
//         string memory wxfiSymbol = wxfiContract.symbol();
//         console.log("WXFI Name:", wxfiName);
//         console.log("WXFI Symbol:", wxfiSymbol);
//         require(
//             keccak256(bytes(wxfiName)) == keccak256(bytes("Wrapped XFI")) &&
//             keccak256(bytes(wxfiSymbol)) == keccak256(bytes("WXFI")),
//             "WXFI contract verification failed"
//         );
        
//         // Verify Oracle
//         address diaOracle = address(oracle.diaOracle());
//         console.log("DIA Oracle in UnifiedOracle:", diaOracle);
//         require(diaOracle == diaOracleAddress, "DIA Oracle address mismatch");
        
//         // Verify APR staking references
//         address aprOracleAddr = address(aprStaking.oracle());
//         address aprTokenAddr = address(aprStaking.stakingToken());
//         console.log("APR Staking Oracle:", aprOracleAddr);
//         console.log("APR Staking Token:", aprTokenAddr);
//         require(aprOracleAddr == oracleProxy, "APR Staking Oracle address mismatch");
//         require(aprTokenAddr == wxfi, "APR Staking Token address mismatch");
        
//         // Verify APY staking references
//         address apyOracleAddr = address(apyStaking.oracle());
//         address apyAssetAddr = address(apyStaking.asset());
//         console.log("APY Staking Oracle:", apyOracleAddr);
//         console.log("APY Staking Asset:", apyAssetAddr);
//         require(apyOracleAddr == oracleProxy, "APY Staking Oracle address mismatch");
//         require(apyAssetAddr == wxfi, "APY Staking Asset address mismatch");
        
//         // Verify Manager references
//         address managerAprAddr = address(stakingManager.getAPRContract());
//         address managerApyAddr = address(stakingManager.getAPYContract());
//         address managerTokenAddr = address(stakingManager.getXFIToken());
//         address managerOracleAddr = address(stakingManager.oracle());
//         console.log("Manager APR Contract:", managerAprAddr);
//         console.log("Manager APY Contract:", managerApyAddr);
//         console.log("Manager XFI Token:", managerTokenAddr);
//         console.log("Manager Oracle:", managerOracleAddr);
//         require(managerAprAddr == aprStakingProxy, "Manager APR Contract address mismatch");
//         require(managerApyAddr == apyStakingProxy, "Manager APY Contract address mismatch");
//         require(managerTokenAddr == wxfi, "Manager XFI Token address mismatch");
//         require(managerOracleAddr == oracleProxy, "Manager Oracle address mismatch");
        
//         console.log("All contract connections verified!");
//     }
    
//     function verifyRoles() internal {
//         console.log("\n==== Verifying Role Assignments ====");
        
//         bytes32 adminRole = 0x00;
//         bytes32 stakingManagerRole = keccak256("STAKING_MANAGER_ROLE");
//         bytes32 oracleUpdaterRole = keccak256("ORACLE_UPDATER_ROLE");
//         bytes32 fulfillerRole = keccak256("FULFILLER_ROLE");
        
//         // Verify admin roles
//         bool hasAdminRoleInOracle = oracle.hasRole(adminRole, adminAddress);
//         bool hasAdminRoleInApr = aprStaking.hasRole(adminRole, adminAddress);
//         bool hasAdminRoleInApy = apyStaking.hasRole(adminRole, adminAddress);
//         bool hasAdminRoleInManager = stakingManager.hasRole(adminRole, adminAddress);
        
//         console.log("Admin has admin role in Oracle:", hasAdminRoleInOracle);
//         console.log("Admin has admin role in APR Staking:", hasAdminRoleInApr);
//         console.log("Admin has admin role in APY Staking:", hasAdminRoleInApy);
//         console.log("Admin has admin role in Manager:", hasAdminRoleInManager);
        
//         require(hasAdminRoleInOracle, "Admin missing admin role in Oracle");
//         require(hasAdminRoleInApr, "Admin missing admin role in APR Staking");
//         require(hasAdminRoleInApy, "Admin missing admin role in APY Staking");
//         require(hasAdminRoleInManager, "Admin missing admin role in Manager");
        
//         // Verify manager roles
//         bool hasManagerRoleInApr = aprStaking.hasRole(stakingManagerRole, stakingManagerProxy);
//         bool hasManagerRoleInApy = apyStaking.hasRole(stakingManagerRole, stakingManagerProxy);
//         bool hasOracleUpdaterInOracle = oracle.hasRole(oracleUpdaterRole, stakingManagerProxy);
//         bool adminHasOracleUpdater = oracle.hasRole(oracleUpdaterRole, adminAddress);
//         bool adminHasFulfiller = stakingManager.hasRole(fulfillerRole, adminAddress);
        
//         console.log("Manager has staking manager role in APR:", hasManagerRoleInApr);
//         console.log("Manager has staking manager role in APY:", hasManagerRoleInApy);
//         console.log("Manager has oracle updater role:", hasOracleUpdaterInOracle);
//         console.log("Admin has oracle updater role:", adminHasOracleUpdater);
//         console.log("Admin has fulfiller role:", adminHasFulfiller);
        
//         require(hasManagerRoleInApr, "Manager missing staking manager role in APR");
//         require(hasManagerRoleInApy, "Manager missing staking manager role in APY");
//         require(hasOracleUpdaterInOracle, "Manager missing oracle updater role");
//         require(adminHasOracleUpdater, "Admin missing oracle updater role");
//         require(adminHasFulfiller, "Admin missing fulfiller role");
        
//         console.log("All role assignments verified!");
//     }
    
//     function verifyOracleSettings() internal {
//         console.log("\n==== Verifying Oracle Settings ====");
        
//         // Check Oracle settings
//         uint256 xfiPrice = oracle.getPrice("XFI");
//         (uint256 xfiOraclePrice, uint256 timestamp) = oracle.getXFIPrice();
//         uint256 apr = oracle.getCurrentAPR();
//         uint256 apy = oracle.getCurrentAPY();
//         uint256 unbondingPeriod = oracle.getUnbondingPeriod();
//         uint256 totalStaked = oracle.getTotalStakedXFI();
//         uint256 launchTimestamp = stakingManager.getLaunchTimestamp();
        
//         console.log("XFI Price:", xfiPrice);
//         console.log("XFI Oracle Price:", xfiOraclePrice);
//         console.log("XFI Price Timestamp:", timestamp);
//         console.log("Current APR:", apr);
//         console.log("Current APY:", apy);
//         console.log("Unbonding Period:", unbondingPeriod / 1 days, "days");
//         console.log("Total Staked XFI:", totalStaked);
//         console.log("Launch Timestamp:", launchTimestamp);
//         console.log("Current Timestamp:", block.timestamp);
//         console.log("Unstaking Frozen:", stakingManager.isUnstakingFrozen());
        
//         // Verify some key settings
//         require(xfiPrice > 0, "XFI price is zero");
//         require(xfiOraclePrice > 0, "XFI oracle price is zero");
//         require(apr > 0, "APR is zero");
//         require(apy > 0, "APY is zero");
//         require(unbondingPeriod > 0, "Unbonding period is zero");
//         require(launchTimestamp > 0, "Launch timestamp is zero");
        
//         console.log("Oracle settings verified!");
//     }
    
//     // Helper function to split a string
//     function split(string memory _base, string memory _delimiter) internal pure returns (string[] memory) {
//         bytes memory base = bytes(_base);
//         uint256 count = 1;
        
//         // Count the number of delimiters
//         for(uint i = 0; i < base.length; i++) {
//             if(base[i] == bytes(_delimiter)[0]) {
//                 count++;
//             }
//         }
        
//         // Create the array
//         string[] memory parts = new string[](count);
        
//         // Split the string
//         count = 0;
//         string memory part;
//         for(uint i = 0; i < base.length; i++) {
//             if(base[i] != bytes(_delimiter)[0]) {
//                 part = string.concat(part, string(abi.encodePacked(base[i])));
//             } else {
//                 parts[count] = part;
//                 part = "";
//                 count++;
//             }
//         }
        
//         // Add the last part
//         parts[count] = part;
        
//         return parts;
//     }
// } 