// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NativeStaking} from "../../src/core/NativeStaking.sol";
import {NativeStakingManager} from "../../src/core/NativeStakingManager.sol";
import {NativeStakingVault} from "../../src/core/NativeStakingVault.sol";
import {UnifiedOracle} from "../../src/periphery/UnifiedOracle.sol";
import {MockDIAOracle} from "../mocks/MockDIAOracle.sol";
import {MockUnifiedOracle} from "../mocks/MockUnifiedOracle.sol";
import {WXFI} from "../../src/periphery/WXFI.sol";
import {INativeStaking} from "../../src/interfaces/INativeStaking.sol";

/**
 * @title APRStakingBaseTest
 * @dev Base contract for testing the Native Staking APR flow
 * Provides common setup and utility functions for all APR-related tests
 */
contract APRStakingBaseTest is Test {
    // Contracts
    NativeStaking public nativeStaking;
    NativeStakingManager public stakingManager;
    NativeStakingVault public stakingVault;
    UnifiedOracle public oracle;
    MockDIAOracle public diaOracle;
    WXFI public wxfi;
    
    // Mock contracts for isolated testing
    MockUnifiedOracle public mockOracle;
    
    // Test accounts
    address public admin = address(this);
    address public treasury = address(0x1);
    address public user1 = address(0x100);
    address public user2 = address(0x200);
    address public user3 = address(0x300);
    
    // Constants
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant MIN_STAKE_AMOUNT = 1 ether;
    uint256 public constant APR = 10e16; // 10% with 18 decimals
    uint256 public constant APY = 8e16;  // 8% with 18 decimals
    uint256 public constant UNBONDING_PERIOD = 14 days;
    
    // Events (from INativeStaking)
    event Staked(address indexed user, uint256 amount, string validator, uint256 stakeId);
    event UnstakeRequested(address indexed user, uint256 amount, string validator, uint256 indexed requestId, uint256 unlockTime);
    event UnstakeClaimed(address indexed user, uint256 amount, uint256 indexed requestId);
    event RewardsClaimed(address indexed user, uint256 amount);
    
    function setUp() public virtual {
        // Label accounts for easier debugging
        vm.label(admin, "Admin");
        vm.label(treasury, "Treasury");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        
        // Set up initial balances
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(user3, INITIAL_BALANCE);
        vm.deal(treasury, INITIAL_BALANCE);
        
        // Deploy mock DIA Oracle
        diaOracle = new MockDIAOracle();
        diaOracle.setPrice("XFI/USD", 1e8); // $1 price
        
        // Deploy WXFI token
        wxfi = new WXFI();
        
        // Deploy and initialize Oracle
        oracle = new UnifiedOracle();
        oracle.initialize(address(diaOracle));
        oracle.setTotalStakedXFI(1000000 ether); // Initial total staked
        oracle.setCurrentAPR(10); // 10%
        oracle.setCurrentAPY(8);  // 8%
        oracle.setUnbondingPeriod(UNBONDING_PERIOD);
        
        // Deploy stakingVault with WXFI token
        stakingVault = new NativeStakingVault();
        stakingVault.initialize(
            address(wxfi),
            address(oracle),
            "XFI Staking Vault",
            "xXFI"
        );
        
        // Deploy Native Staking
        nativeStaking = new NativeStaking();
        nativeStaking.initialize(
            address(wxfi),
            address(oracle)
        );
        
        // Deploy staking manager
        stakingManager = new NativeStakingManager();
        stakingManager.initialize(
            payable(address(nativeStaking)),
            address(stakingVault),
            address(wxfi),
            address(oracle)
        );
        
        // Setup roles
        _setupRoles();
        
        // Deploy mock oracle for isolated testing
        mockOracle = new MockUnifiedOracle();
    }
    
    /**
     * @dev Setup roles for contracts
     */
    function _setupRoles() internal {
        // Grant staking manager role to the manager contract
        bytes32 stakingManagerRole = nativeStaking.STAKING_MANAGER_ROLE();
        nativeStaking.grantRole(stakingManagerRole, address(stakingManager));
        
        // Grant admin roles
        nativeStaking.grantRole(nativeStaking.DEFAULT_ADMIN_ROLE(), admin);
        stakingManager.grantRole(stakingManager.DEFAULT_ADMIN_ROLE(), admin);
        stakingVault.grantRole(stakingVault.DEFAULT_ADMIN_ROLE(), admin);
        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), admin);
        
        // Oracle updater role
        oracle.grantRole(oracle.ORACLE_UPDATER_ROLE(), admin);
    }
    
    /**
     * @dev Helper to perform a direct stake for testing
     */
    function _stakeDirectXFI(address user, uint256 amount, string memory validator) internal {
        vm.deal(user, address(user).balance + amount);
        vm.prank(user);
        (bool success, ) = address(stakingManager).call{value: amount}(
            abi.encodeWithSignature("stakeAPR(uint256,string)", amount, validator)
        );
        require(success, "Stake failed");
    }
    
    /**
     * @dev Helper to advance time and get updated rewards
     */
    function _advanceTimeAndUpdateAPR(uint256 timeToAdvance, uint256 newAPR) internal {
        skip(timeToAdvance);
        oracle.setCurrentAPR(newAPR);
    }
    
    /**
     * @dev Helper to check staking information
     */
    function _checkStake(
        address user,
        uint256 stakeIndex,
        uint256 expectedAmount,
        uint256 expectedStakedAt,
        uint256 expectedUnbondingAt
    ) internal {
        INativeStaking.StakeInfo[] memory stakes = nativeStaking.getUserStakes(user);
        assertGe(stakes.length, stakeIndex + 1, "Stake doesn't exist");
        
        INativeStaking.StakeInfo memory stake = stakes[stakeIndex];
        assertEq(stake.amount, expectedAmount, "Stake amount incorrect");
        assertEq(stake.stakedAt, expectedStakedAt, "StakedAt timestamp incorrect");
        assertEq(stake.unbondingAt, expectedUnbondingAt, "UnbondingAt timestamp incorrect");
    }
    
    /**
     * @dev Helper to check unstake request information
     */
    function _checkUnstakeRequest(
        address user,
        uint256 requestIndex,
        uint256 expectedAmount,
        uint256 expectedUnlockTime,
        bool expectedCompleted
    ) internal {
        INativeStaking.UnstakeRequest[] memory requests = nativeStaking.getUserUnstakeRequests(user);
        assertGe(requests.length, requestIndex + 1, "Unstake request doesn't exist");
        
        INativeStaking.UnstakeRequest memory request = requests[requestIndex];
        assertEq(request.amount, expectedAmount, "Unstake amount incorrect");
        assertEq(request.unlockTime, expectedUnlockTime, "Unlock time incorrect");
        assertEq(request.completed, expectedCompleted, "Completed status incorrect");
    }
} 