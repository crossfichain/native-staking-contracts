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
            address(oracle),
            address(xfi),
            50 ether, // Min stake amount
            10 ether, // Min unstake amount
            false // Do not enforce minimum amounts for tests
        );
        
        // Setup roles
        staking.grantRole(staking.DEFAULT_ADMIN_ROLE(), ADMIN);
        staking.grantRole(staking.STAKING_MANAGER_ROLE(), ADMIN);
        
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
        
        // Capture the requestId emitted from the event
        vm.recordLogs();
        staking.requestUnstake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Find the UnstakeRequested event
        bytes memory requestId;
        for (uint i = 0; i < entries.length; i++) {
            // The event UnstakeRequested has the signature:
            // event UnstakeRequested(address indexed user, uint256 amount, string validator, bytes requestId);
            // The first topic is the event signature hash
            if (entries[i].topics[0] == keccak256("UnstakeRequested(address,uint256,string,bytes)")) {
                // The requestId is in the data portion, but we need to decode it correctly
                // The data contains amount, validator and requestId (non-indexed parameters)
                (uint256 decodedAmount, string memory validator, bytes memory id) = abi.decode(entries[i].data, (uint256, string, bytes));
                requestId = id;
                break;
            }
        }
        
        // Ensure we found a valid requestId
        require(requestId.length > 0, "RequestId not found in events");
        
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);
        
        // Make sure the contract has enough tokens to transfer during claim
        uint256 adminBalanceBefore = xfi.balanceOf(ADMIN);
        
        // Ensure staking contract has exactly the expected amount
        deal(address(xfi), address(staking), INITIAL_BALANCE);
        
        // Claim unstake
        vm.prank(ADMIN);
        uint256 amount = staking.claimUnstake(USER, requestId);
        
        assertEq(amount, INITIAL_BALANCE);
        assertEq(xfi.balanceOf(ADMIN), adminBalanceBefore + INITIAL_BALANCE); // Token is sent to the caller (ADMIN)
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
        
        // For testing purposes, we're using a simple bytes value for the requestId
        bytes memory requestId = abi.encodePacked(
            uint16(0),                // Request type (0 for unstake)
            uint32(block.timestamp),  // Timestamp 
            uint64(uint256(keccak256(abi.encodePacked(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")))), 
            uint32(0)                 // Sequence number
        );
        vm.stopPrank();
        
        // Try to claim before unbonding period
        vm.prank(USER);
        staking.claimUnstake(USER, requestId);
    }
    
    function testFailClaimUnstakeByNonOwner() public {
        // Setup unstake request
        vm.startPrank(ADMIN);
        xfi.approve(address(staking), INITIAL_BALANCE);
        staking.stake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", address(0));
        staking.requestUnstake(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
        
        // For testing purposes, we're using a simple bytes value for the requestId
        bytes memory requestId = abi.encodePacked(
            uint16(0),                // Request type (0 for unstake)
            uint32(block.timestamp),  // Timestamp 
            uint64(uint256(keccak256(abi.encodePacked(USER, INITIAL_BALANCE, "mxvaloper1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")))), 
            uint32(0)                 // Sequence number
        );
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);
        
        // Try to claim as non-admin
        vm.prank(USER);
        vm.expectRevert("AccessControl: account 0x0000000000000000000000000000000000000002 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        staking.claimUnstake(USER, requestId);
    }
} 