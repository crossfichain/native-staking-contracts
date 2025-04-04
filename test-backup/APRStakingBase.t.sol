// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/NativeStaking.sol";
import "../../src/core/ConcreteNativeStakingManager.sol";
import "../../src/periphery/UnifiedOracle.sol"; 
import "../../src/periphery/WXFI.sol";
import "../utils/MockDIAOracle.sol";
import "../../src/deployment/DeploymentCoordinator.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title APRStakingBase
 * @dev Base contract for all APR staking related tests
 * Sets up the necessary contracts for testing NativeStaking with the APR model
 */
contract APRStakingBase is Test {
    // Test constants
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    address public constant SECOND_USER = address(0x3);
    string public constant VALIDATOR_ID = "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";

    // Contracts
    WXFI public wxfi;
    MockDIAOracle public diaOracle;
    UnifiedOracle public oracle;
    NativeStaking public staking;
    ConcreteNativeStakingManager public manager;
    ProxyAdmin public proxyAdmin;

    /**
     * @dev Test set up function
     */
    function setUp() public virtual {
        // Deploy contracts directly
        vm.startPrank(ADMIN);

        wxfi = new WXFI();

        // Deploy DIA Oracle mock
        diaOracle = new MockDIAOracle();
        // Set XFI price to $1 with 8 decimals in the DIA Oracle
        diaOracle.setPrice("XFI/USD", 1e8);

        // Deploy Oracle with DIA Oracle
        UnifiedOracle oracleImpl = new UnifiedOracle();
        proxyAdmin = new ProxyAdmin();
        
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
        
        // Deploy NativeStaking (APR)
        NativeStaking stakingImpl = new NativeStaking();
        
        bytes memory stakingData = abi.encodeWithSelector(
            NativeStaking.initialize.selector,
            address(wxfi),
            address(oracle)
        );
        
        TransparentUpgradeableProxy stakingProxy = new TransparentUpgradeableProxy(
            address(stakingImpl),
            address(proxyAdmin),
            stakingData
        );
        
        staking = NativeStaking(address(stakingProxy));
        
        // Deploy NativeStakingManager
        ConcreteNativeStakingManager managerImpl = new ConcreteNativeStakingManager();
        bytes memory managerData = abi.encodeWithSelector(
            NativeStakingManager.initialize.selector,
            address(staking),
            address(0), // No APY contract for this test
            address(wxfi),
            address(oracle),
            false, // Do not enforce minimum amounts for tests
            30 days, // Initial freeze time (30 days)
            50 ether, // Minimum stake amount
            10 ether, // Minimum unstake amount
            1 ether   // Minimum reward claim amount
        );
        
        TransparentUpgradeableProxy managerProxy = new TransparentUpgradeableProxy(
            address(managerImpl),
            address(proxyAdmin),
            managerData
        );
        
        manager = ConcreteNativeStakingManager(payable(address(managerProxy)));
        
        // Grant roles
        staking.grantRole(staking.STAKING_MANAGER_ROLE(), address(manager));
        oracle.grantRole(oracle.ORACLE_UPDATER_ROLE(), address(manager));
        
        // Set up initial values
        // Set current APR to 10% (with 18 decimals) - 0.10 * 10^18
        oracle.setCurrentAPR(10); // Takes percentage value (10 = 10%)
        
        // Set XFI price to $1 with 18 decimals in our oracle
        oracle.setPrice("XFI", 1 ether); // 1 * 10^18
        
        // Set launch timestamp to a month ago to disable unstaking freeze
        oracle.setLaunchTimestamp(block.timestamp - 31 days);
        
        vm.stopPrank();

        // Mint initial WXFI for tests
        mintWXFI(USER, 1000 ether);
        mintWXFI(SECOND_USER, 1000 ether);
    }
    
    /**
     * @dev Helper function to mint WXFI to the given address
     * @param to Address to mint to
     * @param amount Amount to mint
     */
    function mintWXFI(address to, uint256 amount) internal {
        // Use deal to set the WXFI balance of the address
        deal(address(wxfi), to, amount);
    }
    
    /**
     * @dev Helper function to approve WXFI to be spent by the manager
     * @param from Address giving approval
     * @param amount Amount to approve
     */
    function approveWXFI(address from, uint256 amount) internal {
        vm.startPrank(from);
        wxfi.approve(address(manager), amount);
        vm.stopPrank();
    }
    
    /**
     * @dev Helper function to make a user stake XFI with given amount
     * @param from User address
     * @param amount Amount to stake
     */
    function stake(address from, uint256 amount) internal {
        mintWXFI(from, amount);
        approveWXFI(from, amount);
        
        vm.startPrank(from);
        manager.stakeAPR(amount, VALIDATOR_ID);
        vm.stopPrank();
    }
    
    /**
     * @dev Helper function to make a user request to unstake XFI
     * @param from User address
     * @param amount Amount to unstake
     */
    function unstakeRequest(address from, uint256 amount) internal {
        vm.startPrank(from);
        manager.unstakeAPR(amount, VALIDATOR_ID);
        vm.stopPrank();
    }
    
    /**
     * @dev Helper function to fulfill an unstake request
     * @param from User address
     * @param requestId Request ID to fulfill
     */
    function fulfillUnstakeRequest(address from, bytes memory requestId) internal {
        vm.startPrank(from);
        manager.claimUnstakeAPR(requestId);
        vm.stopPrank();
    }
    
    /**
     * @dev Helper function to advance time and update block timestamp
     * @param secondsToAdvance Number of seconds to advance
     */
    function advanceTime(uint256 secondsToAdvance) internal {
        vm.warp(block.timestamp + secondsToAdvance);
    }
    
    /**
     * @dev Helper function to claim rewards
     * @param from User address
     */
    function claimRewards(address from) internal {
        vm.startPrank(from);
        manager.claimRewardsAPR();
        vm.stopPrank();
    }
} 