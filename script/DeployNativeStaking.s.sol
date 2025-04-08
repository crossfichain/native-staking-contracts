// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/NativeStaking.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/interfaces/IOracle.sol";

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
        
        // Deploy mock Oracle (required for deployment)
        MockOracle oracle = new MockOracle();
        
        // Deploy NativeStaking implementation
        NativeStaking stakingImplementation = new NativeStaking();
        
        // Deploy ProxyAdmin (for transparent proxy control)
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        
        // Prepare initialization data
        bytes memory initializeData = abi.encodeWithSelector(
            NativeStaking.initialize.selector,
            deployer,  // Deployer is the initial admin
            MINIMUM_STAKE_AMOUNT,
            address(oracle)
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
        
        // Grant operator role to intended address
        stakingContract.grantRole(operatorRole, OPERATOR_ADDRESS);
        
        // Grant admin role to the specified admin address if different from deployer
        if (ADMIN_ADDRESS != deployer) {
            stakingContract.grantRole(DEFAULT_ADMIN_ROLE, ADMIN_ADDRESS);
        }
        
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
        console.log("Oracle:", address(oracle));
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
        
        console.log("Other Parameters:");
        console.log("MINIMUM_STAKE_AMOUNT:", MINIMUM_STAKE_AMOUNT, "wei");
        console.log("");
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}

/**
 * @title MockOracle
 * @dev Simple mock oracle for deployment testing
 */
contract MockOracle is IOracle {
    // Mock conversion rates and prices
    uint256 private constant XFI_TO_MPX_RATE = 1000;
    uint256 private _mpxPrice = 1 ether; // 1 USD per MPX with 18 decimals
    uint256 private _xfiPrice = 1000 ether; // 1000 USD per XFI with 18 decimals
    
    /**
     * @dev Returns the current price for the given asset
     * @param symbol The symbol to get the price for (e.g., "XFI")
     * @return The price with 18 decimals of precision
     */
    function getPrice(string calldata symbol) external view override returns (uint256) {
        if (keccak256(bytes(symbol)) == keccak256(bytes("XFI"))) {
            return _xfiPrice;
        } else if (keccak256(bytes(symbol)) == keccak256(bytes("MPX"))) {
            return _mpxPrice;
        }
        revert("Unsupported symbol");
    }
    
    /**
     * @dev Returns the current XFI price with timestamp
     * @return price The XFI price with 18 decimals
     * @return timestamp The timestamp when the price was updated
     */
    function getXFIPrice() external view override returns (uint256 price, uint256 timestamp) {
        return (_xfiPrice, block.timestamp);
    }
    
    /**
     * @dev Converts XFI to MPX based on current prices
     * @param xfiAmount The amount of XFI to convert
     * @return The equivalent amount of MPX
     */
    function convertXFItoMPX(uint256 xfiAmount) external pure override returns (uint256) {
        return xfiAmount * XFI_TO_MPX_RATE;
    }
    
    /**
     * @dev Sets the MPX/USD price
     * @param price The MPX/USD price with 18 decimals
     */
    function setMPXPrice(uint256 price) external override {
        _mpxPrice = price;
    }
    
    /**
     * @dev Returns the current MPX/USD price
     * @return The MPX/USD price with 18 decimals
     */
    function getMPXPrice() external view override returns (uint256) {
        return _mpxPrice;
    }
    
    /**
     * @dev Mock conversion from MPX to XFI
     * @param mpxAmount Amount of MPX to convert
     * @return xfiAmount Equivalent amount in XFI
     */
    function convertMPXtoXFI(uint256 mpxAmount) external pure returns (uint256) {
        return mpxAmount / XFI_TO_MPX_RATE;
    }
} 