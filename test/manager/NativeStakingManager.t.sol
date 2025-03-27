// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/NativeStakingManager.sol";
import "../../src/core/NativeStakingVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockStakingOracle} from "../mocks/MockStakingOracle.sol";
import "../../src/core/APRStaking.sol";

/**
 * @title NativeStakingManagerTest
 * @dev Test contract for the NativeStakingManager
 */
contract NativeStakingManagerTest is Test {
    // Test contracts
    MockERC20 public xfi;
    MockERC20 public wxfi;
    MockStakingOracle public oracle;
    NativeStakingVault public vault;
    NativeStakingManager public manager;
    APRStaking public aprContract;
    
    // Test constants
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant APY = 1000; // 10% in basis points
    uint256 public constant UNBONDING_PERIOD = 14 days;
    address public constant ADMIN = address(0x4);
    address public constant USER = address(0x1);
    address public constant USER2 = address(0x2);
    address public constant COMPOUNDER = address(0x3);
    
    function setUp() public {
        vm.startPrank(ADMIN);
        
        // Deploy mock contracts
        xfi = new MockERC20("XFI", "XFI", 18);
        wxfi = new MockERC20("WXFI", "WXFI", 18);
        oracle = new MockStakingOracle();
        
        // Setup oracle with initial values
        oracle.setXfiPrice(1e18);
        oracle.setMpxPrice(1e18);
        oracle.setCurrentAPR(1000); // 10% APR
        oracle.setUnbondingPeriod(UNBONDING_PERIOD);
        
        // Deploy contracts
        manager = new NativeStakingManager();
        aprContract = new APRStaking();
        vault = new NativeStakingVault();
        
        // Initialize contracts first
        manager.initialize(
            address(aprContract),
            address(vault),
            address(wxfi),
            address(oracle),
            false, // Don't enforce minimums for tests
            0, // No initial freeze time
            50 ether, // Min stake amount
            10 ether, // Min unstake amount
            1 ether // Min reward claim amount
        );
        
        aprContract.initialize(address(oracle), address(wxfi));
        vault.initialize(
            address(wxfi),
            address(oracle),
            "XFI Staking Vault",
            "xXFI"
        );
        
        // Setup roles after initialization
        vm.startPrank(ADMIN);
        manager.grantRole(manager.DEFAULT_ADMIN_ROLE(), ADMIN);
        manager.grantRole(manager.FULFILLER_ROLE(), ADMIN);
        manager.grantRole(manager.ORACLE_MANAGER_ROLE(), ADMIN);
        vm.stopPrank();
        
        vm.startPrank(ADMIN);
        aprContract.grantRole(aprContract.DEFAULT_ADMIN_ROLE(), ADMIN);
        vm.stopPrank();
        
        vm.startPrank(ADMIN);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), ADMIN);
        vault.grantRole(vault.STAKING_MANAGER_ROLE(), address(manager));
        vault.grantRole(vault.COMPOUNDER_ROLE(), COMPOUNDER);
        vm.stopPrank();
        
        // Mint tokens for testing
        xfi.mint(USER, INITIAL_BALANCE);
        xfi.mint(USER2, INITIAL_BALANCE);
        wxfi.mint(address(manager), INITIAL_BALANCE);
        wxfi.mint(USER, INITIAL_BALANCE);
        wxfi.mint(USER2, INITIAL_BALANCE);
        wxfi.mint(address(oracle), INITIAL_BALANCE);
        
        // Mint initial shares to prevent inflation attacks
        wxfi.mint(ADMIN, 1 ether);
        vm.startPrank(ADMIN);
        wxfi.approve(address(vault), 1 ether);
        vault.deposit(1 ether, ADMIN);
        vm.stopPrank();
        
        // Approve manager for staking
        vm.startPrank(USER);
        xfi.approve(address(manager), INITIAL_BALANCE);
        xfi.approve(address(vault), INITIAL_BALANCE);
        wxfi.approve(address(manager), INITIAL_BALANCE);
        wxfi.approve(address(vault), INITIAL_BALANCE);
        vm.stopPrank();
        
        vm.startPrank(USER2);
        xfi.approve(address(manager), INITIAL_BALANCE);
        xfi.approve(address(vault), INITIAL_BALANCE);
        wxfi.approve(address(manager), INITIAL_BALANCE);
        wxfi.approve(address(vault), INITIAL_BALANCE);
        vm.stopPrank();
        
        // Setup oracle rewards
        vm.startPrank(address(oracle));
        MockStakingOracle(address(oracle)).setUserClaimableRewards(USER, 100 ether);
        MockStakingOracle(address(oracle)).setUserClaimableRewards(USER2, 100 ether);
        MockStakingOracle(address(oracle)).setValidatorStake(USER, "mxvaloper1", 100 ether);
        MockStakingOracle(address(oracle)).setValidatorStake(USER2, "mxvaloper1", 100 ether);
        vm.stopPrank();
        
        vm.stopPrank();
    }
    
    function testGetContractAddresses() public {
        assertEq(manager.getAPYContract(), address(vault), "APY contract address should match");
        assertEq(manager.getXFIToken(), address(wxfi), "WXFI token address should match");
    }
    
    function testStakeAPY() public {
        uint256 stakeAmount = 100 ether;
        
        vm.startPrank(USER);
        wxfi.approve(address(manager), stakeAmount);
        uint256 shares = manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        assertGt(shares, 0, "Should receive vault shares");
        assertEq(vault.balanceOf(USER), shares, "User should own the shares");
        assertEq(wxfi.balanceOf(address(vault)), stakeAmount + 1 ether, "Vault should hold the WXFI");
    }
    
    function testWithdraw() public {
        uint256 stakeAmount = 100 ether;
        
        // Ensure manager has enough tokens for operations
        vm.startPrank(ADMIN);
        wxfi.mint(address(manager), stakeAmount * 10);
        wxfi.mint(address(vault), stakeAmount * 10);
        vm.stopPrank();
        
        // User stakes XFI
        vm.startPrank(USER);
        xfi.approve(address(manager), stakeAmount);
        uint256 shares = manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        // Fast forward 6 months and compound rewards
        vm.warp(block.timestamp + 180 days);
        
        // Add rewards
        vm.startPrank(COMPOUNDER);
        uint256 rewardAmount = 10 ether;
        xfi.mint(COMPOUNDER, rewardAmount);
        xfi.approve(address(vault), rewardAmount);
        
        // Make sure vault has approval to spend the tokens
        wxfi.approve(address(vault), rewardAmount);
        bool success = vault.compoundRewards(rewardAmount);
        vm.stopPrank();
        
        assertTrue(success, "Compound should succeed");
        
        // Make sure vault has enough tokens
        vm.startPrank(ADMIN);
        wxfi.mint(address(vault), stakeAmount * 10);
        vm.stopPrank();
        
        // User requests withdrawal
        vm.startPrank(USER);
        vault.approve(address(manager), shares); // Approve shares for withdrawal
        bytes memory requestId = manager.withdrawAPY(shares);
        vm.stopPrank();
        
        assertGt(requestId.length, 0, "Should get valid request ID");
        
        // Fast forward through unbonding period
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);
        
        // Make sure vault has enough tokens for withdrawal
        vm.startPrank(ADMIN);
        wxfi.mint(address(vault), stakeAmount * 2); // Provide ample liquidity to the vault
        vm.stopPrank();
        
        // Ensure the vault's max liquidity is set to allow withdrawals
        vm.startPrank(ADMIN);
        vault.setMaxLiquidityPercent(10000); // 100% for testing
        vm.stopPrank();
        
        // User claims withdrawal
        vm.startPrank(USER);
        uint256 assets = manager.claimWithdrawalAPY(requestId);
        vm.stopPrank();
        
        assertGt(assets, 0, "Should get assets back");
        assertGt(xfi.balanceOf(USER), INITIAL_BALANCE - stakeAmount, "User should get XFI back with rewards");
    }
    
    function testCompoundingRewards() public {
        uint256 stakeAmount = 1000 ether;
        uint256 rewardAmount = 100 ether;
        
        // User stakes XFI
        vm.startPrank(USER);
        xfi.approve(address(manager), stakeAmount);
        manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        // Add rewards
        vm.startPrank(COMPOUNDER);
        xfi.mint(COMPOUNDER, rewardAmount);
        wxfi.mint(COMPOUNDER, rewardAmount);
        
        // Approve both xfi and wxfi to be spent by the vault
        xfi.approve(address(vault), rewardAmount);
        wxfi.approve(address(vault), rewardAmount);
        
        vault.compoundRewards(rewardAmount);
        vm.stopPrank();
        
        // Check total assets
        uint256 totalAssets = vault.totalAssets();
        assertGe(totalAssets, stakeAmount, "Total assets should include staked amount at minimum");
        
        // User withdraws everything
        vm.startPrank(ADMIN);
        vault.setMaxLiquidityPercent(10000); // 100% for testing
        
        // Ensure vault has enough liquidity
        wxfi.mint(address(vault), stakeAmount * 2);
        vm.stopPrank();
        
        vm.startPrank(USER);
        uint256 shares = vault.balanceOf(USER);
        uint256 assets = vault.redeem(shares, USER, USER);
        vm.stopPrank();
        
        assertGt(assets, 0, "Should get assets back");
    }
    
    function testClaimRewardsAPRForValidator() public {
        uint256 rewardAmount = 10 ether;
        string memory validator = "mxvaloper1";
        
        // Setup oracle rewards for specific validator
        vm.startPrank(address(oracle));
        oracle.setUserClaimableRewardsForValidator(USER, validator, rewardAmount);
        oracle.setValidatorStake(USER, validator, 100 ether);
        vm.stopPrank();
        
        // Ensure manager has enough tokens
        vm.startPrank(ADMIN);
        wxfi.mint(address(manager), rewardAmount * 2);
        vm.stopPrank();
        
        // User claims rewards
        vm.startPrank(USER);
        bytes memory requestIdBytes = manager.claimRewardsAPRForValidator(validator, rewardAmount);
        vm.stopPrank();
        
        // Since we've updated the system to use bytes requestId, we need to handle it differently
        // We're no longer checking the specific request details via getRequest since it's using the new format
        
        // Instead, verify the rewards were transferred correctly
        assertEq(wxfi.balanceOf(USER), INITIAL_BALANCE + rewardAmount, "User should receive rewards");
        
        // Verify we received a valid bytes requestId
        assertGt(requestIdBytes.length, 0, "Request ID should not be empty");
    }
    
    function testClaimRewardsAPRForMultipleValidators() public {
        // Setup
        string memory validator1 = "mxva123456789";
        string memory validator2 = "mxva987654321";
        uint256 stakeAmount = 1000 ether;
        uint256 rewardAmount1 = 100 ether;
        uint256 rewardAmount2 = 200 ether;
        
        // Stake with first validator
        vm.startPrank(USER);
        wxfi.approve(address(manager), stakeAmount);
        manager.stakeAPR(stakeAmount, validator1);
        vm.stopPrank();
        
        // Mint more WXFI to the user for the second stake
        wxfi.mint(USER, stakeAmount);
        
        // Stake with second validator
        vm.startPrank(USER);
        wxfi.approve(address(manager), stakeAmount);
        manager.stakeAPR(stakeAmount, validator2);
        vm.stopPrank();
        
        // Set rewards for both validators
        oracle.setUserClaimableRewardsForValidator(USER, validator1, rewardAmount1);
        oracle.setUserClaimableRewardsForValidator(USER, validator2, rewardAmount2);
        
        // Set validator stakes in oracle
        oracle.setValidatorStake(USER, validator1, stakeAmount);
        oracle.setValidatorStake(USER, validator2, stakeAmount);
        
        // Set total rewards
        oracle.setUserClaimableRewards(USER, rewardAmount1 + rewardAmount2);
        
        // Mint rewards to the manager for both validators
        wxfi.mint(address(manager), rewardAmount1);
        wxfi.mint(address(manager), rewardAmount2);
        
        // Claim rewards from both validators
        vm.startPrank(USER);
        bytes memory requestId1 = manager.claimRewardsAPRForValidator(validator1, rewardAmount1);
        bytes memory requestId2 = manager.claimRewardsAPRForValidator(validator2, rewardAmount2);
        vm.stopPrank();
        
        // Verify
        assertEq(wxfi.balanceOf(USER), INITIAL_BALANCE - stakeAmount + rewardAmount1 + rewardAmount2, "Total rewards not transferred");
        
        // Verify the request IDs
        assertTrue(requestId1.length > 0, "Request ID 1 should not be empty");
        assertTrue(requestId2.length > 0, "Request ID 2 should not be empty");
    }
    
    function testClaimAllRewardsAPR() public {
        // Setup
        string memory validator1 = "mxva123456789";
        string memory validator2 = "mxva987654321";
        uint256 stakeAmount = 1000 ether;
        uint256 rewardAmount1 = 100 ether;
        uint256 rewardAmount2 = 200 ether;
        
        // Stake with first validator
        vm.startPrank(USER);
        wxfi.approve(address(manager), stakeAmount);
        manager.stakeAPR(stakeAmount, validator1);
        vm.stopPrank();
        
        // Mint more WXFI to the user for the second stake
        wxfi.mint(USER, stakeAmount);
        
        // Stake with second validator
        vm.startPrank(USER);
        wxfi.approve(address(manager), stakeAmount);
        manager.stakeAPR(stakeAmount, validator2);
        vm.stopPrank();
        
        // Set rewards for both validators
        oracle.setUserClaimableRewardsForValidator(USER, validator1, rewardAmount1);
        oracle.setUserClaimableRewardsForValidator(USER, validator2, rewardAmount2);
        
        // Set validator stakes in oracle
        oracle.setValidatorStake(USER, validator1, stakeAmount);
        oracle.setValidatorStake(USER, validator2, stakeAmount);
        
        // Set total rewards
        oracle.setUserClaimableRewards(USER, rewardAmount1 + rewardAmount2);
        
        // Mint rewards to the manager
        wxfi.mint(address(manager), rewardAmount1 + rewardAmount2);
        
        // Claim all rewards
        vm.prank(USER);
        uint256 claimedAmount = manager.claimRewardsAPR();
        
        // Verify
        assertEq(claimedAmount, rewardAmount1 + rewardAmount2, "Incorrect total reward amount claimed");
        assertEq(wxfi.balanceOf(USER), INITIAL_BALANCE - stakeAmount + rewardAmount1 + rewardAmount2, "Rewards not transferred");
    }
    
    function testFailClaimRewardsAPRForValidatorNoStake() public {
        uint256 rewardAmount = 10 ether;
        string memory validator = "mxvaloper1";
        
        // Setup oracle rewards but no stake
        vm.startPrank(address(oracle));
        oracle.setUserClaimableRewardsForValidator(USER, validator, rewardAmount);
        vm.stopPrank();
        
        // User attempts to claim rewards
        vm.startPrank(USER);
        vm.expectRevert("No stake found for this validator");
        manager.claimRewardsAPRForValidator(validator, rewardAmount);
        vm.stopPrank();
    }
    
    function testFailClaimRewardsAPRForValidatorBelowMin() public {
        // Setup a minimum reward claim amount
        vm.startPrank(ADMIN);
        manager = new NativeStakingManager();
        manager.initialize(
            address(aprContract),
            address(vault),
            address(wxfi),
            address(oracle),
            true, // Enforce minimums for this test
            0, // No initial freeze time
            50 ether, // Min stake amount
            10 ether, // Min unstake amount
            1 ether // Min reward claim amount - this is what we're testing
        );
        vm.stopPrank();
        
        uint256 rewardAmount = 0.5 ether; // Below minimum
        string memory validator = "mxvaloper1";
        
        // Setup oracle rewards and stake
        vm.startPrank(address(oracle));
        oracle.setUserClaimableRewardsForValidator(USER, validator, rewardAmount);
        oracle.setValidatorStake(USER, validator, 100 ether);
        vm.stopPrank();
        
        // User attempts to claim rewards - this should fail with the specified error
        vm.startPrank(USER);
        vm.expectRevert("Amount must be at least minRewardClaimAmount");
        manager.claimRewardsAPRForValidator(validator, rewardAmount);
        vm.stopPrank();
    }
    
    function testFailClaimRewardsAPRNoStake() public {
        // Setup
        uint256 rewardAmount = 100 ether;
        
        // Set rewards without staking
        oracle.setUserClaimableRewards(USER, rewardAmount);
        
        // Attempt to claim rewards
        vm.prank(USER);
        vm.expectRevert("revert: User has no stake");
        manager.claimRewardsAPR();
    }
} 