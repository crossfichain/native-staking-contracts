// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../../src/core/NativeStaking.sol";
import "../../src/core/NativeStakingVault.sol";
import "../../src/core/NativeStakingManager.sol";
import "../../src/periphery/UnifiedOracle.sol";
import "../../src/periphery/WXFI.sol";
import "../../src/interfaces/INativeStakingManager.sol";
import "../../src/interfaces/IDIAOracle.sol";

/**
 * @title DeploymentScript
 * @dev Forge script for deploying the Native Staking system using proxies
 */
contract DeploymentScript is Script {
    // Deployed contract addresses
    address public wxfi;
    address public oracleProxy;
    address public nativeStakingProxy;
    address public nativeStakingVaultProxy;
    address payable public nativeStakingManagerProxy;
    address public diaOracle;
    
    // ProxyAdmin
    address public proxyAdmin;
    
    function run() external {
        // Get deployer private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer address:", deployer);
        
        // Get DIA Oracle address from environment or use a default for testing
        address diaOracleAddress;
        try vm.envAddress("DIA_ORACLE_ADDRESS") returns (address dia) {
            diaOracleAddress = dia;
        } catch {
            revert("DIA_ORACLE_ADDRESS environment variable not set");
        }
        
        console.log("DIA Oracle address:", diaOracleAddress);
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the full system
        deploySystem(deployer, diaOracleAddress);
        
        // Stop broadcasting
        vm.stopBroadcast();
        
        // Log deployed addresses
        console.log("Deployment completed successfully!");
        console.log("WXFI deployed at:", wxfi);
        console.log("Oracle Proxy deployed at:", oracleProxy);
        console.log("NativeStaking Proxy deployed at:", nativeStakingProxy);
        console.log("NativeStakingVault Proxy deployed at:", nativeStakingVaultProxy);
        console.log("NativeStakingManager Proxy deployed at:", nativeStakingManagerProxy);
        console.log("ProxyAdmin deployed at:", proxyAdmin);
    }
    
    /**
     * @dev Deploys the entire Native Staking system with proper proxies
     * @param adminAddress The address that will be the admin of the system
     * @param diaOracleAddress The address of the DIA Oracle contract for price data
     */
    function deploySystem(address adminAddress, address diaOracleAddress) internal {
        require(adminAddress != address(0), "Invalid admin address");
        require(diaOracleAddress != address(0), "Invalid DIA Oracle address");
        
        diaOracle = diaOracleAddress;
        
        // Step 1: Deploy ProxyAdmin
        ProxyAdmin admin = new ProxyAdmin(adminAddress);
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
        NativeStakingManager nativeStakingManagerImpl = new NativeStakingManager();
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
    }
    
    /**
     * @dev Sets up roles for the deployed contracts
     * @param adminAddress The address that will have admin rights
     */
    function setupRoles(address adminAddress) internal {
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