// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BaseTest.t.sol";

contract RewardsEdgeTest is BaseTest {
    uint256 constant STAKE_AMOUNT = 1000 * 1e18;
    uint256 constant REWARD_AMOUNT = 100 * 1e18;

    function setUp() public override {
        super.setUp();
        console2.log("=== Test Setup ===");
    }

    function test_ZeroStakersRewardAddition() public {
        console2.log("\n=== Zero Stakers Reward Test ===");

        // Add rewards when no one has staked
        vm.startPrank(bob);
        pokemind.addRewards(1, 0, REWARD_AMOUNT);
        console2.log("Added rewards to empty pool");
        vm.stopPrank();

        skip(pokemind.EPOCH_DURATION());

        // Now stake and check if rewards are correct
        vm.startPrank(alice);
        pokemind.stake(1, STAKE_AMOUNT);
        console2.log("Alice staked after rewards were added");
        vm.stopPrank();

        uint256 pending = pokemind.pendingReward(1, alice, 0);
        console2.log("Pending rewards:", pending / 1e18);

        // Should not receive past rewards
        assertEq(pending, 0);
    }

    function test_SmallStakeWithLargeRewards() public {
        console2.log("\n=== Tiny Stake Large Rewards Test ===");

        // Stake minimum amount
        vm.startPrank(alice);
        pokemind.stake(1, MIN_STAKE);
        console2.log("Alice staked minimum:", MIN_STAKE / 1e18);
        vm.stopPrank();

        // Add massive rewards
        vm.startPrank(bob);
        uint256 hugeReward = 1_000_000 * 1e18;
        pokemind.addRewards(1, 0, hugeReward);
        console2.log("Added huge rewards:", hugeReward / 1e18);
        vm.stopPrank();

        skip(pokemind.EPOCH_DURATION() / 2);

        uint256 pending = pokemind.pendingReward(1, alice, 0);
        console2.log("Pending rewards mid-epoch:", pending / 1e18);
        assertTrue(pending > 0, "Should accrue rewards despite tiny stake");
    }

    function test_RepeatedSmallStakes() public {
        console2.log("\n=== Repeated Small Stakes Test ===");

        vm.startPrank(alice);
        for (uint256 i = 0; i < 10; i++) {
            pokemind.stake(1, MIN_STAKE);
            console2.log("Stake", i, "added");
        }
        vm.stopPrank();

        // Add rewards
        vm.startPrank(bob);
        pokemind.addRewards(1, 0, REWARD_AMOUNT);
        vm.stopPrank();

        skip(pokemind.EPOCH_DURATION() / 2);

        uint256 pending = pokemind.pendingReward(1, alice, 0);
        console2.log("Pending rewards after multiple stakes:", pending / 1e18);
    }

    function test_MultipleRewardUpdatesPerEpoch() public {
        console2.log("\n=== Multiple Reward Updates Test ===");

        // Setup stake
        vm.startPrank(alice);
        pokemind.stake(1, STAKE_AMOUNT);
        vm.stopPrank();

        // Add rewards multiple times in same epoch
        vm.startPrank(bob);
        for (uint256 i = 0; i < 5; i++) {
            pokemind.addRewards(1, 0, REWARD_AMOUNT);
            console2.log("Added reward batch:", i);
            skip(pokemind.EPOCH_DURATION() / 10);
        }
        vm.stopPrank();

        uint256 pending = pokemind.pendingReward(1, alice, 0);
        console2.log("Final pending rewards:", pending / 1e18);
    }

    function test_StakeRightBeforeClaim() public {
        console2.log("\n=== Last-Minute Stake Test ===");

        // Setup initial staker
        vm.startPrank(alice);
        pokemind.stake(1, STAKE_AMOUNT);
        vm.stopPrank();

        // Add rewards
        vm.startPrank(bob);
        pokemind.addRewards(1, 0, REWARD_AMOUNT);
        vm.stopPrank();

        // Skip almost to end of epoch
        skip(pokemind.EPOCH_DURATION() - 1);

        // Bob tries to stake at last second
        vm.startPrank(bob);
        pokemind.stake(1, STAKE_AMOUNT * 2);
        console2.log("Bob staked at last second with double stake");
        vm.stopPrank();

        skip(1); // Complete epoch

        uint256 alicePending = pokemind.pendingReward(1, alice, 0);
        uint256 bobPending = pokemind.pendingReward(1, bob, 0);
        console2.log("Alice pending:", alicePending / 1e18);
        console2.log("Bob pending:", bobPending / 1e18);
    }

    function test_RewardTokenDrainAttempt() public {
        console2.log("\n=== Reward Token Drain Test ===");

        // Setup stake and rewards
        vm.startPrank(alice);
        pokemind.stake(1, STAKE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(bob);
        pokemind.addRewards(1, 0, REWARD_AMOUNT);
        vm.stopPrank();

        skip(pokemind.EPOCH_DURATION());

        // Get initial balance
        uint256 initialBalance = rewardToken1.balanceOf(alice);
        console2.log("Initial reward token balance:", initialBalance / 1e18);

        // First claim
        vm.startPrank(alice);
        pokemind.claimRewards(1);
        uint256 afterFirstClaim = rewardToken1.balanceOf(alice);
        console2.log("Balance after first claim:", afterFirstClaim / 1e18);
        console2.log("Claimed amount:", (afterFirstClaim - initialBalance) / 1e18);

        // Try second claim
        pokemind.claimRewards(1);
        uint256 afterSecondClaim = rewardToken1.balanceOf(alice);
        console2.log("Balance after second claim:", afterSecondClaim / 1e18);
        console2.log("Additional claimed:", (afterSecondClaim - afterFirstClaim) / 1e18);

        // Verify no additional rewards were claimed
        assertEq(afterSecondClaim, afterFirstClaim, "Should not be able to claim additional rewards");
        vm.stopPrank();
    }
}
