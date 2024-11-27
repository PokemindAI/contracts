// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BaseTest.t.sol";

contract EpochTest is BaseTest {
    uint256 internal constant STAKE_AMOUNT = 1000 * 1e18;

    function setUp() public override {
        super.setUp();
        console2.log("\n=== Epoch Tests Setup ===");
        console2.log("Initial timestamp:", block.timestamp);
        console2.log("Epoch duration:", pokemind.EPOCH_DURATION());
    }

    function test_EpochBoundaryStaking() public {
        console2.log("\n=== Epoch Boundary Staking Test ===");

        // Stake right before epoch end
        skip(pokemind.EPOCH_DURATION() - 1);
        console2.log("Timestamp before stake:", block.timestamp);

        vm.startPrank(alice);
        pokemind.stake(1, STAKE_AMOUNT);
        console2.log("Staked at timestamp:", block.timestamp);
        vm.stopPrank();

        // Add rewards
        vm.startPrank(bob);
        pokemind.addRewards(1, 0, 100 * 1e18);
        vm.stopPrank();

        // Complete epoch
        skip(1);
        console2.log("Epoch end timestamp:", block.timestamp);

        // Start new epoch
        vm.prank(admin);
        pokemind.startNewEpoch();

        // Check rewards
        uint256 pendingRewards = pokemind.pendingReward(1, alice, 0);
        console2.log("Pending rewards:", pendingRewards / 1e18);

        // Should get very small amount of rewards for 1 second
        assertLt(pendingRewards, 1e18);
    }

    function test_CrossEpochRewards() public {
        console2.log("\n=== Cross Epoch Rewards Test ===");

        // Stake in first epoch
        vm.startPrank(alice);
        pokemind.stake(1, STAKE_AMOUNT);
        console2.log("Staked in epoch 0");
        vm.stopPrank();

        // Add rewards
        vm.startPrank(bob);
        pokemind.addRewards(1, 0, 100 * 1e18);
        console2.log("Added rewards in epoch 0");
        vm.stopPrank();

        // Complete first epoch
        skip(pokemind.EPOCH_DURATION());
        vm.prank(admin);
        pokemind.startNewEpoch();
        console2.log("Started epoch 1");

        // Add more rewards in new epoch
        vm.startPrank(bob);
        pokemind.addRewards(1, 0, 200 * 1e18);
        console2.log("Added more rewards in epoch 1");
        vm.stopPrank();

        // Check rewards
        uint256 pendingRewards = pokemind.pendingReward(1, alice, 0);
        console2.log("Total pending rewards:", pendingRewards / 1e18);

        // Should accumulate rewards from both epochs
        assertGt(pendingRewards, 100 * 1e18);
    }

    function test_RevertWhen_StartingEpochTooEarly() public {
        console2.log("\n=== Early Epoch Start Test ===");

        skip(pokemind.EPOCH_DURATION() / 2);
        console2.log("Trying to start new epoch at half duration");

        vm.startPrank(admin);
        vm.expectRevert("Current epoch not complete");
        pokemind.startNewEpoch();
        vm.stopPrank();
    }

    function test_MultipleEpochTransitions() public {
        console2.log("\n=== Multiple Epoch Transitions Test ===");

        // Stake and add rewards
        vm.startPrank(alice);
        pokemind.stake(1, STAKE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(bob);
        pokemind.addRewards(1, 0, 100 * 1e18);
        vm.stopPrank();

        // Track rewards over multiple epochs
        uint256[] memory rewardSnapshots = new uint256[](3);

        for (uint256 i = 0; i < 3; i++) {
            skip(pokemind.EPOCH_DURATION());

            console2.log("Before epoch", i + 1, "transition:");
            console2.log("  Timestamp:", block.timestamp);
            rewardSnapshots[i] = pokemind.pendingReward(1, alice, 0);
            console2.log("  Pending rewards:", rewardSnapshots[i] / 1e18);

            vm.prank(admin);
            pokemind.startNewEpoch();
        }

        // Rewards should accumulate linearly
        assertGt(rewardSnapshots[1], rewardSnapshots[0]);
        assertGt(rewardSnapshots[2], rewardSnapshots[1]);
    }

    function test_EpochBoundaryWithdrawal() public {
        console2.log("\n=== Epoch Boundary Withdrawal Test ===");

        // Setup stake in first epoch
        vm.startPrank(alice);
        pokemind.stake(1, STAKE_AMOUNT);
        console2.log("Staked in epoch 0");
        vm.stopPrank();

        // Complete first epoch
        skip(pokemind.EPOCH_DURATION());
        console2.log("Completed first epoch duration at:", block.timestamp);
        vm.prank(admin);
        pokemind.startNewEpoch();

        // Complete second epoch
        skip(pokemind.EPOCH_DURATION());
        console2.log("Completed second epoch duration at:", block.timestamp);
        vm.prank(admin);
        pokemind.startNewEpoch();

        console2.log("Completed two epochs");

        // Skip into the third epoch to ensure we can withdraw
        skip(pokemind.EPOCH_DURATION());
        console2.log("Time at withdrawal:", block.timestamp);

        // Try withdrawal
        vm.startPrank(alice);
        pokemind.withdraw(1);
        console2.log("Withdrawal successful");

        // Try to stake again immediately
        pokemind.stake(1, STAKE_AMOUNT);
        console2.log("Immediate re-stake successful");
        vm.stopPrank();
    }

    function test_SkippingMultipleEpochs() public {
        console2.log("\n=== Skipping Multiple Epochs Test ===");

        // Setup initial stake and rewards
        vm.startPrank(alice);
        pokemind.stake(1, STAKE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(bob);
        pokemind.addRewards(1, 0, 100 * 1e18);
        vm.stopPrank();

        // Handle epochs one by one to maintain proper state
        for (uint256 i = 0; i < 3; i++) {
            console2.log("\nStarting epoch transition", i + 1);
            console2.log("Current timestamp:", block.timestamp);

            skip(pokemind.EPOCH_DURATION());
            console2.log("After skip timestamp:", block.timestamp);

            uint256 pendingRewards = pokemind.pendingReward(1, alice, 0);
            console2.log("Pending rewards:", pendingRewards / 1e18);

            vm.prank(admin);
            pokemind.startNewEpoch();
            console2.log("New epoch started");
        }

        // Final rewards check
        uint256 finalRewards = pokemind.pendingReward(1, alice, 0);
        console2.log("\nFinal pending rewards:", finalRewards / 1e18);
        assertGt(finalRewards, 0, "Should have accumulated rewards");
    }
}
