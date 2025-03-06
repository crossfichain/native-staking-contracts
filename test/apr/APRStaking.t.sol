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

/**
 * @title APRStakingTest
 * @dev Simple test for APR staking flow
 */
contract APRStakingTest is Test {
    // Test constants
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    string public constant VALIDATOR_ID = "validator1";
    
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
        oracle.setLaunchTimestamp(block.timestamp - 31 days); // Set launch timestamp to a month ago
        
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
            address(oracle)
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
        uint256 stakeAmount = 10 ether;
        
        vm.prank(USER);
        manager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        assertEq(staking.getTotalStaked(USER), stakeAmount, "Staked amount should match");
    }
    
    function testUnstakeAPR() public {
        uint256 stakeAmount = 10 ether;
        uint256 unstakeAmount = 5 ether;
        
        // Stake first
        vm.prank(USER);
        manager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Request unstake
        vm.prank(USER);
        uint256 requestId = manager.unstakeAPR(unstakeAmount, VALIDATOR_ID);
        
        // Verify remaining staked amount
        assertEq(staking.getTotalStaked(USER), stakeAmount - unstakeAmount, "Remaining staked amount should be correct");
        
        // Skip through unbonding period
        skip(oracle.getUnbondingPeriod() + 1);
        
        // Claim unstake
        uint256 balanceBefore = USER.balance;
        
        vm.prank(USER);
        manager.claimUnstakeAPR(requestId);
        
        assertEq(USER.balance, balanceBefore + unstakeAmount, "User balance should increase by unstake amount");
    }
} 