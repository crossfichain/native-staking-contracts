// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../utils/MockDIAOracle.sol";
import "../../src/periphery/UnifiedOracle.sol";
import "../../src/core/NativeStaking.sol";
import "../../src/core/NativeStakingVault.sol";
import "../../src/core/NativeStakingManager.sol";
import "../../src/periphery/WXFI.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title NativeStakingE2ETest
 * @dev Comprehensive end-to-end test for the Native Staking system
 * 
 * Note: This test focuses on the basic functionality of the system.
 * The unstaking tests need further refinement to properly track request IDs
 * and handle the unstaking freeze period.
 */
contract NativeStakingE2ETest is Test {
    // System contracts
    UnifiedOracle public oracle;
    MockDIAOracle public diaOracle;
    NativeStaking public aprStaking;
    NativeStakingVault public apyStaking;
    NativeStakingManager public stakingManager;
    WXFI public wxfi;
    ProxyAdmin public proxyAdmin;
    
    // Test accounts
    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    // Test constants
    string public constant VALIDATOR_ID = "validator1";
    uint256 public constant INITIAL_USER_BALANCE = 10000 ether;
    
    // For event capturing
    event StakedAPR(address indexed user, uint256 xfiAmount, uint256 mpxAmount, string validator, bool success, uint256 indexed requestId);
    event StakedAPY(address indexed user, uint256 xfiAmount, uint256 mpxAmount, uint256 shares, uint256 indexed requestId);
    event UnstakedAPR(address indexed user, uint256 xfiAmount, uint256 mpxAmount, string validator, uint256 indexed requestId);
    event WithdrawalRequestedAPY(address indexed user, uint256 xfiAssets, uint256 mpxAssets, uint256 indexed requestId);
    
    function setUp() public {
        console.log("Starting E2E test setup");
        
        // Setup admin
        vm.startPrank(admin);
        
        // 1. Deploy MockDIAOracle
        diaOracle = new MockDIAOracle();
        diaOracle.setPrice("XFI/USD", 1e8); // $1 with 8 decimals
        console.log("MockDIAOracle deployed");
        
        // 2. Deploy WXFI
        wxfi = new WXFI();
        console.log("WXFI deployed");
        
        // 3. Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin(admin);
        console.log("ProxyAdmin deployed");
        
        // 4. Deploy UnifiedOracle with proxy
        UnifiedOracle oracleImpl = new UnifiedOracle();
        bytes memory oracleData = abi.encodeWithSelector(
            UnifiedOracle.initialize.selector,
            address(diaOracle)
        );
        
        TransparentUpgradeableProxy oracleProxy = new TransparentUpgradeableProxy(
            address(oracleImpl),
            address(proxyAdmin),
            oracleData
        );
        
        oracle = UnifiedOracle(address(oracleProxy));
        console.log("UnifiedOracle deployed at:", address(oracle));
        
        // 5. Deploy APR Staking (NativeStaking) with proxy
        NativeStaking aprStakingImpl = new NativeStaking();
        bytes memory aprStakingData = abi.encodeWithSelector(
            NativeStaking.initialize.selector,
            address(wxfi),
            address(oracle)
        );
        
        TransparentUpgradeableProxy aprStakingProxy = new TransparentUpgradeableProxy(
            address(aprStakingImpl),
            address(proxyAdmin),
            aprStakingData
        );
        
        aprStaking = NativeStaking(payable(address(aprStakingProxy)));
        console.log("APR Staking deployed at:", address(aprStaking));
        
        // 6. Deploy APY Staking (NativeStakingVault) with proxy
        NativeStakingVault apyStakingImpl = new NativeStakingVault();
        bytes memory apyStakingData = abi.encodeWithSelector(
            NativeStakingVault.initialize.selector,
            address(wxfi), // 1. underlying asset (_asset)
            address(oracle), // 2. oracle
            "Staked XFI", // 3. name
            "sXFI"       // 4. symbol
        );
        
        TransparentUpgradeableProxy apyStakingProxy = new TransparentUpgradeableProxy(
            address(apyStakingImpl),
            address(proxyAdmin),
            apyStakingData
        );
        
        apyStaking = NativeStakingVault(address(apyStakingProxy));
        console.log("APY Staking deployed at:", address(apyStaking));
        
        // 7. Deploy NativeStakingManager with proxy
        NativeStakingManager managerImpl = new NativeStakingManager();
        bytes memory managerData = abi.encodeWithSelector(
            NativeStakingManager.initialize.selector,
            address(aprStaking),
            address(apyStaking),
            address(wxfi),
            address(oracle)
        );
        
        TransparentUpgradeableProxy managerProxy = new TransparentUpgradeableProxy(
            address(managerImpl),
            address(proxyAdmin),
            managerData
        );
        
        stakingManager = NativeStakingManager(payable(address(managerProxy)));
        console.log("Native Staking Manager deployed at:", address(stakingManager));
        
        // 8. Configure roles
        // Grant roles to staking manager
        aprStaking.grantRole(aprStaking.STAKING_MANAGER_ROLE(), address(stakingManager));
        apyStaking.grantRole(apyStaking.STAKING_MANAGER_ROLE(), address(stakingManager));
        
        // Grant admin roles to admin
        stakingManager.grantRole(stakingManager.DEFAULT_ADMIN_ROLE(), admin);
        aprStaking.grantRole(aprStaking.DEFAULT_ADMIN_ROLE(), admin);
        apyStaking.grantRole(apyStaking.DEFAULT_ADMIN_ROLE(), admin);
        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), admin);
        
        // Grant fulfiller role to admin for testing
        stakingManager.grantRole(stakingManager.FULFILLER_ROLE(), admin);
        
        // Grant Oracle updater role to admin
        oracle.grantRole(oracle.ORACLE_UPDATER_ROLE(), admin);
        
        // 9. Configure Oracle
        oracle.setPrice("XFI", 1 ether);         // $1 with 18 decimals
        oracle.setCurrentAPR(10);                // 10% APR (will be converted to 10 * 1e18 / 100 = 1e17)
        oracle.setCurrentAPY(8);                 // 8% APY (will be converted to 8 * 1e18 / 100 = 8e16)
        oracle.setTotalStakedXFI(1000 ether);    // 1000 XFI staked
        oracle.setUnbondingPeriod(14 days);      // 14 days unbonding
        
        // Set launch timestamp to now to simulate a new deployment
        uint256 launchTime = block.timestamp;
        oracle.setLaunchTimestamp(launchTime);
        console.log("Oracle configured with launch timestamp:", launchTime);
        
        vm.stopPrank();
        
        // 10. Setup test users
        // Give user1 some native XFI
        vm.deal(user1, INITIAL_USER_BALANCE);
        vm.deal(user2, INITIAL_USER_BALANCE);
        
        console.log("E2E test setup completed");
    }
    
    /**
     * @dev Tests APR staking with native XFI
     */
    function testAPRStaking() public {
        console.log("Testing APR staking with native XFI");
        
        uint256 stakeAmount = 1 ether;
        
        // User1 stakes native XFI
        vm.startPrank(user1);
        
        // Extract requestId from event
        vm.recordLogs();
        bool stakeSuccess = stakingManager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        assertTrue(stakeSuccess, "APR stake should succeed");
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId;
        
        // Find the StakedAPR event and extract requestId
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("StakedAPR(address,uint256,uint256,string,bool,uint256)")) {
                requestId = uint256(entries[i].topics[2]); // indexed requestId is topics[2]
                break;
            }
        }
        
        vm.stopPrank();
        
        console.log("APR Stake Request ID:", requestId);
        
        // Admin fulfills the stake request
        vm.startPrank(admin);
        stakingManager.fulfillRequest(requestId, NativeStakingManager.RequestStatus.FULFILLED, "");
        vm.stopPrank();
        
        // Verify stake
        uint256 totalStaked = aprStaking.getTotalStaked(user1);
        assertEq(totalStaked, stakeAmount, "APR stake amount mismatch");
        
        console.log("APR staking test completed successfully");
    }
    
    /**
     * @dev Tests APY staking with native XFI
     */
    function testAPYStaking() public {
        console.log("Testing APY staking with native XFI");
        
        uint256 stakeAmount = 1 ether;
        
        // User2 stakes native XFI
        vm.startPrank(user2);
        
        uint256 beforeShares = apyStaking.balanceOf(user2);
        uint256 sharesReceived = stakingManager.stakeAPY{value: stakeAmount}(stakeAmount);
        uint256 afterShares = apyStaking.balanceOf(user2);
        
        vm.stopPrank();
        
        // Verify stake
        assertGt(sharesReceived, 0, "APY stake should return shares");
        assertGt(afterShares, beforeShares, "User should have more shares after staking");
        
        console.log("APY staking test completed successfully");
    }
    
    /**
     * @dev Tests Oracle functionality
     */
    function testOraclePriceAndAPR() public view {
        // Test XFI price
        uint256 price = oracle.getPrice("XFI");
        assertEq(price, 1 ether, "XFI price should be $1");
        
        // Test APR
        uint256 apr = oracle.getCurrentAPR();
        assertEq(apr, 10 * 1e16, "APR should be 10%");
        
        // Test APY
        uint256 apy = oracle.getCurrentAPY();
        assertEq(apy, 8 * 1e16, "APY should be 8%");
        
        // Test total staked
        uint256 totalStaked = oracle.getTotalStakedXFI();
        assertEq(totalStaked, 1000 ether, "Total staked should be 1000 XFI");
    }
    
    // TODO: Implement proper unstaking tests that handle request IDs correctly
    // function testAPRUnstaking() public { ... }
    // function testAPYUnstaking() public { ... }
    
    receive() external payable {}
} 