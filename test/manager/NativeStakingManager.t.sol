// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/NativeStakingManager.sol";
import "../../src/core/NativeStaking.sol";
import "../../src/core/NativeStakingVault.sol";
import "../../src/periphery/UnifiedOracle.sol";
import "../../src/periphery/WXFI.sol";
import "../utils/MockDIAOracle.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title NativeStakingManagerTest
 * @dev Test contract for the NativeStakingManager
 */
contract NativeStakingManagerTest is Test {
    // Test constants
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    string public constant VALIDATOR_ID = "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    
    // Contracts
    WXFI public wxfi;
    MockDIAOracle public diaOracle;
    UnifiedOracle public oracle;
    NativeStaking public staking;
    NativeStakingVault public stakingVault;
    NativeStakingManager public manager;
    ProxyAdmin public proxyAdmin;
    
    function setUp() public {
        // Deploy contracts
        vm.startPrank(ADMIN);
        
        // Deploy WXFI
        wxfi = new WXFI();
        
        // Deploy DIA Oracle mock
        diaOracle = new MockDIAOracle();
        diaOracle.setPrice("XFI/USD", 1e8); // $1 with 8 decimals
        
        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin(ADMIN);
        
        // Deploy Oracle
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
        
        // Configure Oracle
        oracle.setCurrentAPR(10); // 10% APR
        oracle.setCurrentAPY(8);  // 8% APY
        oracle.setTotalStakedXFI(1000000 ether);
        oracle.setUnbondingPeriod(14 days);
        oracle.setPrice("XFI", 1 ether); // $1 with 18 decimals
        // Don't set launch timestamp in setUp, let the individual tests handle it
        
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
        
        // Deploy NativeStakingVault (APY)
        NativeStakingVault vaultImpl = new NativeStakingVault();
        bytes memory vaultData = abi.encodeWithSelector(
            NativeStakingVault.initialize.selector,
            address(wxfi),
            address(oracle),
            "XFI Staking Vault",
            "xXFI"
        );
        TransparentUpgradeableProxy vaultProxy = new TransparentUpgradeableProxy(
            address(vaultImpl),
            address(proxyAdmin),
            vaultData
        );
        stakingVault = NativeStakingVault(address(vaultProxy));
        
        // Deploy NativeStakingManager
        NativeStakingManager managerImpl = new NativeStakingManager();
        bytes memory managerData = abi.encodeWithSelector(
            NativeStakingManager.initialize.selector,
            address(staking),
            address(stakingVault),
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
        stakingVault.grantRole(stakingVault.STAKING_MANAGER_ROLE(), address(manager));
        oracle.grantRole(oracle.ORACLE_UPDATER_ROLE(), address(manager));
        oracle.grantRole(oracle.ORACLE_UPDATER_ROLE(), ADMIN);
        
        // Give USER some ETH
        vm.deal(USER, 100 ether);
        
        vm.stopPrank();
    }
    
    function testGetContractAddresses() public {
        // Check that the manager returns the correct contract addresses
        assertEq(manager.getAPRContract(), address(staking), "APR contract address should match");
        assertEq(manager.getAPYContract(), address(stakingVault), "APY contract address should match");
        assertEq(manager.getXFIToken(), address(wxfi), "XFI token address should match");
    }
    
    function testStakeAPR() public {
        uint256 stakeAmount = 10 ether;
        
        // USER stakes native XFI
        vm.prank(USER);
        manager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Check that USER has staked the correct amount
        assertEq(staking.getTotalStaked(USER), stakeAmount, "USER should have staked the correct amount");
    }
    
    function testStakeAPY() public {
        uint256 stakeAmount = 10 ether;
        
        // USER stakes native XFI
        vm.prank(USER);
        manager.stakeAPY{value: stakeAmount}(stakeAmount);
        
        // Check that USER received the correct amount of shares
        assertGt(stakingVault.balanceOf(USER), 0, "USER should have received shares");
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
        
        // USER stakes native XFI
        vm.prank(USER);
        manager.stakeAPR{value: stakeAmount}(stakeAmount, VALIDATOR_ID);
        
        // Record logs to capture the request ID from events
        vm.recordLogs();
        
        // USER requests to unstake half the amount
        vm.prank(USER);
        manager.unstakeAPR(stakeAmount / 2, VALIDATOR_ID);
        
        // Extract the request ID from logs
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = 0; // This will be 0 for the first unstake request
        
        // Check that the request was created
        assertEq(staking.getTotalStaked(USER), stakeAmount / 2, "Half of USER's stake should remain");
        
        // Skip through the unbonding period
        skip(oracle.getUnbondingPeriod() + 1);
        
        // Record balances before claiming
        uint256 balanceBefore = USER.balance;
        uint256 wxfiBalanceBefore = wxfi.balanceOf(USER);
        
        // USER claims the unstaked amount
        vm.startPrank(USER);
        uint256 claimed = manager.claimUnstakeAPR(requestId);
        
        // Unwrap WXFI to native XFI
        uint256 wxfiBalance = wxfi.balanceOf(USER);
        wxfi.withdraw(wxfiBalance);
        vm.stopPrank();
        
        // Check that the right amount was claimed
        assertEq(claimed, stakeAmount / 2, "USER should have claimed half the stake");
        assertEq(USER.balance, balanceBefore + stakeAmount / 2, "USER's balance should have increased");
    }
} 