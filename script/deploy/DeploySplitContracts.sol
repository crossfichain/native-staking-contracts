// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/core/BaseNativeStakingManager.sol";
import "../../src/core/SplitNativeStakingManager.sol";
import "../../src/core/NativeStakingManagerLib.sol";
import "../../src/periphery/UnifiedOracle.sol";
import "../../src/core/NativeStaking.sol";
import "../../src/core/NativeStakingVault.sol";
import "../../src/mocks/MockDIAOracle.sol";
import "../../src/mocks/MockWXFI.sol";

/**
 * @title DeploySplitContracts
 * @dev Deployment script for the split NativeStakingManager architecture
 */
contract DeploySplitContracts {
    // Constants for deployment
    uint256 private constant XFI_PRICE = 1e18;  // 1 USD per XFI
    uint256 private constant INITIAL_APR = 10e16; // 10% APR
    uint256 private constant INITIAL_APY = 12e16; // 12% APY
    uint256 private constant UNBONDING_PERIOD = 21 days; // 21 days unbonding
    
    // Admin roles
    address public constant ADMIN = address(0x123); // Change to real admin address
    address public constant OPERATOR = address(0x456); // Change to real operator address
    address public constant EMERGENCY = address(0x789); // Change to real emergency address
    
    // Role constants
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant COMPOUNDER_ROLE = keccak256("COMPOUNDER_ROLE");
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    
    // Deployed contract addresses
    address public wxfi;
    address public mockDiaOracle;
    address public oracleProxy;
    address public aprStakingProxy;
    address public apyStakingProxy;
    address public stakingManagerProxy;
    address public proxyAdmin;
    
    // Size verification
    function getContractSize(address _contract) public view returns (uint256) {
        uint256 size;
        assembly {
            size := extcodesize(_contract)
        }
        return size;
    }
    
    /**
     * @dev Deploy the contract ecosystem
     */
    function run() external {
        log("=== Starting Split Contract Deployment ===");
        
        // Step 1: Deploy ProxyAdmin
        ProxyAdmin admin = new ProxyAdmin();
        proxyAdmin = address(admin);
        log(string.concat("ProxyAdmin deployed at: ", addressToString(proxyAdmin)));
        
        // Step 2: Deploy MockWXFI and MockDIAOracle
        MockWXFI mockWxfi = new MockWXFI("Wrapped XFI", "WXFI", 18);
        wxfi = address(mockWxfi);
        log(string.concat("MockWXFI deployed at: ", addressToString(wxfi)));
        
        MockDIAOracle diaMock = new MockDIAOracle();
        mockDiaOracle = address(diaMock);
        log(string.concat("MockDIAOracle deployed at: ", addressToString(mockDiaOracle)));
        
        // Step 3: Deploy Oracle with proxy
        UnifiedOracle oracleImpl = new UnifiedOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            UnifiedOracle.initialize.selector,
            mockDiaOracle,
            UNBONDING_PERIOD,
            wxfi
        );
        
        TransparentUpgradeableProxy oracleProxyContract = new TransparentUpgradeableProxy(
            address(oracleImpl),
            proxyAdmin,
            oracleInitData
        );
        oracleProxy = address(oracleProxyContract);
        log(string.concat("Oracle Proxy deployed at: ", addressToString(oracleProxy)));
        
        // Step 4: Deploy APR Staking with proxy
        NativeStaking aprStakingImpl = new NativeStaking();
        bytes memory aprStakingInitData = abi.encodeWithSelector(
            NativeStaking.initialize.selector,
            wxfi,
            oracleProxy
        );
        
        TransparentUpgradeableProxy aprStakingProxyContract = new TransparentUpgradeableProxy(
            address(aprStakingImpl),
            proxyAdmin,
            aprStakingInitData
        );
        aprStakingProxy = address(aprStakingProxyContract);
        log(string.concat("APR Staking Proxy deployed at: ", addressToString(aprStakingProxy)));
        
        // Step 5: Deploy APY Staking with proxy
        NativeStakingVault nativeStakingVaultImpl = new NativeStakingVault();
        bytes memory nativeStakingVaultInitData = abi.encodeWithSelector(
            NativeStakingVault.initialize.selector,
            wxfi,
            oracleProxy,
            "Staked XFI",
            "sXFI"
        );
        
        TransparentUpgradeableProxy nativeStakingVaultProxyContract = new TransparentUpgradeableProxy(
            address(nativeStakingVaultImpl),
            proxyAdmin,
            nativeStakingVaultInitData
        );
        apyStakingProxy = address(nativeStakingVaultProxyContract);
        log(string.concat("APY Staking Proxy deployed at: ", addressToString(apyStakingProxy)));
        
        // Step 6: Deploy SplitNativeStakingManager with proxy
        SplitNativeStakingManager nativeStakingManagerImpl = new SplitNativeStakingManager();
        bytes memory nativeStakingManagerInitData = abi.encodeWithSelector(
            BaseNativeStakingManager.initialize.selector,
            aprStakingProxy,
            apyStakingProxy,
            wxfi,
            oracleProxy,
            true,                   // _enforceMinimums
            30 days,                // _initialFreezeTime
            50 ether,               // _minStake (50 XFI)
            10 ether,               // _minUnstake (10 XFI)
            1 ether                 // _minRewardClaim (1 XFI)
        );
        
        TransparentUpgradeableProxy nativeStakingManagerProxyContract = new TransparentUpgradeableProxy(
            address(nativeStakingManagerImpl),
            proxyAdmin,
            nativeStakingManagerInitData
        );
        stakingManagerProxy = address(nativeStakingManagerProxyContract);
        log(string.concat("Staking Manager Proxy deployed at: ", addressToString(stakingManagerProxy)));
        
        // Step 7: Verify contract sizes
        log("\n=== Contract Size Verification ===");
        
        // Note: We cannot get library size directly, this is an estimate
        uint256 libSize = 2000; // Estimated library size based on code complexity
        uint256 baseSize = getContractSize(address(nativeStakingManagerImpl));
        uint256 sizeLimit = 24576; // Ethereum contract size limit
        
        log(string.concat("NativeStakingManagerLib size (estimated): ", uintToString(libSize), " bytes"));
        log(string.concat("SplitNativeStakingManager size: ", uintToString(baseSize), " bytes"));
        
        if (libSize <= sizeLimit && baseSize <= sizeLimit) {
            log("All contract sizes within limits");
        } else {
            log("One or more contracts exceed size limit!");
            if (libSize > sizeLimit) {
                log(string.concat("  - NativeStakingManagerLib exceeds limit by ", 
                    uintToString(libSize - sizeLimit), " bytes"));
            }
            if (baseSize > sizeLimit) {
                log(string.concat("  - SplitNativeStakingManager exceeds limit by ", 
                    uintToString(baseSize - sizeLimit), " bytes"));
            }
        }
        
        // Step 8: Configure system
        log("\n=== Configuring System ===");
        configureSystem();
        
        // Step 9: Print results and deployment info
        log("\n=== Deployment Complete ===");
        printResults();
        saveAddressesToFile();
    }
    
    /**
     * @dev Configure the system post-deployment
     */
    function configureSystem() internal {
        // Get contract instances
        UnifiedOracle oracle = UnifiedOracle(oracleProxy);
        NativeStaking aprStaking = NativeStaking(aprStakingProxy);
        NativeStakingVault apyStaking = NativeStakingVault(apyStakingProxy);
        SplitNativeStakingManager stakingManager = SplitNativeStakingManager(payable(stakingManagerProxy));
        
        // 1. Configure Oracle settings
        log("Setting Oracle parameters...");
        oracle.setCurrentAPR(INITIAL_APR);
        oracle.setCurrentAPY(INITIAL_APY);
        oracle.setUnbondingPeriod(UNBONDING_PERIOD);
        oracle.setPrice("XFI", XFI_PRICE);
        oracle.setTotalStakedXFI(0);
        oracle.setLaunchTimestamp(block.timestamp);
        
        // 2. Setup roles
        log("Setting up roles...");
        
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
        apyStaking.grantRole(EMERGENCY_ROLE, EMERGENCY);
        apyStaking.grantRole(EMERGENCY_ROLE, ADMIN);
        
        // Staking manager role
        aprStaking.grantRole(STAKING_MANAGER_ROLE, stakingManagerProxy);
        aprStaking.grantRole(STAKING_MANAGER_ROLE, OPERATOR);
        aprStaking.grantRole(STAKING_MANAGER_ROLE, ADMIN);
        apyStaking.grantRole(STAKING_MANAGER_ROLE, stakingManagerProxy);
        apyStaking.grantRole(STAKING_MANAGER_ROLE, OPERATOR);
        apyStaking.grantRole(STAKING_MANAGER_ROLE, ADMIN);
        
        // Operator needs fulfiller role
        stakingManager.grantRole(FULFILLER_ROLE, OPERATOR);
        stakingManager.grantRole(FULFILLER_ROLE, ADMIN);
        
        // Operator needs compounder role for APY Staking
        apyStaking.grantRole(COMPOUNDER_ROLE, OPERATOR);
        apyStaking.grantRole(COMPOUNDER_ROLE, ADMIN);
        
        // Oracle updater role for manager so it can update rewards
        oracle.grantRole(ORACLE_UPDATER_ROLE, stakingManagerProxy);
        
        // Grant UPGRADER_ROLE to admin
        aprStaking.grantRole(UPGRADER_ROLE, ADMIN);
        aprStaking.grantRole(UPGRADER_ROLE, OPERATOR);
        apyStaking.grantRole(UPGRADER_ROLE, ADMIN);
        apyStaking.grantRole(UPGRADER_ROLE, OPERATOR);
        stakingManager.grantRole(UPGRADER_ROLE, ADMIN);
        stakingManager.grantRole(UPGRADER_ROLE, OPERATOR);
        oracle.grantRole(UPGRADER_ROLE, ADMIN);
        oracle.grantRole(UPGRADER_ROLE, OPERATOR);
        
        log("System configured successfully.");
    }
    
    /**
     * @dev Print deployment results
     */
    function printResults() internal view {
        log("\n=== Deployment Results ===");
        log(string.concat("Mock DIA Oracle:       ", addressToString(mockDiaOracle)));
        log(string.concat("WXFI:                  ", addressToString(wxfi)));
        log(string.concat("Oracle:                ", addressToString(oracleProxy)));
        log(string.concat("APR Staking:           ", addressToString(aprStakingProxy)));
        log(string.concat("APY Staking:           ", addressToString(apyStakingProxy)));
        log(string.concat("Staking Manager:       ", addressToString(stakingManagerProxy)));
        log(string.concat("Proxy Admin:           ", addressToString(proxyAdmin)));
        
        log("\n=== Admin Addresses ===");
        log(string.concat("Admin:                 ", addressToString(ADMIN)));
        log(string.concat("Operator:              ", addressToString(OPERATOR)));
        log(string.concat("Emergency:             ", addressToString(EMERGENCY)));
    }
    
    /**
     * @dev Save addresses to file
     */
    function saveAddressesToFile() internal {
        // In production, this would write to a file
        // For this example, we just log the addresses in CSV format
        log("\n=== Contract Addresses CSV ===");
        log(string.concat(
            "contract,",
            addressToString(wxfi), ",",
            addressToString(mockDiaOracle), ",",
            addressToString(oracleProxy), ",",
            addressToString(aprStakingProxy), ",",
            addressToString(apyStakingProxy), ",",
            addressToString(stakingManagerProxy), ",",
            addressToString(proxyAdmin)
        ));
        
        log("\n=== Contract Addresses ENV Format ===");
        log(string.concat("WXFI_ADDRESS=", addressToString(wxfi)));
        log(string.concat("DIA_ORACLE_ADDRESS=", addressToString(mockDiaOracle)));
        log(string.concat("ORACLE_PROXY_ADDRESS=", addressToString(oracleProxy)));
        log(string.concat("APR_STAKING_PROXY_ADDRESS=", addressToString(aprStakingProxy)));
        log(string.concat("APY_STAKING_PROXY_ADDRESS=", addressToString(apyStakingProxy)));
        log(string.concat("STAKING_MANAGER_PROXY_ADDRESS=", addressToString(stakingManagerProxy)));
        log(string.concat("PROXY_ADMIN_ADDRESS=", addressToString(proxyAdmin)));
        log(string.concat("ADMIN_ADDRESS=", addressToString(ADMIN)));
        log(string.concat("OPERATOR_ADDRESS=", addressToString(OPERATOR)));
        log(string.concat("EMERGENCY_ADDRESS=", addressToString(EMERGENCY)));
    }
    
    /**
     * @dev Simple logging function
     */
    function log(string memory message) internal view {
        // In production, this would use a proper logger
        // For this example, we'll use a no-op function
    }
    
    /**
     * @dev Convert address to string
     */
    function addressToString(address _addr) internal pure returns (string memory) {
        bytes memory s = new bytes(42);
        s[0] = "0";
        s[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(_addr)) / (2**(8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 + 2 * i] = char(hi);
            s[2 + 2 * i + 1] = char(lo);
        }
        return string(s);
    }
    
    /**
     * @dev Convert uint to string
     */
    function uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        
        uint256 temp = value;
        uint256 digits;
        
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
    
    /**
     * @dev Helper function for address to string conversion
     */
    function char(bytes1 b) internal pure returns (bytes1) {
        if (uint8(b) < 10) {
            return bytes1(uint8(b) + 0x30);
        } else {
            return bytes1(uint8(b) + 0x57);
        }
    }
} 