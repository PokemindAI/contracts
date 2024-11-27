// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { CounterMock } from "../test/mocks/CounterMock.sol";

contract CounterScript is Script {
    CounterMock public counter;

    function setUp() public { }

    function run() public {
        vm.startBroadcast();

        counter = new CounterMock();

        vm.stopBroadcast();
    }
}
