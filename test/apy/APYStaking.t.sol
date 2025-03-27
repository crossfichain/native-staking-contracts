// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/NativeStakingVault.sol";
import "../../src/core/NativeStakingManager.sol";
import "../../src/interfaces/IOracle.sol";
import "../mocks/MockERC20.sol";
import {MockStakingOracle} from "../mocks/MockStakingOracle.sol";

/**
 * @title APYStakingTest
 * @dev Test contract for the APY Staking functionality
 */
contract APYStakingTest is Test {
    // Test constants
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    address public constant COMPOUNDER = address(0x3);
    
    // Contracts
    MockERC20 public xfi;
    MockERC20 public wxfi;
    IOracle public oracle;
    NativeStakingVault public vault;
    NativeStakingManager public manager;
    
    // Test constants
    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant APY = 10 * 1e16; // 10% with 18 decimals
    uint256 public constant UNBONDING_PERIOD = 14 days;
    
    function setUp() public {
        vm.startPrank(ADMIN);
        
        // Deploy mock contracts
        xfi = new MockERC20("XFI", "XFI", 18);
        wxfi = new MockERC20("WXFI", "WXFI", 18);
        oracle = IOracle(address(new MockStakingOracle()));
        
        // Setup oracle values
        MockStakingOracle(address(oracle)).setCurrentAPY(APY);
        MockStakingOracle(address(oracle)).setUnbondingPeriod(UNBONDING_PERIOD);
        MockStakingOracle(address(oracle)).setXfiPrice(1e18); // Set XFI price to 1 USD
        MockStakingOracle(address(oracle)).setTotalStakedXFI(INITIAL_BALANCE); // Set initial total staked
        MockStakingOracle(address(oracle)).setMpxPrice(4 * 1e16); // Set MPX price to $0.04
        
        // Deploy vault
        vault = new NativeStakingVault();
        vault.initialize(
            address(wxfi),
            address(oracle),
            "XFI Staking Vault",
            "xXFI"
        );
        
        // Deploy manager
        manager = new NativeStakingManager();
        manager.initialize(
            address(0), // No APR contract for this test
            address(vault),
            address(wxfi),
            address(oracle),
            false, // Do not enforce minimum amounts for tests
            0, // No initial freeze time
            50 ether, // Min stake amount
            10 ether, // Min unstake amount
            1 ether // Min reward claim amount
        );
        
        // Setup roles
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(manager));
        vault.grantRole(vault.STAKING_MANAGER_ROLE(), address(manager));
        vault.grantRole(vault.COMPOUNDER_ROLE(), COMPOUNDER);
        
        // Give users some tokens
        wxfi.mint(USER, INITIAL_BALANCE);
        wxfi.mint(COMPOUNDER, INITIAL_BALANCE);
        wxfi.mint(ADMIN, INITIAL_BALANCE);
        
        // Mint initial shares to prevent inflation attacks
        vm.startPrank(ADMIN);
        wxfi.mint(ADMIN, 1 ether);
        wxfi.approve(address(vault), 1 ether);
        vault.deposit(1 ether, ADMIN);
        vm.stopPrank();
        
        // Mint initial balance to manager
        wxfi.mint(address(manager), INITIAL_BALANCE);
        
        // Approve vault to spend manager's WXFI
        vm.startPrank(address(manager));
        wxfi.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }
    
    function testStakeAPY() public {
        uint256 stakeAmount = 100 ether;
        
        // Check initial allowances
        assertEq(wxfi.allowance(address(manager), address(vault)), type(uint256).max, "Manager should approve vault");
        
        vm.startPrank(USER);
        wxfi.approve(address(manager), stakeAmount);
        uint256 shares = manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        assertGt(shares, 0, "Should receive vault shares");
        assertEq(vault.balanceOf(USER), shares, "User should own the shares");
        assertEq(wxfi.balanceOf(address(vault)), stakeAmount + 1 ether, "Vault should hold the WXFI");
        
        // Check allowances after stake
        assertEq(wxfi.allowance(USER, address(manager)), 0, "Manager allowance should be used");
        assertEq(wxfi.allowance(address(manager), address(vault)), type(uint256).max, "Vault allowance should remain max");
    }
    
    function testWithdraw() public {
        uint256 stakeAmount = 100 ether;
        
        // User stakes WXFI
        vm.startPrank(USER);
        wxfi.approve(address(manager), stakeAmount);
        uint256 shares = manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        // Fast forward 6 months and compound rewards
        vm.warp(block.timestamp + 180 days);
        
        // Add rewards
        vm.startPrank(COMPOUNDER);
        uint256 rewardAmount = 10 ether;
        wxfi.mint(address(vault), rewardAmount);
        vault.compound();
        vm.stopPrank();
        
        // Set max liquidity percent to 100% for testing
        vm.startPrank(ADMIN);
        vault.setMaxLiquidityPercent(10000); // 100%
        vm.stopPrank();
        
        // User requests withdrawal
        vm.startPrank(USER);
        uint256 currentShares = vault.balanceOf(USER);
        require(currentShares > 0, "User should have shares");
        vault.approve(address(manager), currentShares); // Approve shares for withdrawal
        uint256 requestId = manager.withdrawAPY(currentShares);
        vm.stopPrank();
        
        assertGt(requestId, 0, "Should get valid request ID");
        
        // Fast forward through unbonding period
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);
        
        // User claims withdrawal
        vm.startPrank(USER);
        uint256 assets = manager.claimWithdrawalAPY(requestId);
        vm.stopPrank();
        
        assertGt(assets, 0, "Should get assets back");
        assertEq(wxfi.balanceOf(USER), INITIAL_BALANCE - stakeAmount + assets, "User should get WXFI back with rewards");
    }
    
    function testCompoundingRewards() public {
        uint256 stakeAmount = 1000 ether;
        uint256 rewardAmount = 100 ether;
        
        // User stakes WXFI
        vm.startPrank(USER);
        wxfi.approve(address(manager), stakeAmount);
        manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        // Add rewards through vault
        vm.startPrank(COMPOUNDER);
        wxfi.mint(address(vault), rewardAmount);
        wxfi.approve(address(vault), rewardAmount);
        vault.compound();
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
        vault.approve(address(manager), shares);
        uint256 requestId = manager.withdrawAPY(shares);
        
        // Fast forward through unbonding period
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);
        
        uint256 assets = manager.claimWithdrawalAPY(requestId);
        vm.stopPrank();
        
        assertGt(assets, stakeAmount, "Should get more than original stake due to rewards");
    }
} 