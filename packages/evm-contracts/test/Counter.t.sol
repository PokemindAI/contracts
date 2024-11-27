// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { CounterMock } from "./mocks/CounterMock.sol";

contract CounterTest is Test {
    CounterMock public counter;

    function setUp() public {
        counter = new CounterMock();
        counter.setNumber(0);
    }

    function test_Increment() public {
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function testFuzz_SetNumber(uint256 x) public {
        counter.setNumber(x);
        assertEq(counter.number(), x);
    }
}
