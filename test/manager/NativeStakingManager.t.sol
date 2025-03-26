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
import "../mocks/MockUnifiedOracle.sol";

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
            address(diaOracle),
            14 days // unbonding period
        );
        TransparentUpgradeableProxy oracleProxy = new TransparentUpgradeableProxy(
            address(oracleImpl),
            address(proxyAdmin),
            oracleData
        );
        oracle = UnifiedOracle(address(oracleProxy));
        
        // Configure Oracle
        MockDIAOracle(address(diaOracle)).setPrice("XFI/USD", 1e8); // $1 with 8 decimals
        MockUnifiedOracle(address(oracle)).setAPR(10 * 1e16); // 10% APR
        MockUnifiedOracle(address(oracle)).setAPY(8 * 1e16);  // 8% APY
        MockUnifiedOracle(address(oracle)).setTotalStaked(1000000 ether);
        MockUnifiedOracle(address(oracle)).setValidatorAPR(12 * 1e16); // 12% validator APR
        MockUnifiedOracle(address(oracle)).setPrice(1 ether); // $1 with 18 decimals
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

    function testValidatorUnbonding() public {
        // Setup
        vm.startPrank(ADMIN);
        manager.setLaunchTimestamp(0);
        manager.setUnstakeFreezeTime(0);
        vm.stopPrank();

        // Fund contract with WXFI
        deal(address(wxfi), address(manager), 5 ether);

        // Stake with validator
        vm.startPrank(USER);
        manager.stakeAPR{value: 1 ether}(1 ether, "mxva123");
        vm.stopPrank();

        // Request unstake
        vm.startPrank(USER);
        uint256 requestId = manager.unstakeAPR(0.5 ether, "mxva123");
        vm.stopPrank();

        // Check unbonding period is set
        assertTrue(manager.isValidatorUnbondingForUser(USER, "mxva123"));
        uint256 unbondingEnd = manager.getValidatorUnbondingEndTime(USER, "mxva123");
        assertTrue(unbondingEnd > block.timestamp);

        // Try to stake with same validator during unbonding
        vm.startPrank(USER);
        vm.expectRevert("Validator is in unbonding period for this user");
        manager.stakeAPR{value: 0.5 ether}(0.5 ether, "mxva123");
        vm.stopPrank();

        // Stake with different validator (should work)
        vm.startPrank(USER);
        manager.stakeAPR{value: 0.5 ether}(0.5 ether, "mxva456");
        vm.stopPrank();

        // Fast forward past unbonding period
        vm.warp(unbondingEnd + 1);

        // Check unbonding period is ended
        assertFalse(manager.isValidatorUnbondingForUser(USER, "mxva123"));

        // Should be able to stake with same validator again
        vm.startPrank(USER);
        manager.stakeAPR{value: 0.5 ether}(0.5 ether, "mxva123");
        vm.stopPrank();
    }

    function testUnstakeWithRewards() public {
        // Setup
        vm.startPrank(ADMIN);
        manager.setLaunchTimestamp(0);
        manager.setUnstakeFreezeTime(0);
        vm.stopPrank();

        // Fund contract with WXFI
        deal(address(wxfi), address(manager), 5 ether);

        // Stake with validator
        vm.startPrank(USER);
        manager.stakeAPR{value: 1 ether}(1 ether, "mxva123");
        vm.stopPrank();

        // Set some rewards (below threshold)
        vm.startPrank(ADMIN);
        MockUnifiedOracle(address(oracle)).setAPR(10 * 1e16); // 10% APR
        MockUnifiedOracle(address(oracle)).setAPY(8 * 1e16);  // 8% APY
        MockUnifiedOracle(address(oracle)).setTotalStaked(1000000 ether);
        MockUnifiedOracle(address(oracle)).setValidatorAPR(12 * 1e16); // 12% validator APR
        vm.stopPrank();

        // Request unstake
        vm.startPrank(USER);
        uint256 requestId = manager.unstakeAPR(0.5 ether, "mxva123");
        vm.stopPrank();

        // Check rewards were claimed
        assertEq(wxfi.balanceOf(USER), 5 ether); // Rewards should be transferred

        // Fast forward past unbonding period
        vm.warp(block.timestamp + oracle.getUnbondingPeriod() + 1);

        // Claim unstake
        vm.startPrank(USER);
        uint256 claimedAmount = manager.claimUnstakeAPR(requestId);
        vm.stopPrank();

        // Verify claimed amount
        assertEq(claimedAmount, 0.5 ether);
        assertEq(wxfi.balanceOf(USER), 5.5 ether); // Rewards + unstaked amount
    }

    function testUnstakeWithMultipleValidators() public {
        // Setup
        vm.startPrank(ADMIN);
        manager.setLaunchTimestamp(0);
        manager.setUnstakeFreezeTime(0);
        vm.stopPrank();

        // Fund contract with WXFI
        deal(address(wxfi), address(manager), 5 ether);

        // Stake with multiple validators
        vm.startPrank(USER);
        manager.stakeAPR{value: 1 ether}(1 ether, "mxva123");
        manager.stakeAPR{value: 1 ether}(1 ether, "mxva456");
        manager.stakeAPR{value: 1 ether}(1 ether, "mxva789");
        vm.stopPrank();

        // Set rewards
        vm.startPrank(ADMIN);
        MockUnifiedOracle(address(oracle)).setAPR(10 * 1e16); // 10% APR
        MockUnifiedOracle(address(oracle)).setAPY(8 * 1e16);  // 8% APY
        MockUnifiedOracle(address(oracle)).setTotalStaked(1000000 ether);
        MockUnifiedOracle(address(oracle)).setValidatorAPR(12 * 1e16); // 12% validator APR
        vm.stopPrank();

        // Unstake from one validator
        vm.startPrank(USER);
        uint256 requestId = manager.unstakeAPR(0.5 ether, "mxva123");
        vm.stopPrank();

        // Check rewards were claimed
        assertEq(wxfi.balanceOf(USER), 5 ether);

        // Try to unstake from same validator (should fail)
        vm.startPrank(USER);
        vm.expectRevert("Validator is in unbonding period for this user");
        manager.unstakeAPR(0.5 ether, "mxva123");
        vm.stopPrank();

        // Unstake from different validator (should work)
        vm.startPrank(USER);
        uint256 requestId2 = manager.unstakeAPR(0.5 ether, "mxva456");
        vm.stopPrank();

        // Fast forward past unbonding period
        vm.warp(block.timestamp + oracle.getUnbondingPeriod() + 1);

        // Claim both unstakes
        vm.startPrank(USER);
        uint256 claimedAmount1 = manager.claimUnstakeAPR(requestId);
        uint256 claimedAmount2 = manager.claimUnstakeAPR(requestId2);
        vm.stopPrank();

        // Verify claimed amounts
        assertEq(claimedAmount1, 0.5 ether);
        assertEq(claimedAmount2, 0.5 ether);
        assertEq(wxfi.balanceOf(USER), 6.5 ether); // Rewards + both unstaked amounts
    }

    function testUnstakeWithRewardsAboveThreshold() public {
        // Setup
        vm.startPrank(ADMIN);
        manager.setLaunchTimestamp(0);
        manager.setUnstakeFreezeTime(0);
        vm.stopPrank();

        // Fund contract with WXFI
        deal(address(wxfi), address(manager), 5 ether);

        // Stake with validator
        vm.startPrank(USER);
        manager.stakeAPR{value: 1 ether}(1 ether, "mxva123");
        vm.stopPrank();

        // Set rewards above threshold
        vm.startPrank(ADMIN);
        MockUnifiedOracle(address(oracle)).setAPR(10 * 1e16); // 10% APR
        MockUnifiedOracle(address(oracle)).setAPY(8 * 1e16);  // 8% APY
        MockUnifiedOracle(address(oracle)).setTotalStaked(1000000 ether);
        MockUnifiedOracle(address(oracle)).setValidatorAPR(12 * 1e16); // 12% validator APR
        vm.stopPrank();

        // Request unstake
        vm.startPrank(USER);
        uint256 requestId = manager.unstakeAPR(0.5 ether, "mxva123");
        vm.stopPrank();

        // Check rewards were claimed
        assertEq(wxfi.balanceOf(USER), 5 ether);

        // Fast forward past unbonding period
        vm.warp(block.timestamp + oracle.getUnbondingPeriod() + 1);

        // Claim unstake
        vm.startPrank(USER);
        uint256 claimedAmount = manager.claimUnstakeAPR(requestId);
        vm.stopPrank();

        // Verify claimed amount
        assertEq(claimedAmount, 0.5 ether);
        assertEq(wxfi.balanceOf(USER), 5.5 ether); // Rewards + unstaked amount
    }

    function testEdgeCases() public {
        // Test maximum values
        uint256 maxAmount = type(uint256).max;
        
        // Test staking with maximum amount
        vm.startPrank(USER);
        vm.deal(USER, maxAmount);
        manager.stakeAPR{value: maxAmount}(maxAmount, VALIDATOR_ID);
        vm.stopPrank();
        
        // Test unstaking with maximum amount
        vm.startPrank(USER);
        manager.unstakeAPR(maxAmount, VALIDATOR_ID);
        vm.stopPrank();
        
        // Test rewards with maximum values
        vm.startPrank(ADMIN);
        MockUnifiedOracle(address(oracle)).setAPR(maxAmount);
        MockUnifiedOracle(address(oracle)).setAPY(maxAmount);
        MockUnifiedOracle(address(oracle)).setTotalStaked(maxAmount);
        MockUnifiedOracle(address(oracle)).setValidatorAPR(maxAmount);
        vm.stopPrank();
    }

    function testOracleFailure() public {
        // Test when oracle returns zero price
        vm.startPrank(ADMIN);
        MockUnifiedOracle(address(oracle)).setPrice(0);
        vm.stopPrank();
        
        // Attempt to stake should fail
        vm.startPrank(USER);
        vm.expectRevert("Oracle price cannot be zero");
        manager.stakeAPR{value: 1 ether}(1 ether, VALIDATOR_ID);
        vm.stopPrank();
        
        // Test when oracle returns unreasonably high APR
        vm.startPrank(ADMIN);
        MockUnifiedOracle(address(oracle)).setAPR(51 * 1e16); // 51% APR
        vm.stopPrank();
        
        // Attempt to stake should fail
        vm.startPrank(USER);
        vm.expectRevert("APR value is unreasonably high");
        manager.stakeAPR{value: 1 ether}(1 ether, VALIDATOR_ID);
        vm.stopPrank();
    }

    function testEmergencyPause() public {
        // Test pausing contract
        vm.startPrank(ADMIN);
        manager.pause();
        vm.stopPrank();
        
        // Attempt to stake should fail
        vm.startPrank(USER);
        vm.expectRevert("Pausable: paused");
        manager.stakeAPR{value: 1 ether}(1 ether, VALIDATOR_ID);
        vm.stopPrank();
        
        // Test unpausing contract
        vm.startPrank(ADMIN);
        manager.unpause();
        vm.stopPrank();
        
        // Stake should now work
        vm.startPrank(USER);
        manager.stakeAPR{value: 1 ether}(1 ether, VALIDATOR_ID);
        vm.stopPrank();
    }

    function testContractUpgrade() public {
        // Deploy new implementation
        NativeStakingManager newImpl = new NativeStakingManager();
        
        // Upgrade contract
        vm.startPrank(ADMIN);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(manager)),
            address(newImpl),
            ""
        );
        vm.stopPrank();
        
        // Verify functionality still works
        vm.startPrank(USER);
        manager.stakeAPR{value: 1 ether}(1 ether, VALIDATOR_ID);
        vm.stopPrank();
        
        assertEq(staking.getTotalStaked(USER), 1 ether, "Staking should work after upgrade");
    }

    function testGasOptimization() public {
        // Test gas usage for multiple operations
        uint256 gasStart = gasleft();
        
        // Perform multiple operations
        vm.startPrank(USER);
        manager.stakeAPR{value: 1 ether}(1 ether, VALIDATOR_ID);
        manager.stakeAPR{value: 1 ether}(1 ether, "mxva456");
        manager.stakeAPR{value: 1 ether}(1 ether, "mxva789");
        vm.stopPrank();
        
        uint256 gasUsed = gasStart - gasleft();
        assertTrue(gasUsed < 1000000, "Gas usage should be reasonable");
    }

    function testValidatorManipulation() public {
        // Test invalid validator format
        vm.startPrank(USER);
        vm.expectRevert("Invalid validator format: must start with 'mxva'");
        manager.stakeAPR{value: 1 ether}(1 ether, "invalid_validator");
        vm.stopPrank();
        
        // Test empty validator
        vm.startPrank(USER);
        vm.expectRevert("Invalid validator format: must start with 'mxva'");
        manager.stakeAPR{value: 1 ether}(1 ether, "");
        vm.stopPrank();
        
        // Test very long validator
        string memory longValidator = "mxva";
        for(uint i = 0; i < 100; i++) {
            longValidator = string(abi.encodePacked(longValidator, "x"));
        }
        vm.startPrank(USER);
        vm.expectRevert("Invalid validator format: must start with 'mxva'");
        manager.stakeAPR{value: 1 ether}(1 ether, longValidator);
        vm.stopPrank();
    }
} 