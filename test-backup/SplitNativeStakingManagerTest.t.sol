// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/core/SplitNativeStakingManager.sol";
import "../src/core/BaseNativeStakingManager.sol";
import "../src/core/NativeStakingManagerLib.sol";
import "../src/core/NativeStaking.sol";
import "../src/core/NativeStakingVault.sol";
import "../src/periphery/UnifiedOracle.sol";
import "../src/mocks/MockWXFI.sol";
import "../src/mocks/MockDIAOracle.sol";

contract SplitNativeStakingManagerTest is Test {
    SplitNativeStakingManager public splitManager;
    MockWXFI public wxfi;
    NativeStaking public aprStaking;
    NativeStakingVault public apyStaking;
    UnifiedOracle public oracle;
    MockDIAOracle public diaOracle;
    
    address deployer = address(0x1);
    address user = address(0x2);
    address operator = address(0x3);
    
    uint256 public constant INITIAL_SUPPLY = 1000000 * 1e18;
    uint256 public constant MIN_STAKE = 10 * 1e18;
    uint256 public constant MIN_UNSTAKE = 5 * 1e18;
    uint256 public constant MIN_REWARD_CLAIM = 1 * 1e18;
    uint256 public constant UNBONDING_PERIOD = 14 days;
    
    // Role identifiers
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    
    function setUp() public {
        vm.startPrank(deployer);
        
        // Deploy mock tokens and oracles
        wxfi = new MockWXFI("Wrapped XFI", "WXFI", 18);
        diaOracle = new MockDIAOracle();
        
        // Initialize all implementations
        SplitNativeStakingManager managerImpl = new SplitNativeStakingManager();
        NativeStaking aprImpl = new NativeStaking();
        NativeStakingVault apyImpl = new NativeStakingVault();
        UnifiedOracle oracleImpl = new UnifiedOracle();
        
        // Setup proxies for all implementations
        ERC1967Proxy managerProxy = new ERC1967Proxy(
            address(managerImpl),
            ""
        );
        ERC1967Proxy aprProxy = new ERC1967Proxy(
            address(aprImpl),
            ""
        );
        ERC1967Proxy apyProxy = new ERC1967Proxy(
            address(apyImpl),
            ""
        );
        ERC1967Proxy oracleProxy = new ERC1967Proxy(
            address(oracleImpl),
            ""
        );
        
        // Create contract references to proxies
        splitManager = SplitNativeStakingManager(payable(address(managerProxy)));
        aprStaking = NativeStaking(address(aprProxy));
        apyStaking = NativeStakingVault(address(apyProxy));
        oracle = UnifiedOracle(address(oracleProxy));
        
        // Initialize the oracle
        oracle.initialize(
            address(diaOracle),
            UNBONDING_PERIOD,
            address(wxfi)
        );
        
        // Initialize APR staking
        aprStaking.initialize(
            address(wxfi),
            address(oracle)
        );
        
        // Initialize APY staking
        apyStaking.initialize(
            address(wxfi),
            address(oracle),
            "Staked XFI",
            "sXFI"
        );
        
        // Initialize the manager
        splitManager.initialize(
            address(aprStaking),
            address(apyStaking), 
            address(wxfi),
            address(oracle),
            true, // enforce minimums
            0,    // no initial freeze
            MIN_STAKE,
            MIN_UNSTAKE,
            MIN_REWARD_CLAIM
        );
        
        // Setup roles
        aprStaking.grantRole(STAKING_MANAGER_ROLE, address(splitManager));
        apyStaking.grantRole(STAKING_MANAGER_ROLE, address(splitManager));
        oracle.grantRole(ORACLE_UPDATER_ROLE, deployer);
        
        // Add operator with all necessary roles
        splitManager.grantRole(PAUSER_ROLE, operator);
        splitManager.grantRole(FULFILLER_ROLE, operator);
        splitManager.grantRole(EMERGENCY_ROLE, operator);
        
        // Mint tokens for testing
        wxfi.mint(user, INITIAL_SUPPLY);
        wxfi.mint(deployer, INITIAL_SUPPLY);
        
        // Set up oracle with initial values
        vm.mockCall(
            address(diaOracle),
            abi.encodeWithSelector(diaOracle.getValue.selector, "XFI"),
            abi.encode(1e18, block.timestamp)
        );
        
        // Instead of calling updateOracleData, set the oracle values directly
        // This is a workaround since updateOracleData isn't found in the oracle contract
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getCurrentAPR.selector),
            abi.encode(500) // 5% APR in basis points
        );
        
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getUnbondingPeriod.selector),
            abi.encode(UNBONDING_PERIOD)
        );
        
        vm.stopPrank();
    }
    
    function testInitialization() public {
        // Check that all contracts are properly initialized
        assertEq(address(splitManager.aprStaking()), address(aprStaking));
        assertEq(address(splitManager.apyStaking()), address(apyStaking));
        assertEq(address(splitManager.wxfi()), address(wxfi));
        assertEq(address(splitManager.oracle()), address(oracle));
        
        // Check role assignments
        assertTrue(splitManager.hasRole(DEFAULT_ADMIN_ROLE, deployer));
        assertTrue(splitManager.hasRole(PAUSER_ROLE, operator));
        assertTrue(splitManager.hasRole(FULFILLER_ROLE, operator));
        assertTrue(splitManager.hasRole(EMERGENCY_ROLE, operator));
        
        // Check initialized settings
        assertTrue(splitManager.enforceMinimums());
        assertEq(splitManager.minStake(), MIN_STAKE);
        assertEq(splitManager.minUnstake(), MIN_UNSTAKE);
        assertEq(splitManager.minRewardClaim(), MIN_REWARD_CLAIM);
    }
    
    function testRequestStake() public {
        uint256 stakeAmount = 100 * 1e18;
        
        // Approve tokens for staking
        vm.startPrank(user);
        wxfi.approve(address(splitManager), stakeAmount);
        
        // Request stake with the split manager
        uint256 requestId = splitManager.requestStake(
            stakeAmount, 
            NativeStakingManagerLib.StakingMode.APR,
            "mxvaloper123456789abcdef"
        );
        vm.stopPrank();
        
        // Verify request was created
        assertEq(requestId, 0);
        
        // Verify tokens were transferred to the manager
        assertEq(wxfi.balanceOf(address(splitManager)), stakeAmount);
        assertEq(wxfi.balanceOf(user), INITIAL_SUPPLY - stakeAmount);
    }
    
    function testFulfillStake() public {
        uint256 stakeAmount = 100 * 1e18;
        
        // First request a stake
        vm.startPrank(user);
        wxfi.approve(address(splitManager), stakeAmount);
        uint256 requestId = splitManager.requestStake(
            stakeAmount, 
            NativeStakingManagerLib.StakingMode.APR,
            "mxvaloper123456789abcdef"
        );
        vm.stopPrank();
        
        // Now fulfill the stake as operator
        vm.startPrank(operator);
        bool fulfilled = splitManager.fulfillStake(requestId);
        vm.stopPrank();
        
        // Verify the stake was fulfilled
        assertTrue(fulfilled);
        
        // Check that tokens were staked in APR contract
        assertEq(aprStaking.getTotalStake(user), stakeAmount);
    }
    
    function testPauseUnpause() public {
        // Test pause functionality
        vm.prank(operator);
        splitManager.pause();
        assertTrue(splitManager.paused());
        
        // Try to stake while paused (should revert)
        vm.startPrank(user);
        wxfi.approve(address(splitManager), 100 * 1e18);
        vm.expectRevert("Pausable: paused");
        splitManager.requestStake(
            100 * 1e18, 
            NativeStakingManagerLib.StakingMode.APR,
            "mxvaloper123456789abcdef"
        );
        vm.stopPrank();
        
        // Unpause and verify it works again
        vm.prank(operator);
        splitManager.unpause();
        assertFalse(splitManager.paused());
        
        // Stake after unpausing
        vm.startPrank(user);
        uint256 requestId = splitManager.requestStake(
            100 * 1e18, 
            NativeStakingManagerLib.StakingMode.APR,
            "mxvaloper123456789abcdef"
        );
        vm.stopPrank();
        
        // Verify request was created
        assertEq(requestId, 0);
    }
    
    function testFreezeUnfreezeUnstaking() public {
        // Test freezing unstaking
        uint256 freezeDuration = 7 days;
        
        vm.prank(operator);
        splitManager.freezeUnstaking(freezeDuration);
        
        // Check that unstaking is frozen
        assertTrue(splitManager.isUnstakingFrozen());
        assertEq(splitManager.freezeDuration(), freezeDuration);
        
        // Manually thaw unstaking
        vm.prank(operator);
        splitManager.thawUnstaking();
        
        // Check that unstaking is no longer frozen
        assertFalse(splitManager.isUnstakingFrozen());
    }
    
    function testSetMinimums() public {
        // Test setting new minimums
        uint256 newMinStake = 20 * 1e18;
        uint256 newMinUnstake = 10 * 1e18;
        uint256 newMinRewardClaim = 2 * 1e18;
        
        vm.prank(deployer);
        splitManager.setMinimums(true, newMinStake, newMinUnstake, newMinRewardClaim);
        
        // Check that minimums were updated
        assertTrue(splitManager.enforceMinimums());
        assertEq(splitManager.minStake(), newMinStake);
        assertEq(splitManager.minUnstake(), newMinUnstake);
        assertEq(splitManager.minRewardClaim(), newMinRewardClaim);
        
        // Try to stake below minimum (should revert)
        vm.startPrank(user);
        wxfi.approve(address(splitManager), newMinStake - 1);
        vm.expectRevert("Amount below minimum");
        splitManager.requestStake(
            newMinStake - 1, 
            NativeStakingManagerLib.StakingMode.APR,
            "mxvaloper123456789abcdef"
        );
        vm.stopPrank();
        
        // Disable minimum enforcement
        vm.prank(deployer);
        splitManager.setMinimums(false, newMinStake, newMinUnstake, newMinRewardClaim);
        
        // Try to stake below minimum (should succeed now)
        vm.startPrank(user);
        wxfi.approve(address(splitManager), newMinStake - 1);
        uint256 requestId = splitManager.requestStake(
            newMinStake - 1, 
            NativeStakingManagerLib.StakingMode.APR,
            "mxvaloper123456789abcdef"
        );
        vm.stopPrank();
        
        // Verify request was created
        assertEq(requestId, 0);
    }
} 