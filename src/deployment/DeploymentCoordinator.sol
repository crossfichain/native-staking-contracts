// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../core/NativeStaking.sol";
import "../core/NativeStakingVault.sol";
import "../core/ConcreteNativeStakingManager.sol";
import "../periphery/UnifiedOracle.sol";
import "../periphery/WXFI.sol";
import "../interfaces/INativeStakingManager.sol";
import "../interfaces/IDIAOracle.sol";

/**
 * @title DeploymentCoordinator
 * @dev Centralizes the deployment logic for the Native Staking system
 * Uses TransparentUpgradeableProxy pattern to make contracts upgradeable
 * Note: This contract is not deployed, only used in the deployment script
 */
contract DeploymentCoordinator {
    // Deployed contract addresses
    address public wxfi;
    address public oracleProxy;
    address public nativeStakingProxy;
    address public nativeStakingVaultProxy;
    address payable public nativeStakingManagerProxy;
    address public diaOracle;
    
    // ProxyAdmin
    address public proxyAdmin;
    
    /**
     * @dev Deploys the entire Native Staking system with proper proxies
     * @param adminAddress The address that will be the admin of the system
     * @param diaOracleAddress The address of the DIA Oracle contract for price data
     * @return The address of the NativeStakingManager proxy (the main entry point)
     */
    function deploySystem(address adminAddress, address diaOracleAddress) external returns (address) {
        require(adminAddress != address(0), "Invalid admin address");
        require(diaOracleAddress != address(0), "Invalid DIA Oracle address");
        
        diaOracle = diaOracleAddress;
        
        // Step 1: Deploy ProxyAdmin
        ProxyAdmin admin = new ProxyAdmin();
        proxyAdmin = address(admin);
        admin.transferOwnership(adminAddress);
        
        // Step 2: Deploy WXFI (not upgradeable)
        WXFI wxfiContract = new WXFI();
        wxfi = address(wxfiContract);
        
        // Step 3: Deploy Oracle with proxy
        UnifiedOracle oracleImpl = new UnifiedOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            UnifiedOracle.initialize.selector,
            diaOracleAddress
        );
        
        TransparentUpgradeableProxy oracleProxyContract = new TransparentUpgradeableProxy(
            address(oracleImpl),
            proxyAdmin,
            oracleInitData
        );
        oracleProxy = address(oracleProxyContract);
        
        // Step 4: Deploy NativeStaking (APR) with proxy
        NativeStaking nativeStakingImpl = new NativeStaking();
        bytes memory nativeStakingInitData = abi.encodeWithSelector(
            NativeStaking.initialize.selector,
            wxfi,
            oracleProxy
        );
        
        TransparentUpgradeableProxy nativeStakingProxyContract = new TransparentUpgradeableProxy(
            address(nativeStakingImpl),
            proxyAdmin,
            nativeStakingInitData
        );
        nativeStakingProxy = address(nativeStakingProxyContract);
        
        // Step 5: Deploy NativeStakingVault (APY) with proxy
        NativeStakingVault nativeStakingVaultImpl = new NativeStakingVault();
        bytes memory nativeStakingVaultInitData = abi.encodeWithSelector(
            NativeStakingVault.initialize.selector,
            wxfi,
            oracleProxy,
            "CrossFi Staking Share",
            "xXFI"
        );
        
        TransparentUpgradeableProxy nativeStakingVaultProxyContract = new TransparentUpgradeableProxy(
            address(nativeStakingVaultImpl),
            proxyAdmin,
            nativeStakingVaultInitData
        );
        nativeStakingVaultProxy = address(nativeStakingVaultProxyContract);
        
        // Step 6: Deploy NativeStakingManager with proxy
        ConcreteNativeStakingManager nativeStakingManagerImpl = new ConcreteNativeStakingManager();
        bytes memory nativeStakingManagerInitData = abi.encodeWithSelector(
            NativeStakingManager.initialize.selector,
            nativeStakingProxy,
            nativeStakingVaultProxy,
            wxfi,
            oracleProxy
        );
        
        TransparentUpgradeableProxy nativeStakingManagerProxyContract = new TransparentUpgradeableProxy(
            address(nativeStakingManagerImpl),
            proxyAdmin,
            nativeStakingManagerInitData
        );
        nativeStakingManagerProxy = payable(address(nativeStakingManagerProxyContract));
        
        // Step 7: Setup roles
        setupRoles(adminAddress);
        
        return nativeStakingManagerProxy;
    }
    
    /**
     * @dev Sets up roles for the deployed contracts
     * @param adminAddress The address that will have admin rights
     */
    function setupRoles(address adminAddress) private {
        // Grant the STAKING_MANAGER_ROLE to the manager contract
        NativeStaking aprContract = NativeStaking(nativeStakingProxy);
        NativeStakingVault apyContract = NativeStakingVault(nativeStakingVaultProxy);
        UnifiedOracle oracle = UnifiedOracle(oracleProxy);
        
        bytes32 stakingManagerRole = aprContract.STAKING_MANAGER_ROLE();
        bytes32 adminRole = aprContract.DEFAULT_ADMIN_ROLE();
        bytes32 oracleUpdaterRole = oracle.ORACLE_UPDATER_ROLE();
        
        // Grant staking manager role to the manager contract
        aprContract.grantRole(stakingManagerRole, nativeStakingManagerProxy);
        apyContract.grantRole(stakingManagerRole, nativeStakingManagerProxy);
        
        // Grant oracle updater role to necessary contracts
        oracle.grantRole(oracleUpdaterRole, nativeStakingManagerProxy);
        oracle.grantRole(oracleUpdaterRole, adminAddress);
        
        // Grant admin role to the provided admin address
        aprContract.grantRole(adminRole, adminAddress);
        apyContract.grantRole(adminRole, adminAddress);
        oracle.grantRole(adminRole, adminAddress);
        
        // Use interface to avoid payable fallback issues
        INativeStakingManager manager = INativeStakingManager(nativeStakingManagerProxy);
        // Cast to AccessControlUpgradeable to access the grantRole function
        AccessControlUpgradeable(address(manager)).grantRole(adminRole, adminAddress);
        
        // Revoke admin role from this contract
        aprContract.renounceRole(adminRole, address(this));
        apyContract.renounceRole(adminRole, address(this));
        oracle.renounceRole(adminRole, address(this));
        AccessControlUpgradeable(address(manager)).renounceRole(adminRole, address(this));
    }
} 