// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BaseTest.t.sol";

contract StakingTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_BasicStake() public {
        vm.startPrank(alice);
        uint256 stakeAmount = 150 * 1e18; // More than MIN_STAKE

        // Get initial balances
        uint256 initialBalance = pokeToken.balanceOf(alice);
        uint256 initialContractBalance = pokeToken.balanceOf(address(pokemind));

        // Stake in Bulbasaur pool
        pokemind.stake(1, stakeAmount);

        // Verify balances changed correctly
        assertEq(pokeToken.balanceOf(alice), initialBalance - stakeAmount);
        assertEq(pokeToken.balanceOf(address(pokemind)), initialContractBalance + stakeAmount);

        // Verify stake is recorded
        (uint256 staked,,) = pokemind.getUserStakeInfo(1, alice);
        assertEq(staked, stakeAmount);

        vm.stopPrank();
    }

    function test_StakeIncreasesPoolTotal() public {
        uint256 stakeAmount = 200 * 1e18;

        vm.prank(alice);
        pokemind.stake(1, stakeAmount);

        Pokemind.PoolView[] memory pools = pokemind.getActivePoolsInfo();
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i].pokemonId == 1) {
                assertEq(pools[i].totalStaked, stakeAmount);
                break;
            }
        }
    }

    function test_RevertWhen_StakingBelowMinimum() public {
        vm.startPrank(alice);
        uint256 lowStake = 50 * 1e18; // Below MIN_STAKE

        vm.expectRevert("Below minimum stake");
        pokemind.stake(1, lowStake);
        vm.stopPrank();
    }

    function test_RevertWhen_StakingInInactivePool() public {
        // First deactivate a pool
        vm.prank(admin);
        pokemind.deactivatePool(1);

        // Try to stake in deactivated pool
        vm.startPrank(alice);
        vm.expectRevert("Pool not active");
        pokemind.stake(1, 150 * 1e18);
        vm.stopPrank();
    }

    function test_MultipleStakesFromSameUser() public {
        vm.startPrank(alice);
        uint256 firstStake = 150 * 1e18;
        uint256 secondStake = 200 * 1e18;

        // Make two stakes
        pokemind.stake(1, firstStake);
        pokemind.stake(1, secondStake);

        // Verify total stake
        (uint256 totalStaked,,) = pokemind.getUserStakeInfo(1, alice);
        assertEq(totalStaked, firstStake + secondStake);
        vm.stopPrank();
    }

    function test_StakingAffectsTopChoices() public {
        // Stake in starter pool
        vm.prank(alice);
        pokemind.stake(1, 150 * 1e18); // Bulbasaur

        // Check if it's the top starter
        (uint256 topStarterId, uint256 topStake) = pokemind.getTopStarterChoice();
        assertEq(topStarterId, 1);
        assertEq(topStake, 150 * 1e18);

        // Stake more in another starter
        vm.prank(bob);
        pokemind.stake(4, 200 * 1e18); // Charmander

        // Check if top starter changed
        (topStarterId, topStake) = pokemind.getTopStarterChoice();
        assertEq(topStarterId, 4);
        assertEq(topStake, 200 * 1e18);
    }

    function test_RevertWhen_InsufficientBalance() public {
        // Try to stake more than balance
        vm.startPrank(alice);
        uint256 tooMuch = pokeToken.balanceOf(alice) + 1;

        vm.expectRevert(); // ERC20 insufficient balance error
        pokemind.stake(1, tooMuch);
        vm.stopPrank();
    }
}
