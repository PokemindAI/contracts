// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BaseTest.t.sol";

contract RewardsTest is BaseTest {
    uint256 internal constant STAKE_AMOUNT = 1000 * 1e18; // 1000 POKE
    uint256 internal constant REWARD_AMOUNT = 100 * 1e18; // 100 Reward tokens per epoch
    uint256 internal constant PRECISION = 1e16; // 1% tolerance for comparisons

    function setUp() public override {
        super.setUp();

        console2.log("=== Test Setup ===");
        console2.log("Stake amount:", STAKE_AMOUNT / 1e18, "POKE");
        console2.log("Reward amount:", REWARD_AMOUNT / 1e18, "tokens per epoch");

        // Setup initial stake
        vm.startPrank(alice);
        pokemind.stake(1, STAKE_AMOUNT);
        console2.log("Alice staked:", STAKE_AMOUNT / 1e18, "POKE in pool 1");
        vm.stopPrank();

        // Add initial rewards from Bob
        vm.startPrank(bob);
        pokemind.addRewards(1, 0, REWARD_AMOUNT); // Add rewards in first reward token
        console2.log("Bob added rewards:", REWARD_AMOUNT / 1e18, "tokens to pool 1");
        vm.stopPrank();
    }

    function test_BasicRewardAccrual() public {
        console2.log("\n=== Basic Reward Accrual Test ===");

        // Log initial state
        (uint256 staked, uint256 startEpoch, uint256[] memory initialRewards) = pokemind.getUserStakeInfo(1, alice);
        console2.log("Initial state:");
        console2.log("  Staked:", staked / 1e18);
        console2.log("  Start epoch:", startEpoch);
        console2.log("  Initial pending rewards:", initialRewards[0] / 1e18);

        // Skip half epoch
        skip(pokemind.EPOCH_DURATION() / 2);

        // Check pending rewards
        uint256 pendingMid = pokemind.pendingReward(1, alice, 0);
        console2.log("\nMid-epoch state:");
        console2.log("  Timestamp:", block.timestamp);
        console2.log("  Pending rewards:", pendingMid / 1e18);

        // Skip to end of epoch
        skip(pokemind.EPOCH_DURATION() / 2);

        // Check final pending rewards
        uint256 pendingEnd = pokemind.pendingReward(1, alice, 0);
        console2.log("\nEnd-epoch state:");
        console2.log("  Timestamp:", block.timestamp);
        console2.log("  Pending rewards:", pendingEnd / 1e18);

        // Since Alice is the only staker, she should get all rewards
        assertApproxEqRel(pendingEnd, REWARD_AMOUNT, PRECISION);
    }

    function test_RewardSplitBetweenStakers() public {
        console2.log("\n=== Reward Split Test ===");

        // Bob stakes same amount as Alice
        vm.startPrank(bob);
        pokemind.stake(1, STAKE_AMOUNT);
        console2.log("Bob staked:", STAKE_AMOUNT / 1e18, "POKE in pool 1");
        vm.stopPrank();

        // Skip some time
        skip(pokemind.EPOCH_DURATION() / 2);

        // Check pending rewards for both
        uint256 alicePending = pokemind.pendingReward(1, alice, 0);
        uint256 bobPending = pokemind.pendingReward(1, bob, 0);

        console2.log("\nMid-epoch state:");
        console2.log("  Alice pending:", alicePending / 1e18);
        console2.log("  Bob pending:", bobPending / 1e18);

        // Equal stakes should mean equal rewards
        assertApproxEqRel(alicePending, bobPending, PRECISION);
    }

    function test_RewardClaiming() public {
        console2.log("\n=== Reward Claiming Test ===");

        // Skip to accrue some rewards
        skip(pokemind.EPOCH_DURATION());

        uint256 pendingBefore = pokemind.pendingReward(1, alice, 0);
        console2.log("Pending rewards before claim:", pendingBefore / 1e18);

        uint256 balanceBefore = rewardToken1.balanceOf(alice);
        console2.log("Reward token balance before:", balanceBefore / 1e18);

        // Claim rewards
        vm.startPrank(alice);
        pokemind.claimRewards(1);
        vm.stopPrank();

        uint256 balanceAfter = rewardToken1.balanceOf(alice);
        console2.log("Reward token balance after:", balanceAfter / 1e18);
        uint256 claimed = balanceAfter - balanceBefore;
        console2.log("Actually claimed:", claimed / 1e18);

        // Verify rewards were claimed correctly
        assertEq(claimed, pendingBefore);
        assertEq(pokemind.pendingReward(1, alice, 0), 0);
    }

    function test_MultipleRewardTokens() public {
        console2.log("\n=== Multiple Reward Tokens Test ===");

        // Add rewards for second token
        vm.startPrank(bob);
        pokemind.addRewards(1, 1, REWARD_AMOUNT * 2); // Double rewards for token2
        console2.log("Added second reward token with rate:", (REWARD_AMOUNT * 2) / 1e18);
        vm.stopPrank();

        skip(pokemind.EPOCH_DURATION() / 2);

        // Check pending rewards for both tokens
        uint256 pending1 = pokemind.pendingReward(1, alice, 0);
        uint256 pending2 = pokemind.pendingReward(1, alice, 1);

        console2.log("\nMid-epoch pending rewards:");
        console2.log("  Token1:", pending1 / 1e18);
        console2.log("  Token2:", pending2 / 1e18);

        // Second token should have double the rewards
        assertApproxEqRel(pending2, pending1 * 2, PRECISION);
    }

    function test_RewardRateUpdates() public {
        console2.log("\n=== Reward Rate Update Test ===");

        // Initial rate
        uint256 initialPending = pokemind.pendingReward(1, alice, 0);
        console2.log("Initial pending at start:", initialPending / 1e18);

        // Skip some time
        skip(pokemind.EPOCH_DURATION() / 4);

        // Add more rewards
        vm.startPrank(bob);
        pokemind.addRewards(1, 0, REWARD_AMOUNT * 2);
        console2.log("Added double rewards at 1/4 epoch");
        vm.stopPrank();

        // Skip to mid epoch
        skip(pokemind.EPOCH_DURATION() / 4);

        uint256 midPending = pokemind.pendingReward(1, alice, 0);
        console2.log("Pending at mid-epoch:", midPending / 1e18);

        // Final check at epoch end
        skip(pokemind.EPOCH_DURATION() / 2);

        uint256 finalPending = pokemind.pendingReward(1, alice, 0);
        console2.log("Final pending at epoch end:", finalPending / 1e18);

        // The rate increased partway through, so final should be more than double initial
        assertTrue(finalPending > initialPending * 2);
    }
}
