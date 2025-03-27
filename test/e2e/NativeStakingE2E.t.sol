// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../mocks/MockERC20.sol";
import {MockStakingOracle} from "../mocks/MockStakingOracle.sol";
import "../../src/core/NativeStakingVault.sol";
import "../../src/core/NativeStakingManager.sol";
import "../../src/core/APRStaking.sol";

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
    MockStakingOracle public oracle;
    MockERC20 public xfi;
    NativeStakingVault public vault;
    NativeStakingManager public manager;
    APRStaking public aprContract;
    
    // Test accounts
    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public compounder = address(0x4);
    
    // Test constants
    string public constant VALIDATOR_ID = "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant APY = 100 * 1e16; // 100% with 18 decimals
    uint256 public constant UNBONDING_PERIOD = 14 days;
    
    function setUp() public {
        console.log("Starting E2E test setup");
        
        vm.startPrank(admin);
        
        // Deploy mock contracts
        xfi = new MockERC20("XFI", "XFI", 18);
        oracle = new MockStakingOracle();
        
        // Setup oracle values
        oracle.setCurrentAPY(APY);
        oracle.setCurrentAPR(1000); // 10% APR
        oracle.setUnbondingPeriod(UNBONDING_PERIOD);
        oracle.setXfiPrice(1e18); // Set XFI price to 1 USD
        oracle.setMpxPrice(1e18); // Set MPX price to 1 USD
        
        // Deploy APR contract
        aprContract = new APRStaking();
        aprContract.initialize(
            address(oracle),
            address(xfi)
        );
        
        // Deploy vault
        vault = new NativeStakingVault();
        vault.initialize(
            address(xfi),
            address(oracle),
            "XFI Staking Vault",
            "xXFI"
        );
        
        // Deploy manager
        manager = new NativeStakingManager();
        manager.initialize(
            address(aprContract),
            address(vault),
            address(xfi),
            address(oracle),
            false, // Do not enforce minimum amounts for tests
            0, // No initial freeze time
            50 ether, // Min stake amount
            10 ether, // Min unstake amount
            1 ether // Min reward claim amount
        );
        
        // Setup roles
        vault.grantRole(vault.STAKING_MANAGER_ROLE(), address(manager));
        vault.grantRole(vault.COMPOUNDER_ROLE(), compounder);
        aprContract.grantRole(aprContract.DEFAULT_ADMIN_ROLE(), admin);
        aprContract.grantRole(aprContract.DEFAULT_ADMIN_ROLE(), address(manager));
        manager.grantRole(manager.DEFAULT_ADMIN_ROLE(), admin);
        manager.grantRole(manager.FULFILLER_ROLE(), admin);
        
        // Give users some XFI
        xfi.mint(user1, INITIAL_BALANCE);
        xfi.mint(user2, INITIAL_BALANCE);
        xfi.mint(compounder, INITIAL_BALANCE);
        xfi.mint(address(manager), INITIAL_BALANCE * 2); // For rewards
        
        vm.stopPrank();
        
        console.log("E2E test setup completed");
    }
    
    function testFullStakingFlow() public {
        uint256 stakeAmount = 100 ether;

        // User1 stakes XFI through manager
        vm.startPrank(user1);
        xfi.approve(address(manager), stakeAmount);
        uint256 shares = manager.stakeAPY(stakeAmount);
        assertGt(shares, 0, "User should receive vault shares");
        assertEq(vault.totalAssets(), stakeAmount, "Vault should hold XFI");
        vm.stopPrank();

        // Record initial state
        uint256 initialPrice = vault.convertToAssets(1 ether);
        
        // Fast forward some time
        vm.warp(block.timestamp + 30 days);
        
        // Add rewards to the vault directly
        uint256 rewardAmount = 10 ether;
        xfi.mint(address(vault), rewardAmount);
        
        // Check that the price per share has increased
        uint256 newPrice = vault.convertToAssets(1 ether);
        assertGt(newPrice, initialPrice, "Price per share should increase after rewards");
        
        // Calculate what the full stakeAmount should now be worth
        uint256 expectedNewValue = vault.convertToAssets(shares);
        assertGt(expectedNewValue, stakeAmount, "Stake value should have increased");
    }
    
    function testCompoundingRewards() public {
        uint256 stakeAmount = 1000 ether;
        uint256 rewardAmount = 100 ether;
        
        // User1 stakes XFI
        vm.startPrank(user1);
        xfi.approve(address(manager), stakeAmount);
        manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        // Add rewards
        vm.startPrank(compounder);
        xfi.mint(compounder, rewardAmount);
        xfi.approve(address(vault), rewardAmount);
        vault.compoundRewards(rewardAmount);
        vm.stopPrank();
        
        // Check total assets
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, stakeAmount + rewardAmount, "Total assets should include rewards");
        
        // User1 withdraws everything
        vm.startPrank(admin);
        vault.setMaxLiquidityPercent(10000); // 100% for testing
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 shares = vault.balanceOf(user1);
        uint256 assets = vault.redeem(shares, user1, user1);
        vm.stopPrank();
        
        assertGt(assets, stakeAmount, "Should get more than original stake due to rewards");
    }
    
    function testMultipleUsersWithRewards() public {
        uint256 stakeAmount = 1000 ether;
        uint256 rewardAmount = 100 ether;
        
        // User1 stakes XFI
        vm.startPrank(user1);
        xfi.approve(address(manager), stakeAmount);
        uint256 shares1 = manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        // User2 stakes XFI
        vm.startPrank(user2);
        xfi.approve(address(manager), stakeAmount);
        uint256 shares2 = manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        // Add rewards
        vm.startPrank(compounder);
        xfi.mint(compounder, rewardAmount);
        xfi.approve(address(vault), rewardAmount);
        vault.compoundRewards(rewardAmount);
        vm.stopPrank();
        
        // Check total assets
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, stakeAmount * 2 + rewardAmount, "Total assets should include both stakes and rewards");
        
        // Both users withdraw everything
        vm.startPrank(admin);
        vault.setMaxLiquidityPercent(10000); // 100% for testing
        vm.stopPrank();
        
        // User1 withdraws
        vm.startPrank(user1);
        uint256 assets1 = vault.redeem(shares1, user1, user1);
        vm.stopPrank();
        
        // User2 withdraws
        vm.startPrank(user2);
        uint256 assets2 = vault.redeem(shares2, user2, user2);
        vm.stopPrank();
        
        // Both users should get their fair share of rewards
        assertGt(assets1, stakeAmount, "User1 should get more than original stake due to rewards");
        assertGt(assets2, stakeAmount, "User2 should get more than original stake due to rewards");
        
        // Allow for small rounding differences (1 wei)
        uint256 diff = assets1 > assets2 ? assets1 - assets2 : assets2 - assets1;
        assertLe(diff, 1, "Both users should get equal rewards (within 1 wei)");
    }
    
    function testClaimRewardsFromMultipleValidators() public {
        // Create a simplified mock test for the validator rewards flow
        uint256 rewardAmount1 = 100 ether;
        uint256 rewardAmount2 = 200 ether;
        string memory validator1 = "validator1";
        string memory validator2 = "validator2";
        
        // Set initial balances and approvals
        xfi.mint(address(this), 10 ether); // Just some token balance for the test contract
        uint256 initialBalance = xfi.balanceOf(address(this));
        
        // Make sure manager has enough tokens to transfer as rewards
        xfi.mint(address(manager), rewardAmount1 + rewardAmount2);
        
        // Mock the oracle calls that the manager will make
        // Setup validator stakes (this is just for the safety check in manager)
        oracle.setValidatorStake(address(this), validator1, 1000 ether);
        oracle.setValidatorStake(address(this), validator2, 1000 ether);
        
        // Setup claimable rewards
        oracle.setUserClaimableRewardsForValidator(address(this), validator1, rewardAmount1);
        oracle.setUserClaimableRewardsForValidator(address(this), validator2, rewardAmount2);
        
        // Claim rewards from the first validator
        vm.startPrank(address(this));
        bytes memory requestId1 = manager.claimRewardsAPRForValidator(validator1, rewardAmount1);
        vm.stopPrank();
        
        // Verify first claim - requestId1 is now bytes, but we're checking the reward amount
        assertEq(xfi.balanceOf(address(this)), initialBalance + rewardAmount1, "Balance should increase by first reward amount");
        
        // Claim rewards from the second validator
        vm.startPrank(address(this));
        bytes memory requestId2 = manager.claimRewardsAPRForValidator(validator2, rewardAmount2);
        vm.stopPrank();
        
        // Verify second claim
        assertEq(xfi.balanceOf(address(this)), initialBalance + rewardAmount1 + rewardAmount2, 
            "Balance should increase by both rewards");
            
        // The requestIds should be of type bytes
        assertTrue(requestId1.length > 0, "Request ID 1 should not be empty");
        assertTrue(requestId2.length > 0, "Request ID 2 should not be empty");
    }
    
    function testClaimAllRewardsAfterMultipleStakes() public {
        // Setup
        string memory validator1 = "mxva123456789";
        string memory validator2 = "mxva987654321";
        uint256 stakeAmount = 1000 ether;
        uint256 rewardAmount1 = 100 ether;
        uint256 rewardAmount2 = 200 ether;
        
        // Mint tokens to this contract
        xfi.mint(address(this), stakeAmount * 2);
        
        // Stake with multiple validators
        vm.startPrank(address(this));
        xfi.approve(address(manager), stakeAmount * 2);
        manager.stakeAPR(stakeAmount, validator1);
        manager.stakeAPR(stakeAmount, validator2);
        vm.stopPrank();
        
        // Set stakings in oracle
        oracle.setValidatorStake(address(this), validator1, stakeAmount);
        oracle.setValidatorStake(address(this), validator2, stakeAmount);
        
        // Set rewards for both validators
        oracle.setUserClaimableRewardsForValidator(address(this), validator1, rewardAmount1);
        oracle.setUserClaimableRewardsForValidator(address(this), validator2, rewardAmount2);
        
        // Set total rewards (should match sum of validator rewards)
        oracle.setUserClaimableRewards(address(this), rewardAmount1 + rewardAmount2);
        
        // Mint reward tokens to the manager
        xfi.mint(address(manager), rewardAmount1 + rewardAmount2);
        
        // Record initial balance
        uint256 initialBalance = xfi.balanceOf(address(this));
        
        // Claim all rewards at once
        vm.startPrank(address(this));
        uint256 claimedAmount = manager.claimRewardsAPR();
        vm.stopPrank();
        
        // Verify
        assertEq(claimedAmount, rewardAmount1 + rewardAmount2, "Incorrect total reward amount claimed");
        assertEq(xfi.balanceOf(address(this)), initialBalance + rewardAmount1 + rewardAmount2, 
            "Total rewards not transferred correctly");
    }
} 