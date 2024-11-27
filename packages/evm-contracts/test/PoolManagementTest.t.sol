// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BaseTest.t.sol";

contract PoolManagementTest is BaseTest {
    event PoolCreated(uint256 indexed poolId, string pokemonName, bool isStarter);
    event PoolDeactivated(uint256 indexed poolId);
    event PoolReactivated(uint256 indexed poolId);

    function setUp() public override {
        super.setUp();
    }

    function test_InitialStarterPools() public {
        vm.startPrank(admin);

        // Log current values
        console2.log("Starter pools count:", pokemind.starterPoolsCount());
        console2.log("Total pools count:", pokemind.totalPoolsCount());
        console2.log("Active pools count:", pokemind.getActivePoolsCount());

        // Get and log pool info
        Pokemind.PoolView[] memory pools = pokemind.getActivePoolsInfo();
        console2.log("Active pools length:", pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            console2.log("Pool", i, ":");
            console2.log("  PokemonId:", pools[i].pokemonId);
            console2.log("  Name:", pools[i].pokemonName);
            console2.log("  IsStarter:", pools[i].isStarter);
            console2.log("  IsActive:", pools[i].isActive);
        }

        // First verify basic pool setup
        assertEq(pokemind.starterPoolsCount(), 3);
        assertEq(pokemind.totalPoolsCount(), 3);
        assertEq(pokemind.getActivePoolsCount(), 3);

        // Then verify specific starters exist and are properly configured
        bool hasBulbasaur = false;
        bool hasCharmander = false;
        bool hasSquirtle = false;

        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i].pokemonId == 1) {
                hasBulbasaur = true;
                assertTrue(pools[i].isStarter);
                assertEq(pools[i].pokemonName, "Bulbasaur");
            }
            if (pools[i].pokemonId == 4) {
                hasCharmander = true;
                assertTrue(pools[i].isStarter);
                assertEq(pools[i].pokemonName, "Charmander");
            }
            if (pools[i].pokemonId == 7) {
                hasSquirtle = true;
                assertTrue(pools[i].isStarter);
                assertEq(pools[i].pokemonName, "Squirtle");
            }
        }

        assertTrue(hasBulbasaur, "Bulbasaur pool not found");
        assertTrue(hasCharmander, "Charmander pool not found");
        assertTrue(hasSquirtle, "Squirtle pool not found");

        // Finally check getTopStarterChoice (now we know it has valid starters to choose from)
        (uint256 id, uint256 stake) = pokemind.getTopStarterChoice();
        assertTrue(id == 1 || id == 4 || id == 7, "Invalid starter ID returned");
        assertEq(stake, 0);

        vm.stopPrank();
    }

    function test_CreateRegularPool() public {
        vm.startPrank(admin);

        // Expect event emission
        vm.expectEmit(true, false, false, true);
        emit PoolCreated(25, "Pikachu", false);

        pokemind.createPokemonPool(25, "Pikachu", false);

        // Verify pool creation
        assertEq(pokemind.totalPoolsCount(), 4); // 3 starters + Pikachu
        assertEq(pokemind.getActivePoolsCount(), 4);

        // Verify pool info
        Pokemind.PoolView[] memory pools = pokemind.getActivePoolsInfo();
        bool foundPikachu = false;
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i].pokemonId == 25) {
                foundPikachu = true;
                assertEq(pools[i].pokemonName, "Pikachu");
                assertEq(pools[i].isStarter, false);
                assertEq(pools[i].isActive, true);
                assertEq(pools[i].totalStaked, 0);
                break;
            }
        }
        assertTrue(foundPikachu, "Pikachu pool not found");

        vm.stopPrank();
    }

    function test_RevertWhen_NonOwnerCreatesPool() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        pokemind.createPokemonPool(25, "Pikachu", false);
    }

    function test_RevertWhen_CreatingDuplicatePool() public {
        vm.startPrank(admin);
        pokemind.createPokemonPool(25, "Pikachu", false);

        vm.expectRevert("Pool already exists");
        pokemind.createPokemonPool(25, "Pikachu", false);
        vm.stopPrank();
    }

    function test_DeactivateAndReactivatePool() public {
        vm.startPrank(admin);

        // Create and verify pool
        pokemind.createPokemonPool(25, "Pikachu", false);
        assertEq(pokemind.getActivePoolsCount(), 4);

        // Deactivate pool
        vm.expectEmit(true, false, false, true);
        emit PoolDeactivated(25);
        pokemind.deactivatePool(25);

        assertEq(pokemind.getActivePoolsCount(), 3);

        // Reactivate pool
        vm.expectEmit(true, false, false, true);
        emit PoolReactivated(25);
        pokemind.reactivatePool(25);

        assertEq(pokemind.getActivePoolsCount(), 4);
        vm.stopPrank();
    }
}
