// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Pokemind} from "../src/Pokemind.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract PokemindTest is Test {
    Pokemind public pokemind;
    ERC20Mock public pokeToken;
    ERC20Mock public rewardToken1;
    ERC20Mock public rewardToken2;

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_MINT = 1_000_000 * 1e18;
    uint256 public constant MIN_STAKE = 100 * 1e18;

    function setUp() public {
        vm.startPrank(admin);
        pokeToken = new ERC20Mock("POKE", "POKE", 18);
        rewardToken1 = new ERC20Mock("Reward1", "RWD1", 18);
        rewardToken2 = new ERC20Mock("Reward2", "RWD2", 18);

        pokemind = new Pokemind(address(pokeToken));
        pokemind.addRewardToken(address(rewardToken1));
        pokemind.addRewardToken(address(rewardToken2));
        vm.stopPrank();

        // Setup balances and approvals
        _setupBalances();
    }

    function testStarterPokemonLimits() public {
        vm.startPrank(admin);

        // Should already have 3 starter Pokemon from constructor
        assertEq(pokemind.starterPoolsCount(), 3);

        // Can add one more starter (Pikachu)
        pokemind.createPokemonPool(25, "Pikachu", true);
        assertEq(pokemind.starterPoolsCount(), 4);

        // Should revert when trying to add a fifth starter
        vm.expectRevert("Max starter pools reached");
        pokemind.createPokemonPool(133, "Eevee", true);
    }

    function testRewardDistributionWithEpochChange() public {
        // Setup initial stakes
        vm.startPrank(alice);
        pokemind.stake(1, 200 * 1e18); // Stake in Bulbasaur
        vm.stopPrank();

        vm.startPrank(bob);
        pokemind.stake(1, 200 * 1e18); // Equal stake
        vm.stopPrank();

        // Add rewards
        vm.startPrank(admin);
        rewardToken1.mint(admin, 1000 * 1e18);
        rewardToken1.approve(address(pokemind), type(uint256).max);
        pokemind.addRewards(1, 0, 100 * 1e18);
        vm.stopPrank();

        // Advance half an epoch
        skip(3.5 days);

        // Check intermediate rewards
        uint256 aliceReward = pokemind.pendingReward(1, alice, 0);
        uint256 bobReward = pokemind.pendingReward(1, bob, 0);
        assertApproxEqRel(aliceReward, bobReward, 0.01e18); // 1% tolerance

        // Complete epoch
        skip(3.5 days);
        vm.prank(admin);
        pokemind.startNewEpoch();

        // Verify rewards after epoch
        aliceReward = pokemind.pendingReward(1, alice, 0);
        bobReward = pokemind.pendingReward(1, bob, 0);
        assertApproxEqRel(aliceReward, bobReward, 0.01e18);
    }

    function testEmergencyWithdrawal() public {
        // Setup stake and rewards
        vm.startPrank(alice);
        pokemind.stake(1, 200 * 1e18);
        vm.stopPrank();

        vm.startPrank(admin);
        rewardToken1.mint(admin, 1000 * 1e18);
        rewardToken1.approve(address(pokemind), type(uint256).max);
        pokemind.addRewards(1, 0, 100 * 1e18);
        vm.stopPrank();

        skip(1 days);

        // Emergency withdraw
        vm.startPrank(alice);
        uint256 preBalance = pokeToken.balanceOf(alice);
        pokemind.emergencyWithdraw(1);
        uint256 postBalance = pokeToken.balanceOf(alice);

        // Check principal returned
        assertEq(postBalance - preBalance, 200 * 1e18);

        // Check rewards forfeited
        uint256 rewards = pokemind.pendingReward(1, alice, 0);
        assertEq(rewards, 0);
    }

    function testPauseUnpause() public {
        // Initial stake should work
        vm.startPrank(alice);
        pokemind.stake(1, 200 * 1e18);
        vm.stopPrank();

        // Pause contract
        vm.prank(admin);
        pokemind.pause();

        // Staking should fail while paused
        vm.startPrank(alice);
        // Use proper error handling for custom errors
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        pokemind.stake(1, 200 * 1e18);

        // Emergency withdraw should still work while paused
        pokemind.emergencyWithdraw(1);
        vm.stopPrank();

        // Unpause and verify staking works again
        vm.prank(admin);
        pokemind.unpause();

        vm.startPrank(alice);
        pokemind.stake(1, 200 * 1e18);
        vm.stopPrank();
    }
    function testTopStarterChoice() public {
        // Initial stakes
        vm.startPrank(alice);
        pokemind.stake(1, 300 * 1e18); // Bulbasaur
        pokemind.stake(4, 200 * 1e18); // Charmander
        pokemind.stake(7, 100 * 1e18); // Squirtle
        vm.stopPrank();

        // Check top starter
        (uint256 topId, uint256 totalStaked) = pokemind.getTopStarterChoice();
        assertEq(topId, 1); // Should be Bulbasaur
        assertEq(totalStaked, 300 * 1e18);

        // Add more stake to change winner
        vm.startPrank(bob);
        pokemind.stake(4, 400 * 1e18); // More in Charmander
        vm.stopPrank();

        (topId, totalStaked) = pokemind.getTopStarterChoice();
        assertEq(topId, 4); // Should now be Charmander
        assertEq(totalStaked, 600 * 1e18);
    }

    function testRecoverTokens() public {
        // Send some random token to contract
        ERC20Mock randomToken = new ERC20Mock("Random", "RND", 18);
        randomToken.mint(address(pokemind), 1000 * 1e18);

        uint256 preBalance = randomToken.balanceOf(admin);

        // Recover tokens
        vm.prank(admin);
        pokemind.recoverERC20(address(randomToken), 1000 * 1e18);

        // Check balances
        assertEq(randomToken.balanceOf(admin) - preBalance, 1000 * 1e18);
        assertEq(randomToken.balanceOf(address(pokemind)), 0);

        // Should not be able to recover stake token
        vm.startPrank(admin);
        vm.expectRevert("Cannot recover stake token");
        pokemind.recoverERC20(address(pokeToken), 1000 * 1e18);

        // Should not be able to recover reward tokens
        vm.expectRevert("Cannot recover reward token");
        pokemind.recoverERC20(address(rewardToken1), 1000 * 1e18);
        vm.stopPrank();
    }

    function _setupBalances() internal {
        // Setup token balances and approvals for test accounts
        pokeToken.mint(alice, INITIAL_MINT);
        pokeToken.mint(bob, INITIAL_MINT);
        rewardToken1.mint(alice, INITIAL_MINT);
        rewardToken1.mint(bob, INITIAL_MINT);
        rewardToken2.mint(alice, INITIAL_MINT);
        rewardToken2.mint(bob, INITIAL_MINT);

        vm.startPrank(alice);
        pokeToken.approve(address(pokemind), type(uint256).max);
        rewardToken1.approve(address(pokemind), type(uint256).max);
        rewardToken2.approve(address(pokemind), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        pokeToken.approve(address(pokemind), type(uint256).max);
        rewardToken1.approve(address(pokemind), type(uint256).max);
        rewardToken2.approve(address(pokemind), type(uint256).max);
        vm.stopPrank();
    }
}