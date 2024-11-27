// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import { Pokemind } from "../src/Pokemind.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";

abstract contract BaseTest is Test {
    // Contracts
    Pokemind public pokemind;
    ERC20Mock public pokeToken;
    ERC20Mock public rewardToken1;
    ERC20Mock public rewardToken2;

    // Test addresses
    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");

    // Constants
    uint256 public constant INITIAL_MINT = 1_000_000 * 1e18;
    uint256 public constant MIN_STAKE = 100 * 1e18;

    function fail2(string memory reason) internal pure {
        revert(reason);
    }

    function setUp() public virtual {
        // Setup tokens
        pokeToken = new ERC20Mock("POKE", "POKE", 18);
        rewardToken1 = new ERC20Mock("Reward1", "RWD1", 18);
        rewardToken2 = new ERC20Mock("Reward2", "RWD2", 18);

        // Setup Pokemind contract
        vm.startPrank(admin);
        pokemind = new Pokemind(address(pokeToken));
        pokemind.addRewardToken(address(rewardToken1));
        pokemind.addRewardToken(address(rewardToken2));
        vm.stopPrank();

        // Setup initial token balances
        _setupBalances();
    }

    function _setupBalances() internal {
        // Mint POKE tokens
        pokeToken.mint(alice, INITIAL_MINT);
        pokeToken.mint(bob, INITIAL_MINT);
        pokeToken.mint(carol, INITIAL_MINT);

        // Mint reward tokens
        rewardToken1.mint(alice, INITIAL_MINT);
        rewardToken1.mint(bob, INITIAL_MINT);
        rewardToken2.mint(alice, INITIAL_MINT);
        rewardToken2.mint(bob, INITIAL_MINT);

        // Approve pokemind contract
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
