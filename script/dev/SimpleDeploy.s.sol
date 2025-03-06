// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import "../../src/periphery/UnifiedOracle.sol";
import "../../src/core/NativeStaking.sol";
import "../../src/core/NativeStakingVault.sol";
import "../../src/core/NativeStakingManager.sol";
import "../../src/periphery/WXFI.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title SimpleDeploy
 * @dev All-in-one script for deploying the Native Staking system for development
 * 
 * Run with:
 * forge script script/dev/SimpleDeploy.s.sol:SimpleDeploy --rpc-url <RPC_URL> --broadcast -vvv
 */
contract SimpleDeploy is Script {
    // -------------------------------------------------------------------
    // EDIT THESE VALUES BEFORE RUNNING
    // -------------------------------------------------------------------
    
    // Role addresses
    address public constant ADMIN = address(0xee2e617a42Aab5be36c290982493C6CC6C072982);       // Admin address for managing system
    address public constant OPERATOR = address(0x79F9860d48ef9dDFaF3571281c033664de05E6f5);    // Operator for daily tasks
    address public constant TREASURY = address(0xee2e617a42Aab5be36c290982493C6CC6C072982);    // Treasury for fees
    address public constant EMERGENCY = address(0xee2e617a42Aab5be36c290982493C6CC6C072982);   // Emergency pause/recovery
    
    // Initial configuration
    uint256 public constant INITIAL_APR = 10 ether;     // 10% APR (with 18 decimals)
    uint256 public constant INITIAL_APY = 8 ether;      // 8% APY (with 18 decimals)
    uint256 public constant UNBONDING_PERIOD = 21 days; // 21 days (in seconds)
    uint256 public constant XFI_PRICE = 1 ether;        // $1 per XFI (with 18 decimals)
    
    // -------------------------------------------------------------------
    // END EDITABLE SECTION
    // -------------------------------------------------------------------
    
    // Deployed contract addresses
    address public mockDiaOracle;
    address public wxfi;
    address public oracleProxy;
    address public aprStakingProxy;
    address public apyStakingProxy;
    address payable public stakingManagerProxy;
    address public proxyAdmin;
    
    // Role constants
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    bytes32 public constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
    bytes32 public constant COMPOUNDER_ROLE = keccak256("COMPOUNDER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    function run() public {
        // Get the private key for deployment
        uint256 deployerPrivateKey;
        if (vm.envExists("DEV_PRIVATE_KEY")) {
            deployerPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
        } else {
            // Default anvil private key if not specified
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        }
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("\n==== CrossFi Native Staking Development Deployment ====");
        console.log("Deployer:  ", deployer);
        console.log("Admin:     ", ADMIN);
        console.log("Operator:  ", OPERATOR);
        console.log("Treasury:  ", TREASURY);
        console.log("Emergency: ", EMERGENCY);
        
        // Create deployments directory if it doesn't exist
        try vm.createDir("deployments", false) {} catch {}
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy Mock DIA Oracle
        deployMockDIAOracle();
        
        // 2. Deploy WXFI
        deployWXFI();
        
        // 3. Deploy the core system - directly, not via the coordinator
        deployMainSystemDirect();
        
        // 4. Configure settings
        configureSystem();
        
        vm.stopBroadcast();
        
        // Display final summary
        printResults();
        // saveAddressesToFile();
    }
    
    function deployMockDIAOracle() internal {
        console.log("\n==== Deploying Mock DIA Oracle ====");
        
        // Simple mock DIA Oracle
        MockDIAOracle mockDiaOracleContract = new MockDIAOracle();
        mockDiaOracle = address(mockDiaOracleContract);
        
        // Set initial XFI price to $1
        mockDiaOracleContract.setPrice("XFI/USD", 1e8); // $1 with 8 decimals
        
        console.log("Mock DIA Oracle deployed at:", mockDiaOracle);
    }
    
    function deployWXFI() internal {
        console.log("\n==== Deploying WXFI ====");
        
        // Deploy WXFI
        WXFI wxfiContract = new WXFI();
        wxfi = address(wxfiContract);
        
        console.log("WXFI deployed at:", wxfi);
    }
    
    function deployMainSystemDirect() internal {
        console.log("\n==== Deploying Main System Directly ====");
        
        // Step 1: Deploy ProxyAdmin
        ProxyAdmin admin = new ProxyAdmin(ADMIN);
        proxyAdmin = address(admin);
        console.log("Proxy Admin deployed at:", proxyAdmin);
        
        // Step 2: Deploy Oracle with proxy
        UnifiedOracle oracleImpl = new UnifiedOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            UnifiedOracle.initialize.selector,
            mockDiaOracle
        );
        
        TransparentUpgradeableProxy oracleProxyContract = new TransparentUpgradeableProxy(
            address(oracleImpl),
            proxyAdmin,
            oracleInitData
        );
        oracleProxy = address(oracleProxyContract);
        console.log("Oracle Proxy deployed at:", oracleProxy);
        
        // Step 3: Deploy NativeStaking (APR) with proxy
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
        aprStakingProxy = address(nativeStakingProxyContract);
        console.log("APR Staking Proxy deployed at:", aprStakingProxy);
        
        // Step 4: Deploy NativeStakingVault (APY) with proxy
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
        apyStakingProxy = address(nativeStakingVaultProxyContract);
        console.log("APY Staking Proxy deployed at:", apyStakingProxy);
        
        // Step 5: Deploy NativeStakingManager with proxy
        NativeStakingManager nativeStakingManagerImpl = new NativeStakingManager();
        bytes memory nativeStakingManagerInitData = abi.encodeWithSelector(
            NativeStakingManager.initialize.selector,
            aprStakingProxy,
            apyStakingProxy,
            wxfi,
            oracleProxy
        );
        
        TransparentUpgradeableProxy nativeStakingManagerProxyContract = new TransparentUpgradeableProxy(
            address(nativeStakingManagerImpl),
            proxyAdmin,
            nativeStakingManagerInitData
        );
        stakingManagerProxy = payable(address(nativeStakingManagerProxyContract));
        console.log("Staking Manager Proxy deployed at:", stakingManagerProxy);
        
        console.log("Main system deployed successfully.");
    }
    
    function configureSystem() internal {
        console.log("\n==== Configuring System ====");
        
        // Get contract instances
        UnifiedOracle oracle = UnifiedOracle(oracleProxy);
        NativeStaking aprStaking = NativeStaking(aprStakingProxy);
        NativeStakingVault apyStaking = NativeStakingVault(apyStakingProxy);
        NativeStakingManager stakingManager = NativeStakingManager(payable(stakingManagerProxy));
        
        // 1. Configure Oracle settings
        console.log("Setting Oracle parameters...");
        oracle.setCurrentAPR(INITIAL_APR);
        oracle.setCurrentAPY(INITIAL_APY);
        oracle.setUnbondingPeriod(UNBONDING_PERIOD);
        oracle.setPrice("XFI", XFI_PRICE);
        oracle.setTotalStakedXFI(0);
        oracle.setLaunchTimestamp(block.timestamp);
        
        // 2. Setup operator roles
        console.log("Setting up roles...");
        
        // Make sure Admin has admin role in all contracts
        oracle.grantRole(DEFAULT_ADMIN_ROLE, ADMIN);
        aprStaking.grantRole(DEFAULT_ADMIN_ROLE, ADMIN);
        apyStaking.grantRole(DEFAULT_ADMIN_ROLE, ADMIN);
        stakingManager.grantRole(DEFAULT_ADMIN_ROLE, ADMIN);
        
        // Oracle roles
        oracle.grantRole(ORACLE_UPDATER_ROLE, OPERATOR);
        oracle.grantRole(ORACLE_UPDATER_ROLE, ADMIN);
        oracle.grantRole(PAUSER_ROLE, OPERATOR);
        oracle.grantRole(PAUSER_ROLE, ADMIN);
        oracle.grantRole(PAUSER_ROLE, EMERGENCY);
        
        // Emergency roles
        aprStaking.grantRole(EMERGENCY_ROLE, EMERGENCY);
        aprStaking.grantRole(EMERGENCY_ROLE, ADMIN);
        aprStaking.grantRole(EMERGENCY_ROLE, OPERATOR);
        apyStaking.grantRole(EMERGENCY_ROLE, EMERGENCY);
        apyStaking.grantRole(EMERGENCY_ROLE, ADMIN);
        apyStaking.grantRole(EMERGENCY_ROLE, OPERATOR);
        
        // Staking manager role
        aprStaking.grantRole(STAKING_MANAGER_ROLE, stakingManagerProxy);
        aprStaking.grantRole(STAKING_MANAGER_ROLE, OPERATOR);
        apyStaking.grantRole(STAKING_MANAGER_ROLE, stakingManagerProxy);
        apyStaking.grantRole(STAKING_MANAGER_ROLE, OPERATOR);
        
        // Operator needs fulfiller role
        stakingManager.grantRole(FULFILLER_ROLE, OPERATOR);
        stakingManager.grantRole(FULFILLER_ROLE, ADMIN);
        
        // Operator needs compounder role for APY Staking
        apyStaking.grantRole(COMPOUNDER_ROLE, OPERATOR);
        apyStaking.grantRole(COMPOUNDER_ROLE, ADMIN);
        
        // Oracle updater role for manager so it can update rewards
        oracle.grantRole(ORACLE_UPDATER_ROLE, stakingManagerProxy);
        
        console.log("System configured successfully.");
    }
    
    function printResults() internal view {
        console.log("\n==== Deployment Results ====");
        console.log("Mock DIA Oracle:       ", mockDiaOracle);
        console.log("WXFI:                  ", wxfi);
        console.log("Oracle:                ", oracleProxy);
        console.log("APR Staking:           ", aprStakingProxy);
        console.log("APY Staking:           ", apyStakingProxy);
        console.log("Staking Manager:       ", stakingManagerProxy);
        console.log("Proxy Admin:           ", proxyAdmin);
        
        console.log("\n==== Test Account Addresses ====");
        console.log("Admin:                 ", ADMIN);
        console.log("Operator:              ", OPERATOR);
        console.log("Treasury:              ", TREASURY);
        console.log("Emergency:             ", EMERGENCY);
        
        console.log("\n==== Fund test accounts ====");
        console.log("Run these commands to fund your test accounts:");
        console.log(string.concat("cast send --value 1ether ", vm.toString(ADMIN), " --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"));
        console.log(string.concat("cast send --value 1ether ", vm.toString(OPERATOR), " --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"));
        console.log(string.concat("cast send --value 1ether ", vm.toString(TREASURY), " --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"));
        console.log(string.concat("cast send --value 1ether ", vm.toString(EMERGENCY), " --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"));
    }
    
    function saveAddressesToFile() internal {
        console.log("\n==== Saving Addresses ====");
        
        // Format: contracts,wxfi,mockDiaOracle,oracleProxy,aprStakingProxy,apyStakingProxy,stakingManagerProxy,proxyAdmin
        string memory deploymentInfo = string.concat(
            "contract,",
            vm.toString(wxfi), ",",
            vm.toString(mockDiaOracle), ",",
            vm.toString(oracleProxy), ",",
            vm.toString(aprStakingProxy), ",",
            vm.toString(apyStakingProxy), ",",
            vm.toString(stakingManagerProxy), ",",
            vm.toString(proxyAdmin)
        );
        
        vm.writeFile("deployments/dev-contracts.csv", deploymentInfo);
        console.log("Contract addresses saved to deployments/dev-contracts.csv");
        
        // Save to environment file for easier loading
        string memory envContent = string.concat(
            "# Generated by SimpleDeploy.s.sol - ", vm.toString(block.timestamp), "\n",
            "WXFI_ADDRESS=", vm.toString(wxfi), "\n",
            "DIA_ORACLE_ADDRESS=", vm.toString(mockDiaOracle), "\n",
            "ORACLE_PROXY_ADDRESS=", vm.toString(oracleProxy), "\n",
            "APR_STAKING_PROXY_ADDRESS=", vm.toString(aprStakingProxy), "\n",
            "APY_STAKING_PROXY_ADDRESS=", vm.toString(apyStakingProxy), "\n",
            "STAKING_MANAGER_PROXY_ADDRESS=", vm.toString(stakingManagerProxy), "\n",
            "PROXY_ADMIN_ADDRESS=", vm.toString(proxyAdmin), "\n",
            "\n",
            "ADMIN_ADDRESS=", vm.toString(ADMIN), "\n",
            "OPERATOR_ADDRESS=", vm.toString(OPERATOR), "\n",
            "TREASURY_ADDRESS=", vm.toString(TREASURY), "\n", 
            "EMERGENCY_ADDRESS=", vm.toString(EMERGENCY), "\n"
        );
        
        vm.writeFile("deployments/dev.env", envContent);
        console.log("Environment variables saved to deployments/dev.env");
        console.log("You can load them with: source deployments/dev.env");
    }
}

/**
 * @dev Minimal mock DIA Oracle implementation for development
 */
contract MockDIAOracle {
    mapping(string => uint128) private prices;
    mapping(string => uint128) private timestamps;
    
    event PriceSet(string key, uint128 price);
    
    function getValue(string memory key) external view returns (uint128 price, uint128 timestamp) {
        return (prices[key], timestamps[key]);
    }
    
    function setPrice(string memory key, uint128 value) external {
        prices[key] = value;
        timestamps[key] = uint128(block.timestamp);
        emit PriceSet(key, value);
    }
} 