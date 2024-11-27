// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BaseTest.t.sol";

contract WithdrawalTest is BaseTest {
    uint256 internal constant STAKE_AMOUNT = 150 * 1e18;

    function setUp() public override {
        super.setUp();

        // Setup initial stake for tests
        vm.startPrank(alice);
        pokemind.stake(1, STAKE_AMOUNT);
        vm.stopPrank();
    }

    function completeEpoch() internal {
        uint256 startTime = block.timestamp;
        console2.log("Initial timestamp:", startTime);

        // Skip to end of current epoch
        skip(pokemind.EPOCH_DURATION());
        console2.log("After first skip timestamp:", block.timestamp);

        // Start new epoch
        vm.startPrank(admin);
        pokemind.startNewEpoch();
        vm.stopPrank();

        // Skip to end of new epoch
        skip(pokemind.EPOCH_DURATION());
        console2.log("After second skip timestamp:", block.timestamp);
        console2.log("Is epoch complete?", pokemind.isEpochComplete());
    }

    function test_WithdrawAfterEpochComplete() public {
        uint256 initialBalance = pokeToken.balanceOf(alice);

        console2.log("Before epoch completion:");
        console2.log("Is epoch complete?", pokemind.isEpochComplete());

        completeEpoch();

        console2.log("After epoch completion:");
        console2.log("Is epoch complete?", pokemind.isEpochComplete());

        vm.startPrank(alice);
        pokemind.withdraw(1);
        vm.stopPrank();

        // Check balances
        assertEq(pokeToken.balanceOf(alice), initialBalance + STAKE_AMOUNT);

        // Check stake is cleared
        (uint256 staked,,) = pokemind.getUserStakeInfo(1, alice);
        assertEq(staked, 0);
    }

    function test_RevertWhen_WithdrawingBeforeEpochEnd() public {
        vm.startPrank(alice);
        vm.expectRevert("Epoch not complete");
        pokemind.withdraw(1);
        vm.stopPrank();
    }

    function test_EmergencyWithdraw() public {
        uint256 initialBalance = pokeToken.balanceOf(alice);

        vm.startPrank(alice);
        pokemind.emergencyWithdraw(1);
        vm.stopPrank();

        // Check balances
        assertEq(pokeToken.balanceOf(alice), initialBalance + STAKE_AMOUNT);

        // Check stake is cleared
        (uint256 staked,,) = pokemind.getUserStakeInfo(1, alice);
        assertEq(staked, 0);

        // Check rewards are cleared
        (,, uint256[] memory pendingRewards) = pokemind.getUserStakeInfo(1, alice);
        for (uint256 i = 0; i < pendingRewards.length; i++) {
            assertEq(pendingRewards[i], 0);
        }
    }

    function test_RevertWhen_WithdrawingWithNoStake() public {
        completeEpoch();

        vm.startPrank(bob);
        vm.expectRevert("No stake found");
        pokemind.withdraw(1);
        vm.stopPrank();
    }

    function test_WithdrawUpdatesPoolTotal() public {
        // Get initial pool total
        Pokemind.PoolView[] memory poolsBefore = pokemind.getActivePoolsInfo();
        uint256 initialTotal;
        for (uint256 i = 0; i < poolsBefore.length; i++) {
            if (poolsBefore[i].pokemonId == 1) {
                initialTotal = poolsBefore[i].totalStaked;
                break;
            }
        }

        completeEpoch();

        // Withdraw
        vm.startPrank(alice);
        pokemind.withdraw(1);
        vm.stopPrank();

        // Check pool total updated
        Pokemind.PoolView[] memory poolsAfter = pokemind.getActivePoolsInfo();
        for (uint256 i = 0; i < poolsAfter.length; i++) {
            if (poolsAfter[i].pokemonId == 1) {
                assertEq(poolsAfter[i].totalStaked, initialTotal - STAKE_AMOUNT);
                break;
            }
        }
    }

    function test_MultiplePeopleWithdrawing() public {
        // Setup bob's stake
        vm.startPrank(bob);
        pokemind.stake(1, STAKE_AMOUNT);
        vm.stopPrank();

        completeEpoch();

        // Both withdraw
        uint256 aliceInitial = pokeToken.balanceOf(alice);
        uint256 bobInitial = pokeToken.balanceOf(bob);

        vm.prank(alice);
        pokemind.withdraw(1);
        vm.prank(bob);
        pokemind.withdraw(1);

        assertEq(pokeToken.balanceOf(alice), aliceInitial + STAKE_AMOUNT);
        assertEq(pokeToken.balanceOf(bob), bobInitial + STAKE_AMOUNT);
    }

    function test_WithdrawImpactOnTopChoices() public {
        // Setup competitive stakes
        vm.prank(bob);
        pokemind.stake(4, STAKE_AMOUNT * 2); // Bigger stake in Charmander

        // Verify initial top choice
        (uint256 topStarterId,) = pokemind.getTopStarterChoice();
        assertEq(topStarterId, 4); // Should be Charmander

        completeEpoch();

        vm.prank(bob);
        pokemind.withdraw(4);

        // Check if top starter changed to Alice's stake
        (topStarterId,) = pokemind.getTopStarterChoice();
        assertEq(topStarterId, 1); // Should now be Bulbasaur
    }
}
