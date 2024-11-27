// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Pokemind} from "../src/Pokemind.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract InvariantTest is StdInvariant, Test {
    Pokemind public pokemind;
    ERC20Mock public pokeToken;
    ERC20Mock public rewardToken1;
    ERC20Mock public rewardToken2;

    address[] public actors;
    uint256 public constant NUM_ACTORS = 5;
    uint256 public constant INITIAL_MINT = 1_000_000 * 1e18;

    // Track total stakes and rewards for invariant checks
    uint256 public totalStaked;
    mapping(uint256 => uint256) public totalRewardsAdded; // rewardTokenIndex => amount

    event InvariantBroken(string reason);

    function setUp() public {
        // Setup tokens
        pokeToken = new ERC20Mock("POKE", "POKE", 18);
        rewardToken1 = new ERC20Mock("Reward1", "RWD1", 18);
        rewardToken2 = new ERC20Mock("Reward2", "RWD2", 18);

        // Setup Pokemind
        pokemind = new Pokemind(address(pokeToken));
        pokemind.addRewardToken(address(rewardToken1));
        pokemind.addRewardToken(address(rewardToken2));

        // Setup actors
        for (uint256 i = 0; i < NUM_ACTORS; i++) {
            address actor = address(uint160(0x1000 + i));
            actors.push(actor);

            // Mint and approve tokens
            pokeToken.mint(actor, INITIAL_MINT);
            rewardToken1.mint(actor, INITIAL_MINT);
            rewardToken2.mint(actor, INITIAL_MINT);

            vm.startPrank(actor);
            pokeToken.approve(address(pokemind), type(uint256).max);
            rewardToken1.approve(address(pokemind), type(uint256).max);
            rewardToken2.approve(address(pokemind), type(uint256).max);
            vm.stopPrank();
        }

        targetContract(address(pokemind));
    }

    function invariant_solvency() public view {
        // Contract balance should be >= total staked
        uint256 contractBalance = pokeToken.balanceOf(address(pokemind));
        uint256 sumOfAllStakes = calculateTotalStakes();

        assertGe(contractBalance, sumOfAllStakes, "Solvency broken: Contract balance < total stakes");
    }

    function invariant_poolTotals() public view {
        // Sum of individual stakes should equal pool totals
        Pokemind.PoolView[] memory pools = pokemind.getActivePoolsInfo();

        for (uint256 i = 0; i < pools.length; i++) {
            uint256 poolTotal = pools[i].totalStaked;
            uint256 calculatedTotal = calculatePoolTotal(pools[i].pokemonId);

            if (poolTotal != calculatedTotal) {
                console2.log("Pool", pools[i].pokemonId, "totals mismatch:");
                console2.log("Stored total:", poolTotal);
                console2.log("Calculated total:", calculatedTotal);
                assertEq(poolTotal, calculatedTotal, "Pool totals don't match sum of stakes");
            }
        }
    }

    function invariant_activePoolsConsistency() public view {
        // Check active pools array matches pool states
        Pokemind.PoolView[] memory pools = pokemind.getActivePoolsInfo();
        uint256 activeCount = pokemind.getActivePoolsCount();

        assertEq(pools.length, activeCount, "Active pools count mismatch");

        for (uint256 i = 0; i < pools.length; i++) {
            assertTrue(pools[i].isActive, "Inactive pool in active pools array");
        }
    }

    function invariant_rewardFairness() public view {
        // For each pool and reward token, check if rewards are proportional to stakes
        Pokemind.PoolView[] memory pools = pokemind.getActivePoolsInfo();

        for (uint256 poolIndex = 0; poolIndex < pools.length; poolIndex++) {
            uint256 pokemonId = pools[poolIndex].pokemonId;
            uint256 poolTotal = pools[poolIndex].totalStaked;

            if (poolTotal > 0) {
                for (uint256 rewardIndex = 0; rewardIndex < pokemind.getRewardTokensCount(); rewardIndex++) {
                    verifyRewardFairness(pokemonId, rewardIndex);
                }
            }
        }
    }

    // Helper functions
    function calculateTotalStakes() internal view returns (uint256 total) {
        Pokemind.PoolView[] memory pools = pokemind.getActivePoolsInfo();
        for (uint256 i = 0; i < pools.length; i++) {
            total += pools[i].totalStaked;
        }
        return total;
    }

    function calculatePoolTotal(uint256 pokemonId) internal view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            (uint256 staked,,) = pokemind.getUserStakeInfo(pokemonId, actors[i]);
            total += staked;
        }
        return total;
    }

    function verifyRewardFairness(uint256 pokemonId, uint256 rewardIndex) internal view {
        uint256 poolTotal = 0;
        uint256 totalRewardShare = 0;

        for (uint256 i = 0; i < actors.length; i++) {
            (uint256 staked,,) = pokemind.getUserStakeInfo(pokemonId, actors[i]);
            if (staked > 0) {
                uint256 pendingReward = pokemind.pendingReward(pokemonId, actors[i], rewardIndex);
                totalRewardShare += pendingReward;
                poolTotal += staked;
            }
        }

        // Check if any user's reward share is disproportionate
        for (uint256 i = 0; i < actors.length; i++) {
            (uint256 staked,,) = pokemind.getUserStakeInfo(pokemonId, actors[i]);
            if (staked > 0) {
                uint256 pendingReward = pokemind.pendingReward(pokemonId, actors[i], rewardIndex);
                uint256 expectedShare = (totalRewardShare * staked) / poolTotal;

                // Allow for some rounding difference (0.1%)
                uint256 tolerance = expectedShare / 1000;
                assertLe(
                    pendingReward,
                    expectedShare + tolerance,
                    "Reward distribution not proportional to stake"
                );
            }
        }
    }

    // Handler functions for fuzzing
    function handle_stake(uint256 actorIndex, uint256 pokemonId, uint256 amount) public {
        // Bound inputs
        actorIndex = bound(actorIndex, 0, actors.length - 1);
        pokemonId = bound(pokemonId, 0, 151); // Gen 1 Pokemon range
        amount = bound(amount, pokemind.MIN_STAKE(), INITIAL_MINT);

        try pokemind.stake(pokemonId, amount) {
            totalStaked += amount;
        } catch {}
    }

    function handle_addRewards(
        uint256 actorIndex,
        uint256 pokemonId,
        uint256 rewardIndex,
        uint256 amount
    ) public {
        actorIndex = bound(actorIndex, 0, actors.length - 1);
        pokemonId = bound(pokemonId, 0, 151);
        rewardIndex = bound(rewardIndex, 0, pokemind.getRewardTokensCount() - 1);
        amount = bound(amount, 0, INITIAL_MINT);

        try pokemind.addRewards(pokemonId, rewardIndex, amount) {
            totalRewardsAdded[rewardIndex] += amount;
        } catch {}
    }

    function handle_withdraw(uint256 actorIndex, uint256 pokemonId) public {
        actorIndex = bound(actorIndex, 0, actors.length - 1);
        pokemonId = bound(pokemonId, 0, 151);

        try pokemind.withdraw(pokemonId) {
            // Update tracking in success case
            (uint256 staked,,) = pokemind.getUserStakeInfo(pokemonId, actors[actorIndex]);
            totalStaked -= staked;
        } catch {}
    }

    function handle_advanceTime(uint256 timeJump) public {
        timeJump = bound(timeJump, 1 days, 30 days);
        skip(timeJump);

        // Try to start new epoch if possible
        try pokemind.startNewEpoch() {} catch {}
    }
}