// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.26;

// import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
// import "../core/NativeStaking.sol";
// import "../core/NativeStakingVault.sol";
// import "../core/NativeStakingManager.sol";
// import "../periphery/CrossFiOracle.sol";
// import "../periphery/WXFI.sol";
// import "../interfaces/INativeStakingManager.sol";

// /**
//  * @title DeploymentCoordinator
//  * @dev Centralizes the deployment logic for the Native Staking system
//  * Uses TransparentUpgradeableProxy pattern to make contracts upgradeable
//  * Note: This contract is not deployed, only used in the deployment script
//  */
// contract DeploymentCoordinator {
//     // Deployed contract addresses
//     address public wxfi;
//     address public oracleProxy;
//     address public nativeStakingProxy;
//     address public nativeStakingVaultProxy;
//     address payable public nativeStakingManagerProxy;
    
//     // ProxyAdmin
//     address public proxyAdmin;
    
//     /**
//      * @dev Deploys the entire Native Staking system with proper proxies
//      * @param adminAddress The address that will be the admin of the system
//      * @return The address of the NativeStakingManager proxy (the main entry point)
//      */
//     function deploySystem(address adminAddress) external returns (address) {
//         require(adminAddress != address(0), "Invalid admin address");
        
//         // Step 1: Deploy ProxyAdmin
//         ProxyAdmin admin = new ProxyAdmin(adminAddress);
//         proxyAdmin = address(admin);
//         admin.transferOwnership(adminAddress);
        
//         // Step 2: Deploy WXFI (not upgradeable)
//         WXFI wxfiContract = new WXFI();
//         wxfi = address(wxfiContract);
        
//         // Step 3: Deploy Oracle with proxy
//         CrossFiOracle oracleImpl = new CrossFiOracle();
//         bytes memory oracleInitData = abi.encodeWithSelector(
//             CrossFiOracle.initialize.selector
//         );
        
//         TransparentUpgradeableProxy oracleProxyContract = new TransparentUpgradeableProxy(
//             address(oracleImpl),
//             proxyAdmin,
//             oracleInitData
//         );
//         oracleProxy = address(oracleProxyContract);
        
//         // Step 4: Deploy NativeStaking (APR) with proxy
//         NativeStaking nativeStakingImpl = new NativeStaking();
//         bytes memory nativeStakingInitData = abi.encodeWithSelector(
//             NativeStaking.initialize.selector,
//             wxfi,
//             oracleProxy
//         );
        
//         TransparentUpgradeableProxy nativeStakingProxyContract = new TransparentUpgradeableProxy(
//             address(nativeStakingImpl),
//             proxyAdmin,
//             nativeStakingInitData
//         );
//         nativeStakingProxy = address(nativeStakingProxyContract);
        
//         // Step 5: Deploy NativeStakingVault (APY) with proxy
//         NativeStakingVault nativeStakingVaultImpl = new NativeStakingVault();
//         bytes memory nativeStakingVaultInitData = abi.encodeWithSelector(
//             NativeStakingVault.initialize.selector,
//             wxfi,
//             oracleProxy,
//             "CrossFi Staking Share",
//             "xXFI"
//         );
        
//         TransparentUpgradeableProxy nativeStakingVaultProxyContract = new TransparentUpgradeableProxy(
//             address(nativeStakingVaultImpl),
//             proxyAdmin,
//             nativeStakingVaultInitData
//         );
//         nativeStakingVaultProxy = address(nativeStakingVaultProxyContract);
        
//         // Step 6: Deploy NativeStakingManager with proxy
//         NativeStakingManager nativeStakingManagerImpl = new NativeStakingManager();
//         bytes memory nativeStakingManagerInitData = abi.encodeWithSelector(
//             NativeStakingManager.initialize.selector,
//             nativeStakingProxy,
//             nativeStakingVaultProxy,
//             wxfi,
//             oracleProxy
//         );
        
//         TransparentUpgradeableProxy nativeStakingManagerProxyContract = new TransparentUpgradeableProxy(
//             address(nativeStakingManagerImpl),
//             proxyAdmin,
//             nativeStakingManagerInitData
//         );
//         nativeStakingManagerProxy = payable(address(nativeStakingManagerProxyContract));
        
//         // Step 7: Setup roles
//         setupRoles(adminAddress);
        
//         return nativeStakingManagerProxy;
//     }
    
//     /**
//      * @dev Sets up roles for the deployed contracts
//      * @param adminAddress The address that will have admin rights
//      */
//     function setupRoles(address adminAddress) private {
//         // Grant the STAKING_MANAGER_ROLE to the manager contract
//         NativeStaking aprContract = NativeStaking(nativeStakingProxy);
//         NativeStakingVault apyContract = NativeStakingVault(nativeStakingVaultProxy);
        
//         bytes32 stakingManagerRole = aprContract.STAKING_MANAGER_ROLE();
//         bytes32 adminRole = aprContract.DEFAULT_ADMIN_ROLE();
        
//         // Grant staking manager role to the manager contract
//         aprContract.grantRole(stakingManagerRole, nativeStakingManagerProxy);
//         apyContract.grantRole(stakingManagerRole, nativeStakingManagerProxy);
        
//         // Grant admin role to the provided admin address
//         aprContract.grantRole(adminRole, adminAddress);
//         apyContract.grantRole(adminRole, adminAddress);
//         CrossFiOracle(oracleProxy).grantRole(adminRole, adminAddress);
        
//         // Use interface to avoid payable fallback issues
//         INativeStakingManager manager = INativeStakingManager(nativeStakingManagerProxy);
//         // Cast to AccessControlUpgradeable to access the grantRole function
//         AccessControlUpgradeable(address(manager)).grantRole(adminRole, adminAddress);
        
//         // Revoke admin role from this contract
//         aprContract.renounceRole(adminRole, address(this));
//         apyContract.renounceRole(adminRole, address(this));
//         CrossFiOracle(oracleProxy).renounceRole(adminRole, address(this));
//         AccessControlUpgradeable(address(manager)).renounceRole(adminRole, address(this));
//     }
// } 