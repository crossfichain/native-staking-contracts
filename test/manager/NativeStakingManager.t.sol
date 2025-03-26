// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/NativeStakingManager.sol";
import "../../src/core/NativeStakingVault.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockStakingOracle.sol";

/**
 * @title NativeStakingManagerTest
 * @dev Test contract for the NativeStakingManager
 */
contract NativeStakingManagerTest is Test {
    // Test constants
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    address public constant COMPOUNDER = address(0x3);
    
    // Contracts
    MockERC20 public xfi;
    MockStakingOracle public oracle;
    NativeStakingVault public vault;
    NativeStakingManager public manager;
    
    // Test constants
    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant APY = 1000; // 10% in basis points
    uint256 public constant UNBONDING_PERIOD = 14 days;
    
    function setUp() public {
        vm.startPrank(ADMIN);
        
        // Deploy mock contracts
        xfi = new MockERC20("XFI", "XFI", 18);
        oracle = new MockStakingOracle();
        
        // Setup oracle values
        oracle.setAPY(APY);
        oracle.setUnbondingPeriod(UNBONDING_PERIOD);
        oracle.setPrice(1e18); // Set XFI price to 1 USD
        
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
            address(0), // No APR contract for this test
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
        vault.grantRole(vault.COMPOUNDER_ROLE(), COMPOUNDER);
        
        // Give users some XFI
        xfi.mint(USER, INITIAL_BALANCE);
        xfi.mint(COMPOUNDER, INITIAL_BALANCE);
        
        vm.stopPrank();
    }
    
    function testGetContractAddresses() public {
        assertEq(manager.getAPYContract(), address(vault), "APY contract address should match");
        assertEq(manager.getXFIToken(), address(xfi), "XFI token address should match");
    }
    
    function testStakeAPY() public {
        uint256 stakeAmount = 100 ether;
        
        vm.startPrank(USER);
        xfi.approve(address(manager), stakeAmount);
        uint256 shares = manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        assertGt(shares, 0, "Should receive vault shares");
        assertEq(vault.balanceOf(USER), shares, "User should own the shares");
        assertEq(xfi.balanceOf(address(vault)), stakeAmount, "Vault should hold the XFI");
    }
    
    function testWithdraw() public {
        uint256 stakeAmount = 100 ether;
        
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
        bool success = vault.compound();
        vm.stopPrank();
        
        assertTrue(success, "Compound should succeed");
        
        // User requests withdrawal
        vm.startPrank(USER);
        uint256 requestId = vault.requestWithdrawal(shares, USER, USER);
        vm.stopPrank();
        
        assertGt(requestId, 0, "Should get valid request ID");
        
        // Fast forward through unbonding period
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);
        
        // User claims withdrawal
        vm.startPrank(USER);
        uint256 assets = vault.claimWithdrawal(requestId);
        vm.stopPrank();
        
        assertGt(assets, 0, "Should get assets back");
        assertEq(xfi.balanceOf(USER), INITIAL_BALANCE - stakeAmount + assets, "User should get XFI back with rewards");
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
        xfi.approve(address(vault), rewardAmount);
        vault.compoundRewards(rewardAmount);
        vm.stopPrank();
        
        // Check total assets
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, stakeAmount + rewardAmount, "Total assets should include rewards");
        
        // User withdraws everything
        vm.startPrank(ADMIN);
        vault.setMaxLiquidityPercent(10000); // 100% for testing
        vm.stopPrank();
        
        vm.startPrank(USER);
        uint256 shares = vault.balanceOf(USER);
        uint256 assets = vault.redeem(shares, USER, USER);
        vm.stopPrank();
        
        assertGt(assets, stakeAmount, "Should get more than original stake due to rewards");
    }
} 