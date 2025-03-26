// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/APRStaking.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockStakingOracle.sol";

contract APRStakingTest is Test {
    // Test constants
    address public constant ADMIN = address(0x1);
    address public constant USER = address(0x2);
    address public constant MANAGER = address(0x3);
    
    // Contracts
    MockERC20 public xfi;
    MockStakingOracle public oracle;
    APRStaking public staking;
    
    // Test constants
    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant STAKE_AMOUNT = 100 ether;
    uint256 public constant UNBONDING_PERIOD = 7 days;
    string public constant VALIDATOR = "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    
    function setUp() public {
        // Deploy mock contracts
        xfi = new MockERC20("XFI", "XFI", 18);
        oracle = new MockStakingOracle();
        
        // Deploy staking contract
        staking = new APRStaking();
        
        // Initialize staking with admin as msg.sender
        vm.startPrank(ADMIN);
        staking.initialize(address(oracle), address(xfi));
        vm.stopPrank();
        
        // Setup initial balances
        xfi.mint(MANAGER, INITIAL_BALANCE);
        xfi.mint(USER, INITIAL_BALANCE);
        
        // Setup oracle values
        oracle.setUnbondingPeriod(UNBONDING_PERIOD);
        oracle.setPrice(1e18); // Set XFI price to 1 USD
    }
    
    function testInitialization() public {
        assertEq(address(staking.oracle()), address(oracle));
        assertEq(staking.stakingToken(), address(xfi));
    }
    
    function testStake() public {
        vm.startPrank(MANAGER);
        xfi.approve(address(staking), STAKE_AMOUNT);
        bool success = staking.stake(USER, STAKE_AMOUNT, VALIDATOR, address(xfi));
        vm.stopPrank();
        
        assertTrue(success);
        assertEq(staking.getTotalStaked(USER), STAKE_AMOUNT);
        assertEq(staking.getValidatorStake(USER, VALIDATOR), STAKE_AMOUNT);
        
        string[] memory validators = staking.getUserValidators(USER);
        assertEq(validators.length, 1);
        assertEq(validators[0], VALIDATOR);
    }
    
    function testRequestUnstake() public {
        // First stake
        vm.startPrank(MANAGER);
        xfi.approve(address(staking), STAKE_AMOUNT);
        staking.stake(USER, STAKE_AMOUNT, VALIDATOR, address(xfi));
        
        // Request unstake
        staking.requestUnstake(USER, STAKE_AMOUNT, VALIDATOR);
        vm.stopPrank();
        
        assertEq(staking.getTotalStaked(USER), 0);
        assertEq(staking.getValidatorStake(USER, VALIDATOR), 0);
        
        string[] memory validators = staking.getUserValidators(USER);
        assertEq(validators.length, 0);
    }
    
    function testClaimUnstake() public {
        // Setup unstake request
        vm.startPrank(MANAGER);
        xfi.approve(address(staking), STAKE_AMOUNT);
        staking.stake(USER, STAKE_AMOUNT, VALIDATOR, address(xfi));
        staking.requestUnstake(USER, STAKE_AMOUNT, VALIDATOR);
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);
        
        // Claim unstake
        vm.prank(MANAGER);
        uint256 amount = staking.claimUnstake(USER, 0);
        
        assertEq(amount, STAKE_AMOUNT);
        assertEq(xfi.balanceOf(USER), INITIAL_BALANCE);
    }
    
    function testClaimRewards() public {
        // Setup stake
        vm.startPrank(MANAGER);
        xfi.approve(address(staking), STAKE_AMOUNT);
        staking.stake(USER, STAKE_AMOUNT, VALIDATOR, address(xfi));
        
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
        
        vm.startPrank(MANAGER);
        xfi.approve(address(staking), STAKE_AMOUNT);
        staking.stake(USER, STAKE_AMOUNT, VALIDATOR, invalidToken);
    }
    
    function testFailSetStakingTokenByNonAdmin() public {
        address newToken = address(0x4);
        
        vm.prank(USER);
        staking.setStakingToken(newToken);
    }
    
    function testFailClaimUnstakeBeforeUnbonding() public {
        // Setup unstake request
        vm.startPrank(MANAGER);
        xfi.approve(address(staking), STAKE_AMOUNT);
        staking.stake(USER, STAKE_AMOUNT, VALIDATOR, address(xfi));
        staking.requestUnstake(USER, STAKE_AMOUNT, VALIDATOR);
        vm.stopPrank();
        
        // Try to claim before unbonding period
        vm.prank(USER);
        staking.claimUnstake(USER, 0);
    }
    
    function testFailClaimUnstakeByNonOwner() public {
        // Setup unstake request
        vm.startPrank(MANAGER);
        xfi.approve(address(staking), STAKE_AMOUNT);
        staking.stake(USER, STAKE_AMOUNT, VALIDATOR, address(xfi));
        staking.requestUnstake(USER, STAKE_AMOUNT, VALIDATOR);
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);
        
        // Try to claim as non-manager
        vm.prank(USER);
        vm.expectRevert("AccessControl: account 0x0000000000000000000000000000000000000002 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        staking.claimUnstake(USER, 0);
    }
} 