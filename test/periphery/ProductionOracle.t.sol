// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/periphery/ProductionOracle.sol";
import "../utils/MockDIAOracle.sol";

/**
 * @title ProductionOracleTest
 * @dev Test contract for ProductionOracle
 */
contract ProductionOracleTest is Test {
    // Test constants
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    
    // Contracts
    MockDIAOracle public diaOracle;
    ProductionOracle public oracle;
    
    function setUp() public {
        vm.startPrank(ADMIN);
        
        // Deploy DIA Oracle mock
        diaOracle = new MockDIAOracle();
        // Set XFI price to $1 with 8 decimals in the DIA Oracle
        diaOracle.setPrice("XFI/USD", 1e8);
        
        // Deploy Oracle implementation
        ProductionOracle oracleImpl = new ProductionOracle();
        // Initialize the oracle
        oracleImpl.initialize(address(diaOracle));
        
        // Set oracle reference
        oracle = oracleImpl;
        
        // Grant roles
        oracle.grantRole(oracle.ORACLE_UPDATER_ROLE(), ADMIN);
        
        vm.stopPrank();
    }
    
    function testGetXFIPrice() public {
        // Test getting XFI price from DIA Oracle
        (uint256 price, uint256 timestamp) = oracle.getXFIPrice();
        
        // Price should be converted from DIA's 8 decimals to 18 decimals
        assertEq(price, 1 ether, "XFI price should be $1 with 18 decimals");
        assertTrue(timestamp > 0, "Timestamp should be set");
    }
    
    function testGetPrice() public {
        // Test getting XFI price via the getPrice function
        uint256 price = oracle.getPrice("XFI");
        
        // Price should match what we get from getXFIPrice
        assertEq(price, 1 ether, "XFI price should be $1 with 18 decimals");
    }
    
    function testFallbackPrice() public {
        vm.startPrank(ADMIN);
        
        // Set fallback price in the oracle
        oracle.setPrice("XFI", 2 ether); // $2
        
        // Test when DIA price is too old
        uint128 oldTimestamp = uint128(block.timestamp - 2 hours);
        diaOracle.setPriceWithTimestamp("XFI/USD", 1e8, oldTimestamp);
        
        // Get price should now use fallback
        (uint256 price, uint256 timestamp) = oracle.getXFIPrice();
        
        // Price should be the fallback price
        assertEq(price, 2 ether, "XFI price should use fallback price of $2");
        
        vm.stopPrank();
    }
    
    function testConvertXFItoMPX() public {
        vm.startPrank(ADMIN);
        
        // Set XFI price to $1
        diaOracle.setPrice("XFI/USD", 1e8);
        
        vm.stopPrank();
        
        // Convert 10 XFI to MPX
        uint256 mpxAmount = oracle.convertXFItoMPX(10 ether);
        
        // With XFI at $1 and MPX at $0.04, 10 XFI should be 250 MPX
        // 10 * $1 / $0.04 = 250
        assertEq(mpxAmount, 250 ether, "10 XFI should convert to 250 MPX");
    }
    
    function testSetAPR() public {
        vm.startPrank(ADMIN);
        
        // Set APR to 12%
        oracle.setCurrentAPR(12);
        
        vm.stopPrank();
        
        // Get APR
        uint256 apr = oracle.getCurrentAPR();
        
        // APR should be 12% with 18 decimals
        assertEq(apr, 12 * 1e16, "APR should be 12% with 18 decimals");
    }
    
    function testUserClaimableRewards() public {
        vm.startPrank(ADMIN);
        
        // Set claimable rewards for a user
        oracle.setUserClaimableRewards(USER, 100 ether);
        
        vm.stopPrank();
        
        // Get claimable rewards
        uint256 rewards = oracle.getUserClaimableRewards(USER);
        
        // Rewards should be what we set
        assertEq(rewards, 100 ether, "User should have 100 XFI in claimable rewards");
        
        // Clear rewards
        vm.startPrank(ADMIN);
        uint256 cleared = oracle.clearUserClaimableRewards(USER);
        vm.stopPrank();
        
        // Cleared amount should match what we set
        assertEq(cleared, 100 ether, "Cleared rewards should be 100 XFI");
        
        // Rewards after clearing should be 0
        rewards = oracle.getUserClaimableRewards(USER);
        assertEq(rewards, 0, "User should have 0 XFI in claimable rewards after clearing");
    }
    
    function testUnstakingFrozen() public {
        // Initially, unstaking should not be frozen since launch timestamp is the deployment time
        assertFalse(oracle.isUnstakingFrozen(), "Unstaking should not be frozen by default");
        
        vm.startPrank(ADMIN);
        
        // Set launch timestamp to current time
        oracle.setLaunchTimestamp(block.timestamp);
        
        vm.stopPrank();
        
        // Unstaking should now be frozen
        assertTrue(oracle.isUnstakingFrozen(), "Unstaking should be frozen after setting launch timestamp");
        
        // Advance time 31 days
        vm.warp(block.timestamp + 31 days);
        
        // Unstaking should no longer be frozen
        assertFalse(oracle.isUnstakingFrozen(), "Unstaking should not be frozen after 31 days");
    }
    
    function testBatchSetUserClaimableRewards() public {
        address[] memory users = new address[](3);
        users[0] = address(0x100);
        users[1] = address(0x200);
        users[2] = address(0x300);
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;
        
        vm.startPrank(ADMIN);
        
        // Batch set claimable rewards
        oracle.batchSetUserClaimableRewards(users, amounts);
        
        vm.stopPrank();
        
        // Check each user's rewards
        assertEq(oracle.getUserClaimableRewards(users[0]), 100 ether, "User 1 should have 100 XFI in claimable rewards");
        assertEq(oracle.getUserClaimableRewards(users[1]), 200 ether, "User 2 should have 200 XFI in claimable rewards");
        assertEq(oracle.getUserClaimableRewards(users[2]), 300 ether, "User 3 should have 300 XFI in claimable rewards");
    }
} 