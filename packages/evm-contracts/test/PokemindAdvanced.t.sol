// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Pokemind} from "../src/Pokemind.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract PokemindAdvancedTest is Test {
    Pokemind public pokemind;
    ERC20Mock public pokeToken;
    ERC20Mock public rewardToken1;
    ERC20Mock public rewardToken2;
    ERC20Mock public rewardToken3;

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");

    uint256 public constant INITIAL_MINT = 1_000_000 * 1e18;
    uint256 public constant MIN_STAKE = 100 * 1e18;

    function setUp() public {
        vm.startPrank(admin);
        pokeToken = new ERC20Mock("POKE", "POKE", 18);
        rewardToken1 = new ERC20Mock("Reward1", "RWD1", 18);
        rewardToken2 = new ERC20Mock("Reward2", "RWD2", 18);
        rewardToken3 = new ERC20Mock("Reward3", "RWD3", 18);

        pokemind = new Pokemind(address(pokeToken));
        pokemind.addRewardToken(address(rewardToken1));
        pokemind.addRewardToken(address(rewardToken2));
        pokemind.addRewardToken(address(rewardToken3));
        vm.stopPrank();

        _setupBalances();
    }

    // Test Pool Deactivation/Reactivation
    function testPoolLifecycle() public {
        // Create new non-starter pool
        vm.startPrank(admin);
        pokemind.createPokemonPool(25, "Pikachu", false);
        vm.stopPrank();

        // Initial stake
        vm.startPrank(alice);
        pokemind.stake(25, 200 * 1e18);
        vm.stopPrank();

        // Deactivate pool - need to be admin
        vm.startPrank(admin);
        pokemind.deactivatePool(25);

        // Verify pool is inactive
        Pokemind.PoolView[] memory pools = pokemind.getActivePoolsInfo();
        bool found = false;
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i].pokemonId == 25) {
                found = true;
                break;
            }
        }
        assertFalse(found, "Deactivated pool still in active pools");

        // Try to stake in deactivated pool
        vm.stopPrank(); // Stop admin
        vm.startPrank(bob);
        vm.expectRevert("Pool not active");
        pokemind.stake(25, 200 * 1e18);
        vm.stopPrank();

        // Reactivate pool - need to be admin again
        vm.startPrank(admin);
        pokemind.reactivatePool(25);

        // Verify pool is active again
        pools = pokemind.getActivePoolsInfo();
        found = false;
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i].pokemonId == 25) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Reactivated pool not in active pools");
        vm.stopPrank();

        // Stake should work again
        vm.startPrank(bob);
        pokemind.stake(25, 200 * 1e18);
        vm.stopPrank();
    }

    // Test Reward Rate Changes
    function testRewardRateChanges() public {
        // Initial setup
        vm.startPrank(alice);
        pokemind.stake(1, 400 * 1e18); // Stake in Bulbasaur
        vm.stopPrank();

        // Add initial rewards
        vm.startPrank(admin);
        rewardToken1.mint(admin, 1000 * 1e18);
        rewardToken1.approve(address(pokemind), type(uint256).max);
        pokemind.addRewards(1, 0, 100 * 1e18);
        vm.stopPrank();

        // Advance halfway through epoch
        skip(3.5 days);

        // Record intermediate rewards
        uint256 halfwayRewards = pokemind.pendingReward(1, alice, 0);

        // Add more rewards
        vm.startPrank(admin);
        pokemind.addRewards(1, 0, 200 * 1e18);
        vm.stopPrank();

        // Complete epoch
        skip(3.5 days);

        // Final rewards should reflect both reward rates
        uint256 finalRewards = pokemind.pendingReward(1, alice, 0);
        assertTrue(finalRewards > halfwayRewards * 2, "Reward rate change not reflected");
    }

    // Test Multiple Reward Tokens
    function testMultipleRewardTokens() public {
        // Setup stakes
        vm.startPrank(alice);
        pokemind.stake(1, 300 * 1e18);
        vm.stopPrank();

        vm.startPrank(bob);
        pokemind.stake(1, 300 * 1e18);
        vm.stopPrank();

        // Add different rewards
        vm.startPrank(admin);
        rewardToken1.mint(admin, 1000 * 1e18);
        rewardToken2.mint(admin, 2000 * 1e18);
        rewardToken3.mint(admin, 3000 * 1e18);

        rewardToken1.approve(address(pokemind), type(uint256).max);
        rewardToken2.approve(address(pokemind), type(uint256).max);
        rewardToken3.approve(address(pokemind), type(uint256).max);

        pokemind.addRewards(1, 0, 100 * 1e18);  // Token1
        pokemind.addRewards(1, 1, 200 * 1e18);  // Token2
        pokemind.addRewards(1, 2, 300 * 1e18);  // Token3
        vm.stopPrank();

        // Advance time
        skip(3.5 days);

        // Check rewards for each token
        (,, uint256[] memory aliceRewards) = pokemind.getUserStakeInfo(1, alice);
        (,, uint256[] memory bobRewards) = pokemind.getUserStakeInfo(1, bob);

        // Equal stakes should have equal rewards for each token
        for (uint256 i = 0; i < 3; i++) {
            assertApproxEqRel(aliceRewards[i], bobRewards[i], 0.01e18);
            assertTrue(aliceRewards[i] > 0, "No rewards for token");

            // Each subsequent token should have higher rewards
            if (i > 0) {
                assertTrue(aliceRewards[i] > aliceRewards[i-1], "Reward proportion incorrect");
            }
        }
    }

    // Gas Usage Tests
    function testGasOptimization() public {
        // Test stake gas usage with different scenarios
        uint256 gas = gasleft();
        vm.startPrank(alice);
        pokemind.stake(1, 200 * 1e18);
        uint256 gasUsed = gas - gasleft();
        console2.log("Gas used for first stake:", gasUsed);

        // Second stake in same pool
        gas = gasleft();
        pokemind.stake(1, 200 * 1e18);
        gasUsed = gas - gasleft();
        console2.log("Gas used for additional stake:", gasUsed);

        // Stake in different pool
        gas = gasleft();
        pokemind.stake(4, 200 * 1e18);
        gasUsed = gas - gasleft();
        console2.log("Gas used for new pool stake:", gasUsed);
        vm.stopPrank();

        // Add rewards gas usage
        vm.startPrank(admin);
        rewardToken1.mint(admin, 1000 * 1e18);
        rewardToken1.approve(address(pokemind), type(uint256).max);

        gas = gasleft();
        pokemind.addRewards(1, 0, 100 * 1e18);
        gasUsed = gas - gasleft();
        console2.log("Gas used for adding rewards:", gasUsed);
        vm.stopPrank();

        // Claim rewards gas usage
        skip(7 days);
        gas = gasleft();
        vm.prank(alice);
        pokemind.claimRewards(1);
        gasUsed = gas - gasleft();
        console2.log("Gas used for claiming rewards:", gasUsed);
    }

    // Test Team Formation
    function testTeamFormation() public {
        // Create multiple non-starter pools
        vm.startPrank(admin);
        for (uint256 i = 10; i <= 20; i++) {
            pokemind.createPokemonPool(i, string(abi.encodePacked("Pokemon", vm.toString(i))), false);
        }
        vm.stopPrank();

        // Different stake amounts to create clear ranking
        vm.startPrank(alice);
        pokemind.stake(10, 600 * 1e18);  // Highest stake
        pokemind.stake(11, 500 * 1e18);
        pokemind.stake(12, 400 * 1e18);
        vm.stopPrank();

        vm.startPrank(bob);
        pokemind.stake(13, 300 * 1e18);
        pokemind.stake(14, 200 * 1e18);
        pokemind.stake(15, 100 * 1e18);  // Lowest stake
        vm.stopPrank();

        // Get top team choices
        (uint256[] memory topIds, uint256[] memory topStakes) = pokemind.getTopTeamChoices();

        // Verify correct number of choices
        assertEq(topIds.length, 6, "Wrong number of team choices");
        assertEq(topStakes.length, 6, "Wrong number of stake values");

        // Verify order (should be descending by stake amount)
        for (uint256 i = 0; i < topStakes.length - 1; i++) {
            assertTrue(topStakes[i] >= topStakes[i + 1], "Stakes not in descending order");
        }

        // Verify actual values
        assertEq(topIds[0], 10, "Wrong top Pokemon");
        assertEq(topStakes[0], 600 * 1e18, "Wrong top stake");
    }

    function _setupBalances() internal {
        pokeToken.mint(alice, INITIAL_MINT);
        pokeToken.mint(bob, INITIAL_MINT);
        pokeToken.mint(carol, INITIAL_MINT);

        rewardToken1.mint(alice, INITIAL_MINT);
        rewardToken1.mint(bob, INITIAL_MINT);
        rewardToken2.mint(alice, INITIAL_MINT);
        rewardToken2.mint(bob, INITIAL_MINT);
        rewardToken3.mint(alice, INITIAL_MINT);
        rewardToken3.mint(bob, INITIAL_MINT);

        vm.startPrank(alice);
        pokeToken.approve(address(pokemind), type(uint256).max);
        rewardToken1.approve(address(pokemind), type(uint256).max);
        rewardToken2.approve(address(pokemind), type(uint256).max);
        rewardToken3.approve(address(pokemind), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        pokeToken.approve(address(pokemind), type(uint256).max);
        rewardToken1.approve(address(pokemind), type(uint256).max);
        rewardToken2.approve(address(pokemind), type(uint256).max);
        rewardToken3.approve(address(pokemind), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(carol);
        pokeToken.approve(address(pokemind), type(uint256).max);
        rewardToken1.approve(address(pokemind), type(uint256).max);
        rewardToken2.approve(address(pokemind), type(uint256).max);
        rewardToken3.approve(address(pokemind), type(uint256).max);
        vm.stopPrank();
    }
}