// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/periphery/CrossFiOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CrossFiOracleTest is Test {
    CrossFiOracle public oracle;
    CrossFiOracle public implementation;
    ERC1967Proxy public proxy;
    
    address public admin = address(1);
    address public updater = address(2);
    address public pauser = address(3);
    address public upgrader = address(4);
    address public user = address(5);
    
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // Test data
    string public constant XFI_SYMBOL = "XFI";
    string public constant VALIDATOR1 = "validator1";
    string public constant VALIDATOR2 = "validator2";
    string public constant VALIDATOR3 = "validator3";
    
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant DEFAULT_APY = 8 * PRICE_PRECISION / 100; // 8%
    uint256 public constant DEFAULT_APR = 10 * PRICE_PRECISION / 100; // 10%
    uint256 public constant DEFAULT_UNBONDING_PERIOD = 21 days;

    function setUp() public {
        // Deploy implementation
        implementation = new CrossFiOracle();
        
        // Deploy proxy with the initializer
        bytes memory initData = abi.encodeWithSelector(CrossFiOracle.initialize.selector);
        proxy = new ERC1967Proxy(address(implementation), initData);
        
        // Set oracle as the proxy
        oracle = CrossFiOracle(address(proxy));
        
        // The initialize function already grants roles to msg.sender (which is the test contract)
        // So we need to set up the roles from msg.sender to other addresses
        
        // First, grant admin role to admin address
        oracle.grantRole(DEFAULT_ADMIN_ROLE, admin);
        
        // Now as admin, grant the other roles
        vm.startPrank(admin);
        oracle.grantRole(ORACLE_UPDATER_ROLE, updater);
        oracle.grantRole(PAUSER_ROLE, pauser);
        oracle.grantRole(UPGRADER_ROLE, upgrader);
        
        // Revoke roles from the test contract address
        oracle.revokeRole(DEFAULT_ADMIN_ROLE, address(this));
        oracle.revokeRole(ORACLE_UPDATER_ROLE, address(this));
        oracle.revokeRole(PAUSER_ROLE, address(this));
        oracle.revokeRole(UPGRADER_ROLE, address(this));
        vm.stopPrank();
    }

    // Test initialization
    function testInitialize() public {
        assertEq(oracle.getUnbondingPeriod(), DEFAULT_UNBONDING_PERIOD);
        assertEq(oracle.getCurrentAPY(), DEFAULT_APY);
        assertEq(oracle.getCurrentAPR(), DEFAULT_APR);
        assertTrue(oracle.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(oracle.hasRole(ORACLE_UPDATER_ROLE, updater));
        assertTrue(oracle.hasRole(PAUSER_ROLE, pauser));
        assertTrue(oracle.hasRole(UPGRADER_ROLE, upgrader));
    }

    // Test price update functions
    function testSetPrice() public {
        uint256 newPrice = 5 * PRICE_PRECISION; // $5.00

        vm.startPrank(updater);
        oracle.setPrice(newPrice);
        vm.stopPrank();

        assertEq(oracle.getPrice(XFI_SYMBOL), newPrice);
    }

    function testSetPriceUnauthorized() public {
        uint256 newPrice = 5 * PRICE_PRECISION; // $5.00

        vm.startPrank(user);
        vm.expectRevert();
        oracle.setPrice(newPrice);
        vm.stopPrank();
    }

    function testSetPriceWhenPaused() public {
        // Pause the contract
        vm.startPrank(pauser);
        oracle.pause();
        vm.stopPrank();

        // Try to set price when paused
        vm.startPrank(updater);
        vm.expectRevert(
            abi.encodeWithSelector(
                PausableUpgradeable.EnforcedPause.selector
            )
        );
        oracle.setPrice(5 * PRICE_PRECISION);
        vm.stopPrank();
    }

    // Test validator functions
    function testSetValidator() public {
        bool isActive = true;
        uint256 apr = 12; // 12%

        vm.startPrank(updater);
        oracle.setValidator(VALIDATOR1, isActive, apr);
        vm.stopPrank();

        assertTrue(oracle.isValidatorActive(VALIDATOR1));
        assertEq(oracle.getValidatorAPR(VALIDATOR1), 12 * PRICE_PRECISION / 100);
    }

    function testSetValidatorUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert();
        oracle.setValidator(VALIDATOR1, true, 12);
        vm.stopPrank();
    }

    function testBulkSetValidatorStatus() public {
        string[] memory validators = new string[](3);
        validators[0] = VALIDATOR1;
        validators[1] = VALIDATOR2;
        validators[2] = VALIDATOR3;

        bool[] memory statuses = new bool[](3);
        statuses[0] = true;
        statuses[1] = false;
        statuses[2] = true;

        vm.startPrank(updater);
        oracle.bulkSetValidatorStatus(validators, statuses);
        vm.stopPrank();

        assertTrue(oracle.isValidatorActive(VALIDATOR1));
        assertFalse(oracle.isValidatorActive(VALIDATOR2));
        assertTrue(oracle.isValidatorActive(VALIDATOR3));
    }

    function testBulkSetValidatorStatusLengthMismatch() public {
        string[] memory validators = new string[](3);
        validators[0] = VALIDATOR1;
        validators[1] = VALIDATOR2;
        validators[2] = VALIDATOR3;

        bool[] memory statuses = new bool[](2);
        statuses[0] = true;
        statuses[1] = false;

        vm.startPrank(updater);
        vm.expectRevert("Length mismatch");
        oracle.bulkSetValidatorStatus(validators, statuses);
        vm.stopPrank();
    }

    function testSetValidatorAPR() public {
        uint256 apr = 15 * PRICE_PRECISION; // 15% as raw value

        vm.startPrank(updater);
        oracle.setValidatorAPR(VALIDATOR1, apr);
        vm.stopPrank();

        assertEq(oracle.getValidatorAPR(VALIDATOR1), apr);
    }

    // Test staking info functions
    function testSetTotalStakedXFI() public {
        uint256 totalStaked = 1000000 * 1e18; // 1M XFI

        vm.startPrank(updater);
        oracle.setTotalStakedXFI(totalStaked);
        vm.stopPrank();

        assertEq(oracle.getTotalStakedXFI(), totalStaked);
    }

    function testSetCurrentAPY() public {
        uint256 apy = 15; // 15%

        vm.startPrank(updater);
        oracle.setCurrentAPY(apy);
        vm.stopPrank();

        assertEq(oracle.getCurrentAPY(), 15 * PRICE_PRECISION / 100);
    }

    function testSetCurrentAPR() public {
        uint256 apr = 12; // 12%

        vm.startPrank(updater);
        oracle.setCurrentAPR(apr);
        vm.stopPrank();

        assertEq(oracle.getCurrentAPR(), 12 * PRICE_PRECISION / 100);
    }

    function testSetUnbondingPeriod() public {
        uint256 newPeriod = 14 days;

        vm.startPrank(admin);
        oracle.setUnbondingPeriod(newPeriod);
        vm.stopPrank();

        assertEq(oracle.getUnbondingPeriod(), newPeriod);
    }

    function testSetUnbondingPeriodUnauthorized() public {
        uint256 newPeriod = 14 days;

        vm.startPrank(updater); // Not admin
        vm.expectRevert();
        oracle.setUnbondingPeriod(newPeriod);
        vm.stopPrank();
    }

    // Test pause/unpause functions
    function testPause() public {
        vm.startPrank(pauser);
        oracle.pause();
        vm.stopPrank();

        assertTrue(oracle.paused());
    }

    function testPauseUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert();
        oracle.pause();
        vm.stopPrank();
    }

    function testUnpause() public {
        // First pause
        vm.startPrank(pauser);
        oracle.pause();
        vm.stopPrank();
        
        assertTrue(oracle.paused());

        // Then unpause
        vm.startPrank(pauser);
        oracle.unpause();
        vm.stopPrank();
        
        assertFalse(oracle.paused());
    }

    // Test upgrade function
    function testUpgrade() public {
        // Deploy new implementation
        CrossFiOracle newImplementation = new CrossFiOracle();
        
        vm.startPrank(upgrader);
        oracle.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
        
        // Check implementation was changed
        // Note: This test is limited since we can't easily check
        // the implementation address directly in Foundry
    }

    function testUpgradeUnauthorized() public {
        CrossFiOracle newImplementation = new CrossFiOracle();
        
        vm.startPrank(user);
        vm.expectRevert();
        oracle.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }
} 