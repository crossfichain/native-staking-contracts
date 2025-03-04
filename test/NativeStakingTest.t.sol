// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/core/NativeStaking.sol";
import "../src/core/NativeStakingVault.sol";
import "../src/core/NativeStakingManager.sol";
import "../src/periphery/CrossFiOracle.sol";
import "../src/periphery/WXFI.sol";
import "../src/deployment/DeploymentCoordinator.sol";

contract NativeStakingTest is Test {
    // Contracts
    DeploymentCoordinator coordinator;
    CrossFiOracle oracle;
    NativeStaking aprStaking;
    NativeStakingVault apyStaking;
    NativeStakingManager manager;
    WXFI wxfi;
    
    // Addresses
    address admin = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    
    // Test values
    uint256 initialBalance = 1000 ether;
    string validator1 = "validator1";
    string validator2 = "validator2";
    
    function setUp() public {
        // Deploy the system using the coordinator
        coordinator = new DeploymentCoordinator();
        address managerProxy = coordinator.deploySystem(admin);
        
        // Get the deployed contracts
        oracle = CrossFiOracle(coordinator.oracleProxy());
        aprStaking = NativeStaking(coordinator.nativeStakingProxy());
        apyStaking = NativeStakingVault(coordinator.nativeStakingVaultProxy());
        manager = NativeStakingManager(managerProxy);
        wxfi = WXFI(coordinator.wxfi());
        
        // Configure the Oracle
        vm.startPrank(admin);
        oracle.setPrice(1 ether);  // 1 XFI = 1 USD (for simplicity)
        oracle.setValidator(validator1, true, 10);  // 10% APR
        oracle.setValidator(validator2, true, 12);  // 12% APR
        oracle.setTotalStakedXFI(1000000 ether);
        oracle.setCurrentAPY(8);  // 8% APY for the vault
        oracle.setUnbondingPeriod(14 days);
        vm.stopPrank();
        
        // Fund test users with ETH and mint WXFI
        vm.deal(user1, initialBalance);
        vm.deal(user2, initialBalance);
        
        // User 1 wraps some XFI
        vm.prank(user1);
        wxfi.deposit{value: 100 ether}();
        
        // User 2 wraps some XFI
        vm.prank(user2);
        wxfi.deposit{value: 100 ether}();
    }
    
    function testDirectStaking() public {
        uint256 stakeAmount = 50 ether;
        
        // Approve and stake
        vm.startPrank(user1);
        wxfi.approve(address(manager), stakeAmount);
        manager.stakeAPR(stakeAmount, validator1);
        vm.stopPrank();
        
        // Check stake
        (uint256 amount, string memory validatorId, uint256 timestamp) = aprStaking.getUserStake(user1, 0);
        assertEq(amount, stakeAmount);
        assertEq(validatorId, validator1);
        assertGt(timestamp, 0);
        
        // Fast forward 30 days
        skip(30 days);
        
        // Calculate expected rewards (simplified)
        uint256 expectedRewards = stakeAmount * 10 / 100 * 30 / 365;
        
        // Check claimable rewards
        uint256 claimable = aprStaking.getUnclaimedRewards(user1);
        assertApproxEqRel(claimable, expectedRewards, 0.01e18);  // Within 1% due to rounding
        
        // Claim rewards
        vm.prank(user1);
        manager.claimAPRRewards();
        
        // Check WXFI balance increased
        assertApproxEqRel(wxfi.balanceOf(user1), 50 ether + expectedRewards, 0.01e18);
    }
    
    function testCompoundStaking() public {
        uint256 stakeAmount = 50 ether;
        
        // Approve and stake
        vm.startPrank(user2);
        wxfi.approve(address(manager), stakeAmount);
        manager.stakeAPY(stakeAmount);
        vm.stopPrank();
        
        // Check share balance
        uint256 initialShares = apyStaking.balanceOf(user2);
        assertGt(initialShares, 0);
        
        // Fast forward 30 days
        skip(30 days);
        
        // Simulate compound
        vm.prank(admin);
        apyStaking.compound();
        
        // Value of shares should have increased
        uint256 valueAfterCompound = apyStaking.convertToAssets(initialShares);
        assertGt(valueAfterCompound, stakeAmount);
        
        // Request withdrawal
        vm.prank(user2);
        manager.unstakeAPY(initialShares);
        
        // Fast forward through unbonding period
        skip(14 days);
        
        // Claim unstaked tokens
        uint256 balanceBefore = wxfi.balanceOf(user2);
        vm.prank(user2);
        manager.claimUnstakeAPY();
        uint256 balanceAfter = wxfi.balanceOf(user2);
        
        // Should receive more than initial stake due to compounding
        assertGt(balanceAfter - balanceBefore, stakeAmount);
    }
} 