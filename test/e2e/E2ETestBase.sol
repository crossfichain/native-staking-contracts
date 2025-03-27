// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockWXFI.sol";
import {MockStakingOracle} from "../mocks/MockStakingOracle.sol";
import "../../src/core/NativeStakingVault.sol";
import "../../src/core/ConcreteNativeStakingManager.sol";
import "../../src/core/APRStaking.sol";

/**
 * @title E2ETestBase
 * @dev Base contract for E2E tests with common setup
 */
abstract contract E2ETestBase is Test {
    // System contracts
    MockStakingOracle public oracle;
    MockWXFI public xfi;
    NativeStakingVault public vault;
    ConcreteNativeStakingManager public manager;
    APRStaking public aprContract;
    
    // Test accounts
    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public compounder = address(0x4);
    
    // Test constants
    string public constant VALIDATOR_ID = "mxvaoper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant APY = 100 * 1e16; // 100% with 18 decimals
    uint256 public constant UNBONDING_PERIOD = 14 days;
    
    function setUp() public virtual {
        console.log("Starting E2E test setup");
        
        vm.startPrank(admin);
        
        // Deploy mock contracts
        xfi = new MockWXFI();
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
            address(xfi),
            50 ether, // Min stake amount
            10 ether, // Min unstake amount
            false // Do not enforce minimum amounts for tests
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
        manager = new ConcreteNativeStakingManager();
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
} 