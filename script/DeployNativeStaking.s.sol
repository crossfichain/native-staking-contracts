// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/NativeStaking.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/interfaces/IOracle.sol";
import "../src/interfaces/IDIAOracle.sol";
import "../src/periphery/UnifiedOracle.sol";

/**
 * @title DeployNativeStaking
 * @dev Deployment script for the NativeStaking contract
 */
contract DeployNativeStaking is Script {
    // Role addresses
    address constant ADMIN_ADDRESS = 0xee2e617a42Aab5be36c290982493C6CC6C072982;
    address constant MANAGER_ADDRESS = 0xc35e04979A78630F16e625902283720681f2932e;
    address constant OPERATOR_ADDRESS = 0x79F9860d48ef9dDFaF3571281c033664de05E6f5;
    
    // Role constants
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    
    // Default delay settings (can be overridden via CLI arguments)
    uint256 constant DEFAULT_MIN_STAKE_INTERVAL = 1 hours;
    uint256 constant DEFAULT_MIN_UNSTAKE_INTERVAL = 1 days;
    uint256 constant DEFAULT_MIN_CLAIM_INTERVAL = 12 hours;
    
    // Other parameters
    uint256 constant MINIMUM_STAKE_AMOUNT = 1 ether;
    
    function run() external {
        // Get delay settings from environment or use defaults
        uint256 minStakeInterval = 1 days;
        uint256 minUnstakeInterval = 1 days;
        uint256 minClaimInterval = 1 days;
        
        // Get deployer private key from environment
        uint256 deployerKey = vm.envUint("DEV_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        
        // Start broadcasting transactions with the deployer's private key
        vm.startBroadcast(deployerKey);
        
        // Deploy MockDIAOracle first
        MockDIAOracle mockDiaOracle = new MockDIAOracle();
        
        // Set initial XFI price in DIA Oracle (0.09 USD with 8 decimals)
        mockDiaOracle.setPrice("XFI/USD", 9_000_000); // $0.09 with 8 decimals
        
        // Deploy UnifiedOracle implementation
        UnifiedOracle unifiedOracle = new UnifiedOracle();
        
        // Initialize the UnifiedOracle with the MockDIAOracle address
        unifiedOracle.initialize(address(mockDiaOracle));
        
        // Set default MPX price in UnifiedOracle to $0.04 with 18 decimals
        unifiedOracle.setMPXPrice(4 * 10**16); // $0.04 with 18 decimals
        
        // Set fallback price for XFI as well
        unifiedOracle.setPrice("XFI", 9 * 10**16); // $0.09 with 18 decimals
        
        // Deploy NativeStaking implementation
        NativeStaking stakingImplementation = new NativeStaking();
        
        // Deploy ProxyAdmin (for transparent proxy control)
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        
        // Prepare initialization data
        bytes memory initializeData = abi.encodeWithSelector(
            NativeStaking.initialize.selector,
            deployer,  // Deployer is the initial admin
            MINIMUM_STAKE_AMOUNT,
            address(unifiedOracle)
        );
        
        // Deploy TransparentUpgradeableProxy with the implementation and initialization data
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(stakingImplementation),
            address(proxyAdmin),
            initializeData
        );
        
        // Cast proxy address to NativeStaking interface
        address payable proxyAddress = payable(address(proxy));
        NativeStaking stakingContract = NativeStaking(proxyAddress);
        
        // Set up roles
        bytes32 managerRole = stakingContract.MANAGER_ROLE();
        bytes32 operatorRole = stakingContract.OPERATOR_ROLE();
        
        // Grant manager role to intended addresses
        stakingContract.grantRole(managerRole, MANAGER_ADDRESS);
        stakingContract.grantRole(managerRole, OPERATOR_ADDRESS);
        stakingContract.grantRole(managerRole, ADMIN_ADDRESS);
        
        // Grant operator role to intended address
        stakingContract.grantRole(operatorRole, OPERATOR_ADDRESS);
        stakingContract.grantRole(operatorRole, MANAGER_ADDRESS);
        stakingContract.grantRole(operatorRole, ADMIN_ADDRESS);
        
        // Grant admin role to the specified admin address if different from deployer
        stakingContract.grantRole(DEFAULT_ADMIN_ROLE, ADMIN_ADDRESS);
        stakingContract.grantRole(DEFAULT_ADMIN_ROLE, MANAGER_ADDRESS);
        stakingContract.grantRole(DEFAULT_ADMIN_ROLE, OPERATOR_ADDRESS);
        
        // Configure delay settings
        stakingContract.setMinStakeInterval(minStakeInterval);
        stakingContract.setMinUnstakeInterval(minUnstakeInterval);
        stakingContract.setMinClaimInterval(minClaimInterval);
        
        // Print deployment information
        console.log("----- DEPLOYMENT COMPLETE -----");
        console.log("Contract Addresses:");
        console.log("NativeStaking Proxy:", address(stakingContract));
        console.log("NativeStaking Implementation:", address(stakingImplementation));
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("UnifiedOracle:", address(unifiedOracle));
        console.log("MockDIAOracle:", address(mockDiaOracle));
        console.log("");
        
        console.log("Role Assignments:");
        console.log("ADMIN:", ADMIN_ADDRESS);
        console.log("MANAGER:", MANAGER_ADDRESS);
        console.log("OPERATOR:", OPERATOR_ADDRESS);
        console.log("Deployer:", deployer);
        console.log("");
        
        console.log("Delay Settings:");
        console.log("MIN_STAKE_INTERVAL:", minStakeInterval, "seconds");
        console.log("MIN_UNSTAKE_INTERVAL:", minUnstakeInterval, "seconds");
        console.log("MIN_CLAIM_INTERVAL:", minClaimInterval, "seconds");
        console.log("");
        
        console.log("Price Information:");
        console.log("XFI Price (DIA): 0.09 USD (8 decimals)");
        console.log("MPX Price: 0.04 USD (18 decimals)");
        console.log("XFI Fallback Price: 0.09 USD (18 decimals)");
        console.log("");
        
        console.log("Other Parameters:");
        console.log("MINIMUM_STAKE_AMOUNT:", MINIMUM_STAKE_AMOUNT, "wei");
        console.log("");
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}

/**
 * @title MockDIAOracle
 * @dev Mock DIA Oracle implementation for testing and development
 */
contract MockDIAOracle is IDIAOracle {
    // Storage for prices and timestamps
    mapping(string => uint128) private _prices;
    mapping(string => uint128) private _timestamps;
    
    /**
     * @dev Returns the current price and timestamp for the given key
     * @param key The symbol to get the price for (e.g., "XFI/USD")
     * @return price The price with 8 decimals of precision
     * @return timestamp The timestamp when the price was updated
     */
    function getValue(string memory key) external view override returns (uint128 price, uint128 timestamp) {
        return (_prices[key], _timestamps[key]);
    }
    
    /**
     * @dev Sets the price for the given key
     * @param key The symbol to update the price for
     * @param value The price with 8 decimals of precision
     */
    function setPrice(string memory key, uint128 value) external override {
        _prices[key] = value;
        _timestamps[key] = uint128(block.timestamp);
    }
} 