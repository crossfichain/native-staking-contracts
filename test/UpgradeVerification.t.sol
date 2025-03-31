// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/core/BaseNativeStakingManager.sol";
import "../src/core/SplitNativeStakingManager.sol";
import "../src/mocks/MockDIAOracle.sol";
import "../src/mocks/MockWXFI.sol";
import "../src/periphery/UnifiedOracle.sol";

/**
 * @title UpgradeVerificationTest
 * @dev Test contract to verify upgrade functionality with the split architecture
 */
contract UpgradeVerificationTest is Test {
    // Test contracts
    MockWXFI public wxfi;
    MockDIAOracle public mockDiaOracle;
    UnifiedOracle public oracle;
    SplitNativeStakingManager public stakingManager;
    
    // Proxy components
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public stakingManagerProxy;
    
    // Test accounts
    address public admin = address(0x1);
    address public operator = address(0x2);
    address public user = address(0x3);
    
    // Role constants
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
    
    /**
     * @dev Set up the test environment
     */
    function setUp() public {
        // Set up accounts
        vm.startPrank(admin);
        
        // Deploy mock contracts
        wxfi = new MockWXFI("Wrapped XFI", "WXFI", 18);
        mockDiaOracle = new MockDIAOracle();
        
        // Deploy Oracle
        UnifiedOracle oracleImpl = new UnifiedOracle();
        
        // Deploy proxy admin
        proxyAdmin = new ProxyAdmin();
        
        // Deploy oracle proxy
        bytes memory oracleInitData = abi.encodeWithSelector(
            UnifiedOracle.initialize.selector,
            address(mockDiaOracle),
            21 days, // unbonding period
            address(wxfi)
        );
        
        TransparentUpgradeableProxy oracleProxy = new TransparentUpgradeableProxy(
            address(oracleImpl),
            address(proxyAdmin),
            oracleInitData
        );
        
        oracle = UnifiedOracle(address(oracleProxy));
        
        // Deploy original staking manager implementation
        SplitNativeStakingManager stakingManagerImpl = new SplitNativeStakingManager();
        
        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            BaseNativeStakingManager.initialize.selector,
            address(0), // apr staking (not used in this test)
            address(0), // apy staking (not used in this test)
            address(wxfi),
            address(oracle),
            true,       // enforce minimums
            30 days,    // initial freeze time
            50 ether,   // min stake
            10 ether,   // min unstake
            1 ether     // min reward claim
        );
        
        // Deploy proxy pointing to implementation
        stakingManagerProxy = new TransparentUpgradeableProxy(
            address(stakingManagerImpl),
            address(proxyAdmin),
            initData
        );
        
        // Create interface to proxy
        stakingManager = SplitNativeStakingManager(payable(address(stakingManagerProxy)));
        
        // Set up roles
        stakingManager.grantRole(DEFAULT_ADMIN_ROLE, admin);
        stakingManager.grantRole(UPGRADER_ROLE, admin);
        stakingManager.grantRole(FULFILLER_ROLE, operator);
        
        // Mint some tokens to user
        wxfi.mint(user, 1000 ether);
        
        vm.stopPrank();
    }
    
    /**
     * @dev Helper function to get the implementation address from a proxy
     */
    function getImplementation(address proxy) internal returns (address) {
        (bool success, bytes memory data) = address(proxyAdmin).call(
            abi.encodeWithSignature("getProxyImplementation(address)", proxy)
        );
        require(success, "Call to getProxyImplementation failed");
        return abi.decode(data, (address));
    }
    
    /**
     * @dev Helper function to upgrade a proxy to a new implementation
     */
    function upgradeProxy(address proxy, address implementation) internal {
        (bool success, ) = address(proxyAdmin).call(
            abi.encodeWithSignature("upgrade(address,address)", proxy, implementation)
        );
        require(success, "Call to upgrade failed");
    }
    
    /**
     * @dev Test upgrading the implementation
     */
    function testUpgradeImplementation() public {
        // Create a new implementation version
        vm.startPrank(admin);
        SplitNativeStakingManager newImplementation = new SplitNativeStakingManager();
        
        // Get the current implementation address
        address currentImpl = getImplementation(address(stakingManagerProxy));
        
        // Upgrade to the new implementation
        upgradeProxy(address(stakingManagerProxy), address(newImplementation));
        
        // Check that the implementation was upgraded
        address newImpl = getImplementation(address(stakingManagerProxy));
        assertNotEq(currentImpl, newImpl, "Implementation should have changed");
        assertEq(newImpl, address(newImplementation), "New implementation should be set");
        
        // Verify that state is preserved
        bool enforceMinimums = stakingManager.enforceMinimums();
        assertTrue(enforceMinimums, "State should be preserved after upgrade");
        
        vm.stopPrank();
    }
    
    /**
     * @dev Test that only authorized accounts can upgrade
     */
    function testUpgradeAuthorization() public {
        // Create a new implementation version
        SplitNativeStakingManager newImplementation = new SplitNativeStakingManager();
        
        // Try to upgrade from unauthorized account (should fail)
        vm.startPrank(user);
        vm.expectRevert();
        stakingManager.upgradeTo(address(newImplementation));
        vm.stopPrank();
        
        // Upgrade from authorized account (should succeed)
        vm.startPrank(admin);
        stakingManager.upgradeTo(address(newImplementation));
        vm.stopPrank();
        
        // Check that the implementation was upgraded
        address newImpl = getImplementation(address(stakingManagerProxy));
        assertEq(newImpl, address(newImplementation), "New implementation should be set");
    }
    
    /**
     * @dev Test contract size
     */
    function testContractSize() public {
        // Get contract code size
        uint256 implSize = address(stakingManager).code.length;
        uint256 sizeLimit = 24576; // Ethereum contract size limit
        
        // Check that implementation is within size limit
        assertTrue(implSize <= sizeLimit, "Implementation size exceeds limit");
        
        // Log the size
        emit log_named_uint("Implementation size (bytes)", implSize);
        emit log_named_uint("Size limit (bytes)", sizeLimit);
        emit log_named_uint("Remaining space (bytes)", sizeLimit - implSize);
    }
} 