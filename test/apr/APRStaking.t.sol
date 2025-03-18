// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/NativeStaking.sol";
import "../../src/core/NativeStakingManager.sol";
import "../../src/periphery/UnifiedOracle.sol";
import "../../src/periphery/WXFI.sol";
import "../utils/MockDIAOracle.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title APRStakingTest
 * @dev Simple test for APR staking flow
 */
contract APRStakingTest is Test {
    // Test constants
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    string public constant VALIDATOR_ID = "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    
    // Contracts
    WXFI public wxfi;
    MockDIAOracle public diaOracle;
    UnifiedOracle public oracle;
    NativeStaking public staking;
    NativeStakingManager public manager;
    ProxyAdmin public proxyAdmin;
    
    function setUp() public {
        vm.startPrank(ADMIN);
        
        // Deploy WXFI
        wxfi = new WXFI();
        
        // Deploy DIA Oracle mock
        diaOracle = new MockDIAOracle();
        diaOracle.setPrice("XFI/USD", 1e8); // $1 with 8 decimals
        
        // Deploy Oracle
        UnifiedOracle oracleImpl = new UnifiedOracle();
        proxyAdmin = new ProxyAdmin(ADMIN);
        
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
        
        // Configure Oracle
        oracle.setCurrentAPR(10); // 10% APR
        oracle.setPrice("XFI", 1 ether); // $1 with 18 decimals
        oracle.setTotalStakedXFI(1000000 ether);
        oracle.setUnbondingPeriod(14 days);
        
        // Deploy NativeStaking
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
        NativeStakingManager managerImpl = new NativeStakingManager();
        
        bytes memory managerData = abi.encodeWithSelector(
            NativeStakingManager.initialize.selector,
            address(staking),
            address(0), // No APY contract for this test
            address(wxfi),
            address(oracle),
            false // Do not enforce minimum amounts for tests
        );
        
        TransparentUpgradeableProxy managerProxy = new TransparentUpgradeableProxy(
            address(managerImpl),
            address(proxyAdmin),
            managerData
        );
        
        manager = NativeStakingManager(payable(address(managerProxy)));
        
        // Setup roles
        staking.grantRole(staking.STAKING_MANAGER_ROLE(), address(manager));
        oracle.grantRole(oracle.ORACLE_UPDATER_ROLE(), address(manager));
        
        // Give USER some ETH
        vm.deal(USER, 100 ether);
        
        vm.stopPrank();
    }
    
    function testStakeAPR() public {
        // Set launch timestamp and unstake freeze time to 0 to disable unstaking freeze
        vm.startPrank(ADMIN);
        oracle.setLaunchTimestamp(0);
        manager.setUnstakeFreezeTime(0);
        vm.stopPrank();
        
        uint256 stakeAmount = 10 ether;
        
        vm.prank(USER);
        manager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        assertEq(staking.getTotalStaked(USER), stakeAmount, "Staked amount should match");
    }
    
    function testUnstakeAPR() public {
        // Set launch timestamp and unstake freeze time to 0 to disable unstaking freeze
        vm.startPrank(ADMIN);
        oracle.setLaunchTimestamp(0);
        manager.setUnstakeFreezeTime(0);
        
        // Fund the contract with WXFI for payouts
        vm.deal(ADMIN, 10 ether);
        wxfi.deposit{value: 5 ether}();
        IERC20(address(wxfi)).transfer(address(staking), 5 ether);
        vm.stopPrank();
        
        uint256 stakeAmount = 10 ether;
        uint256 unstakeAmount = 5 ether;
        
        // Stake first
        vm.prank(USER);
        manager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Record logs to capture the request ID from events
        vm.recordLogs();
        
        // Request unstake
        vm.prank(USER);
        manager.unstakeAPR(unstakeAmount, VALIDATOR_ID);
        
        // Extract the request ID from logs
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = 0; // This will be 0 for the first unstake request
        
        // Verify remaining staked amount
        assertEq(staking.getTotalStaked(USER), stakeAmount - unstakeAmount, "Remaining staked amount should be correct");
        
        // Skip through unbonding period
        skip(oracle.getUnbondingPeriod() + 1);
        
        // Record balances before claiming
        uint256 balanceBefore = USER.balance;
        uint256 wxfiBalanceBefore = wxfi.balanceOf(USER);
        
        // Claim unstake
        vm.startPrank(USER);
        manager.claimUnstakeAPR(requestId);
        
        // Unwrap WXFI to native XFI
        uint256 wxfiBalance = wxfi.balanceOf(USER);
        wxfi.withdraw(wxfiBalance);
        vm.stopPrank();
        
        // Check final balance
        assertEq(USER.balance, balanceBefore + unstakeAmount, "User balance should increase by unstake amount");
    }
} 