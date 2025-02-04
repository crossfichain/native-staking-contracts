// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NativeStaking.base.t.sol";

contract NativeStakingFuzzTest is NativeStakingBaseTest {
    // Bound multipliers for fuzzing
    uint256 constant BOUND_MIN = 1;
    uint256 constant BOUND_MAX = 1000;

    function testFuzz_Stake(uint256 amount) public {
        amount = bound(amount, MIN_STAKE, INITIAL_BALANCE);
        
        vm.startPrank(alice);
        staking.stake{value: amount}();
        
        (uint256 lockedAmount, uint256 collateral, uint256 shares, ) = staking.getStakingPosition(alice);
        assertEq(lockedAmount, amount, "Incorrect locked amount");
        assertEq(shares, amount, "Incorrect shares amount");
        assertTrue(collateral > 0, "Collateral should be positive");
    }

    function testFuzz_MultipleStakes(
        uint256[] calldata amounts,
        address[] calldata users
    ) public {
        vm.assume(amounts.length > 0 && amounts.length == users.length);
        vm.assume(amounts.length <= 10); // Reasonable bound for test performance

        uint256 totalStaked;
        
        for(uint256 i = 0; i < amounts.length; i++) {
            address user = address(uint160(uint256(keccak256(abi.encode(users[i])))));
            vm.assume(user != address(0));
            
            uint256 amount = bound(amounts[i], MIN_STAKE, INITIAL_BALANCE);
            vm.deal(user, amount);
            
            vm.prank(user);
            staking.stake{value: amount}();
            
            totalStaked += amount;
        }
        
        assertEq(staking.totalStaked(), totalStaked, "Total staked mismatch");
    }

    function testFuzz_StakeUnstakeSequence(
        uint256[] calldata stakeAmounts,
        uint256[] calldata unstakeAmounts
    ) public {
        vm.assume(stakeAmounts.length > 0 && stakeAmounts.length == unstakeAmounts.length);
        vm.assume(stakeAmounts.length <= 5); // Reasonable bound

        uint256 totalUserStake;
        vm.startPrank(alice);

        for(uint256 i = 0; i < stakeAmounts.length; i++) {
            uint256 stakeAmount = bound(stakeAmounts[i], MIN_STAKE, INITIAL_BALANCE - totalUserStake);
            staking.stake{value: stakeAmount}();
            totalUserStake += stakeAmount;

            uint256 unstakeAmount = bound(unstakeAmounts[i], 0, totalUserStake);
            if(unstakeAmount > 0) {
                staking.unstake(unstakeAmount);
                totalUserStake -= unstakeAmount;
            }
        }
        vm.stopPrank();
    }

    function testFuzz_RewardDistribution(
        uint256[] calldata stakes,
        uint256[] calldata rewards
    ) public {
        vm.assume(stakes.length > 0 && stakes.length <= 5);
        vm.assume(rewards.length > 0 && rewards.length <= 5);

        // Setup initial stakes
        for(uint256 i = 0; i < stakes.length; i++) {
            uint256 amount = bound(stakes[i], MIN_STAKE, INITIAL_BALANCE);
            vm.deal(alice, amount);
            vm.prank(alice);
            staking.stake{value: amount}();
        }

        // Distribute rewards
        vm.startPrank(operator);
        for(uint256 i = 0; i < rewards.length; i++) {
            vm.warp(block.timestamp + COMPOUND_PERIOD);
            uint256 rewardAmount = bound(rewards[i], 0.1 ether, 10 ether);
            staking.distributeRewards(rewardAmount, 0);
        }
        vm.stopPrank();
    }

    function testFuzz_ConversionRates(uint256 price) public {
        price = bound(price, 0.1 ether, 1000 ether);
        oracle.setPrice("XFI/USD", price);

        uint256 amount = 100 ether;
        uint256 delegatedAmount = staking.exposed_calculateDelegatedAmount(amount);
        assertTrue(delegatedAmount > 0, "Delegated amount should be positive");
    }

    function testFuzz_SlashingWithDifferentRates(uint256 stakeAmount, uint256 slashAmount) public {
        stakeAmount = bound(stakeAmount, MIN_STAKE, INITIAL_BALANCE);
        slashAmount = bound(slashAmount, 0.1 ether, stakeAmount);

        vm.prank(alice);
        staking.stake{value: stakeAmount}();

        vm.prank(operator);
        staking.handleSlashing(slashAmount, block.timestamp);
        assertTrue(staking.slashingActive());
    }

    function testFuzz_CompoundingWithDifferentPeriods(
        uint256[] calldata stakeTimes,
        uint256[] calldata rewardAmounts
    ) public {
        vm.assume(stakeTimes.length > 0 && stakeTimes.length == rewardAmounts.length);
        vm.assume(stakeTimes.length <= 5);

        uint256 currentTime = block.timestamp;
        uint256 totalRewards;

        for(uint256 i = 0; i < stakeTimes.length; i++) {
            // Bound time increments between 2-4 weeks
            uint256 timeIncrement = bound(stakeTimes[i], COMPOUND_PERIOD, COMPOUND_PERIOD * 2);
            currentTime += timeIncrement;
            vm.warp(currentTime);

            uint256 rewardAmount = bound(rewardAmounts[i], 0.1 ether, 5 ether);
            vm.prank(operator);
            staking.distributeRewards(rewardAmount, 0);
            totalRewards += rewardAmount;
        }

        assertEq(staking.rewardPool(), totalRewards, "Incorrect reward pool");
    }

    function testFuzz_MultiUserRewardDistribution(
        uint256[] calldata userStakes,
        uint256 rewardAmount
    ) public {
        vm.assume(userStakes.length > 0 && userStakes.length <= 5);
        
        address[] memory users = new address[](userStakes.length);
        uint256 totalStaked;

        // Setup multiple users with different stakes
        for(uint256 i = 0; i < userStakes.length; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encode(i)))));
            uint256 stakeAmount = bound(userStakes[i], MIN_STAKE, INITIAL_BALANCE);
            
            vm.deal(users[i], stakeAmount);
            vm.prank(users[i]);
            staking.stake{value: stakeAmount}();
            
            totalStaked += stakeAmount;
        }

        // Distribute rewards
        vm.warp(block.timestamp + COMPOUND_PERIOD);
        rewardAmount = bound(rewardAmount, 0.1 ether, 10 ether);
        
        vm.prank(operator);
        staking.distributeRewards(rewardAmount, 0);

        // Verify rewards for each user
        for(uint256 i = 0; i < users.length; i++) {
            (, , , uint256 rewards) = staking.getStakingPosition(users[i]);
            assertTrue(rewards > 0, "User should have rewards");
        }
    }

    function testFuzz_PriceImpactOnDelegation(
        uint256[] calldata prices,
        uint256[] calldata stakes
    ) public {
        vm.assume(prices.length > 0 && prices.length == stakes.length);
        vm.assume(prices.length <= 5);

        for(uint256 i = 0; i < prices.length; i++) {
            uint256 price = bound(prices[i], 0.1 ether, 1000 ether);
            uint256 stakeAmount = bound(stakes[i], MIN_STAKE, INITIAL_BALANCE);

            oracle.setPrice("XFI/USD", price);
            
            vm.deal(alice, stakeAmount);
            vm.prank(alice);
            staking.stake{value: stakeAmount}();

            (,uint256 collateral,,) = staking.getStakingPosition(alice);
            assertTrue(collateral > 0, "Collateral should be positive");
        }
    }

    function testFuzz_StressTestWithRandomActions(
        bytes32[] calldata seeds
    ) public {
        vm.assume(seeds.length > 0 && seeds.length <= 20);

        for(uint256 i = 0; i < seeds.length; i++) {
            // Use seed to determine action
            uint256 action = uint256(seeds[i]) % 4;
            
            if(action == 0) {
                // Stake
                uint256 amount = bound(uint256(keccak256(abi.encode(seeds[i], "stake"))), 
                    MIN_STAKE, 
                    INITIAL_BALANCE
                );
                vm.deal(alice, amount);
                vm.prank(alice);
                staking.stake{value: amount}();
            } else if(action == 1) {
                // Unstake
                (uint256 staked, , ,) = staking.getStakingPosition(alice);
                if(staked > 0) {
                    uint256 amount = bound(uint256(keccak256(abi.encode(seeds[i], "unstake"))), 
                        0, 
                        staked
                    );
                    vm.prank(alice);
                    staking.unstake(amount);
                }
            } else if(action == 2) {
                // Distribute rewards
                vm.warp(block.timestamp + COMPOUND_PERIOD);
                uint256 amount = bound(uint256(keccak256(abi.encode(seeds[i], "reward"))), 
                    0.1 ether, 
                    5 ether
                );
                vm.prank(operator);
                staking.distributeRewards(amount, 0);
            } else {
                // Update price
                uint256 price = bound(uint256(keccak256(abi.encode(seeds[i], "price"))), 
                    0.1 ether, 
                    1000 ether
                );
                oracle.setPrice("XFI/USD", price);
            }
        }
    }
} 