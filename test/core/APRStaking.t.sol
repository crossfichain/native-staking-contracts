// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/APRStaking.sol";
import "../../src/interfaces/IOracle.sol";
import "../mocks/MockERC20.sol";
import {MockStakingOracle} from "../mocks/MockStakingOracle.sol";

contract APRStakingTest is Test {
    // Constants
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    address public constant TREASURY = address(0x3);
    
    // Contracts
    MockERC20 public xfi;
    IOracle public oracle;
    APRStaking public staking;
    
    // Test constants
    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant APR = 10 * 1e16; // 10% with 18 decimals
    uint256 public constant UNBONDING_PERIOD = 14 days;
    
    function setUp() public {
        vm.startPrank(ADMIN);
        
        // Deploy mock contracts
        xfi = new MockERC20("XFI", "XFI", 18);
        oracle = IOracle(address(new MockStakingOracle()));
        
        // Setup oracle values
        MockStakingOracle(address(oracle)).setCurrentAPR(APR);
        MockStakingOracle(address(oracle)).setUnbondingPeriod(UNBONDING_PERIOD);
        MockStakingOracle(address(oracle)).setXfiPrice(1e18); // Set XFI price to 1 USD
        
        // Deploy staking contract
        staking = new APRStaking();
        staking.initialize(
            address(xfi),
            address(oracle)
        );
        
        // Setup roles
        staking.grantRole(staking.DEFAULT_ADMIN_ROLE(), ADMIN);
        
        // Give users some XFI
        xfi.mint(USER, INITIAL_BALANCE);
        
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertEq(address(staking.oracle()), address(oracle));
        assertEq(staking.stakingToken(), address(xfi));
    }
    
    function testStake() public {
        vm.startPrank(ADMIN);
        xfi.approve(address(staking), INITIAL_BALANCE);
        bool success = staking.stake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", address(0));
        vm.stopPrank();
        
        assertTrue(success);
        assertEq(staking.getTotalStaked(USER), INITIAL_BALANCE);
        assertEq(staking.getValidatorStake(USER, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"), INITIAL_BALANCE);
        
        string[] memory validators = staking.getUserValidators(USER);
        assertEq(validators.length, 1);
        assertEq(validators[0], "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
    }
    
    function testRequestUnstake() public {
        // First stake
        vm.startPrank(ADMIN);
        xfi.approve(address(staking), INITIAL_BALANCE);
        staking.stake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", address(0));
        
        // Request unstake
        staking.requestUnstake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
        vm.stopPrank();
        
        assertEq(staking.getTotalStaked(USER), 0);
        assertEq(staking.getValidatorStake(USER, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"), 0);
        
        string[] memory validators = staking.getUserValidators(USER);
        assertEq(validators.length, 0);
    }
    
    function testClaimUnstake() public {
        // Setup unstake request
        vm.startPrank(ADMIN);
        xfi.approve(address(staking), INITIAL_BALANCE);
        staking.stake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", address(0));
        staking.requestUnstake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);
        
        // Claim unstake
        vm.prank(ADMIN);
        uint256 amount = staking.claimUnstake(USER, 0);
        
        assertEq(amount, INITIAL_BALANCE);
        assertEq(xfi.balanceOf(USER), INITIAL_BALANCE);
    }
    
    function testClaimRewards() public {
        // Setup stake
        vm.startPrank(ADMIN);
        xfi.approve(address(staking), INITIAL_BALANCE);
        staking.stake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", address(0));
        
        // Add some rewards
        uint256 rewardAmount = 10 ether;
        xfi.mint(address(staking), rewardAmount);
        
        // Claim rewards
        staking.claimRewards(USER, rewardAmount);
        vm.stopPrank();
        
        assertEq(xfi.balanceOf(USER), INITIAL_BALANCE + rewardAmount);
    }
    
    function testSetStakingToken() public {
        address newToken = address(0x4);
        
        vm.startPrank(ADMIN);
        staking.setStakingToken(newToken);
        vm.stopPrank();
        
        assertEq(staking.stakingToken(), newToken);
    }
    
    function testFailStakeWithInvalidToken() public {
        address invalidToken = address(0x4);
        
        vm.startPrank(ADMIN);
        xfi.approve(address(staking), INITIAL_BALANCE);
        staking.stake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", invalidToken);
    }
    
    function testFailSetStakingTokenByNonAdmin() public {
        address newToken = address(0x4);
        
        vm.prank(USER);
        staking.setStakingToken(newToken);
    }
    
    function testFailClaimUnstakeBeforeUnbonding() public {
        // Setup unstake request
        vm.startPrank(ADMIN);
        xfi.approve(address(staking), INITIAL_BALANCE);
        staking.stake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", address(0));
        staking.requestUnstake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
        vm.stopPrank();
        
        // Try to claim before unbonding period
        vm.prank(USER);
        staking.claimUnstake(USER, 0);
    }
    
    function testFailClaimUnstakeByNonOwner() public {
        // Setup unstake request
        vm.startPrank(ADMIN);
        xfi.approve(address(staking), INITIAL_BALANCE);
        staking.stake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", address(0));
        staking.requestUnstake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);
        
        // Try to claim as non-admin
        vm.prank(USER);
        vm.expectRevert("AccessControl: account 0x0000000000000000000000000000000000000002 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        staking.claimUnstake(USER, 0);
    }
} 