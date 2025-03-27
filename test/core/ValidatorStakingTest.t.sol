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
 * @title ValidatorStakingTest
 * @dev Tests for the validator-specific staking features
 */
contract ValidatorStakingTest is Test {
    // Test constants
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    address public constant SECOND_USER = address(0x3);
    string public constant VALIDATOR1 = "mxvaloper1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    string public constant VALIDATOR2 = "mxvaloper1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    uint256 public constant INITIAL_BALANCE = 1000 ether;

    // Contracts
    WXFI public wxfi;
    MockDIAOracle public diaOracle;
    UnifiedOracle public oracle;
    NativeStaking public staking;
    NativeStakingManager public manager;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
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
        NativeStakingManager managerImpl = new NativeStakingManager();
        bytes memory managerData = abi.encodeWithSelector(
            NativeStakingManager.initialize.selector,
            address(staking),
            address(0), // No APY contract for this test
            address(wxfi),
            address(oracle),
            false, // Do not enforce minimum amounts for tests
            0, // Initial freeze time (0 for tests)
            50 ether, // Minimum stake amount
            10 ether, // Minimum unstake amount
            1 ether   // Minimum reward claim amount
        );
        
        TransparentUpgradeableProxy managerProxy = new TransparentUpgradeableProxy(
            address(managerImpl),
            address(proxyAdmin),
            managerData
        );
        
        manager = NativeStakingManager(payable(address(managerProxy)));
        
        // Grant roles
        staking.grantRole(staking.STAKING_MANAGER_ROLE(), address(manager));
        oracle.grantRole(oracle.ORACLE_UPDATER_ROLE(), address(manager));
        
        // Set up initial values
        oracle.setCurrentAPR(10); // 10% APR
        oracle.setPrice("XFI", 1 ether); // $1 per XFI
        oracle.setUnbondingPeriod(14 days);
        
        vm.stopPrank();

        // Mint initial WXFI for tests
        deal(address(wxfi), USER, INITIAL_BALANCE);
        deal(address(wxfi), SECOND_USER, INITIAL_BALANCE);
        deal(address(wxfi), address(manager), INITIAL_BALANCE);
    }
    
    function testStakeWithValidator() public {
        // USER stakes with VALIDATOR1
        uint256 stakeAmount = 100 ether;
        
        vm.startPrank(USER);
        wxfi.approve(address(manager), stakeAmount);
        manager.stakeAPR(stakeAmount, VALIDATOR1);
        vm.stopPrank();
        
        // Verify stake is associated with VALIDATOR1
        NativeStaking.StakeInfo[] memory stakes = staking.getUserStakes(USER);
        assertEq(stakes.length, 1, "Should have one stake");
        assertEq(stakes[0].amount, stakeAmount, "Stake amount should match");
        assertEq(stakes[0].validator, VALIDATOR1, "Validator should match");
        
        // Verify validator stake amount
        uint256 validatorStake = staking.getValidatorStake(USER, VALIDATOR1);
        assertEq(validatorStake, stakeAmount, "Validator stake should match");
        
        // Verify there's no stake for VALIDATOR2
        uint256 validator2Stake = staking.getValidatorStake(USER, VALIDATOR2);
        assertEq(validator2Stake, 0, "Should have no stake for VALIDATOR2");
    }
    
    function testAddToExistingStake() public {
        // USER stakes with VALIDATOR1 twice
        uint256 firstStake = 100 ether;
        uint256 secondStake = 50 ether;
        
        vm.startPrank(USER);
        wxfi.approve(address(manager), firstStake + secondStake);
        manager.stakeAPR(firstStake, VALIDATOR1);
        manager.stakeAPR(secondStake, VALIDATOR1);
        vm.stopPrank();
        
        // Verify stakes are combined for the same validator
        NativeStaking.StakeInfo[] memory stakes = staking.getUserStakes(USER);
        assertEq(stakes.length, 1, "Should have only one stake entry");
        assertEq(stakes[0].amount, firstStake + secondStake, "Stake amount should be combined");
        assertEq(stakes[0].validator, VALIDATOR1, "Validator should match");
        
        // Verify validator stake amount
        uint256 validatorStake = staking.getValidatorStake(USER, VALIDATOR1);
        assertEq(validatorStake, firstStake + secondStake, "Combined validator stake should match");
    }
    
    function testMultipleValidators() public {
        // USER stakes with multiple validators
        uint256 stake1 = 100 ether;
        uint256 stake2 = 200 ether;
        
        vm.startPrank(USER);
        wxfi.approve(address(manager), stake1 + stake2);
        manager.stakeAPR(stake1, VALIDATOR1);
        manager.stakeAPR(stake2, VALIDATOR2);
        vm.stopPrank();
        
        // Verify stakes for each validator
        NativeStaking.StakeInfo[] memory stakes = staking.getUserStakes(USER);
        assertEq(stakes.length, 2, "Should have two stake entries");
        
        // Find and verify stakes for each validator
        uint256 validatorStake1 = staking.getValidatorStake(USER, VALIDATOR1);
        uint256 validatorStake2 = staking.getValidatorStake(USER, VALIDATOR2);
        
        assertEq(validatorStake1, stake1, "VALIDATOR1 stake should match");
        assertEq(validatorStake2, stake2, "VALIDATOR2 stake should match");
        
        // Verify total staked
        uint256 totalStaked = staking.getTotalStaked(USER);
        assertEq(totalStaked, stake1 + stake2, "Total stake should match sum of both validators");
    }
    
    function testUnstakeWithValidator() public {
        // USER stakes with multiple validators
        uint256 stake1 = 100 ether;
        uint256 stake2 = 200 ether;
        
        vm.startPrank(USER);
        wxfi.approve(address(manager), stake1 + stake2);
        manager.stakeAPR(stake1, VALIDATOR1);
        manager.stakeAPR(stake2, VALIDATOR2);
        vm.stopPrank();
        
        // Unstake part of VALIDATOR1
        uint256 unstakeAmount = 50 ether;
        
        vm.startPrank(USER);
        manager.unstakeAPR(unstakeAmount, VALIDATOR1);
        vm.stopPrank();
        
        // Verify remaining stakes
        uint256 remainingStake1 = staking.getValidatorStake(USER, VALIDATOR1);
        uint256 remainingStake2 = staking.getValidatorStake(USER, VALIDATOR2);
        
        assertEq(remainingStake1, stake1 - unstakeAmount, "VALIDATOR1 stake should be reduced");
        assertEq(remainingStake2, stake2, "VALIDATOR2 stake should be unchanged");
        
        // Test unstaking from a validator with no stake
        vm.startPrank(USER);
        vm.expectRevert("No stake found for this validator");
        manager.unstakeAPR(10 ether, "mxvaloper1nonexistent");
        vm.stopPrank();
        
        // Try to unstake more than available balance
        vm.startPrank(USER);
        vm.expectRevert("Validator is in unbonding period for this user");
        manager.unstakeAPR(100e18, VALIDATOR1);
        vm.stopPrank();
    }
    
    function testGetUserStakesFormat() public {
        // USER stakes with multiple validators
        uint256 stake1 = 100 ether;
        uint256 stake2 = 200 ether;
        
        vm.startPrank(USER);
        wxfi.approve(address(manager), stake1 + stake2);
        manager.stakeAPR(stake1, VALIDATOR1);
        manager.stakeAPR(stake2, VALIDATOR2);
        vm.stopPrank();
        
        // Get all stakes and print them for visual verification
        NativeStaking.StakeInfo[] memory stakes = staking.getUserStakes(USER);
        
        console.log("Number of stakes:", stakes.length);
        
        for (uint i = 0; i < stakes.length; i++) {
            console.log("Stake", i);
            console.log("  Validator:", stakes[i].validator);
            console.log("  Amount:", stakes[i].amount);
            console.log("  Staked at:", stakes[i].stakedAt);
            console.log("  Unbonding at:", stakes[i].unbondingAt);
        }
        
        // Verify each stake has all the expected data
        for (uint i = 0; i < stakes.length; i++) {
            assertGt(bytes(stakes[i].validator).length, 0, "Validator should not be empty");
            assertGt(stakes[i].amount, 0, "Amount should be positive");
            assertGt(stakes[i].stakedAt, 0, "Staked timestamp should be set");
            assertEq(stakes[i].unbondingAt, 0, "Unbonding timestamp should be 0 for active stakes");
        }
    }
} 