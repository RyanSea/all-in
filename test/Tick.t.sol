// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./AllInTestSetup.sol";

contract TickTest is AllInTestSetup {
    /// @dev all valid ticks are unique and incremental 
    function test_Tick_UniqueTicks() public view {
        uint start = minPrice;
        uint end = maxPrice;

        int24 tick = clearingHouse.getPriceToTick(start);
        int24 nextTick;
        while (start < end) {
            nextTick = clearingHouse.getPriceToTick(start += minPrice);

            assertTrue(tick < nextTick, "TICK DOES NOT INCREASE");

            tick = nextTick;
        }
    }

    /// @dev book search can reach max price
    function test_Tick_MaxTickVSMaxPrice() public view {
        assertTrue(maxTick > clearingHouse.getPriceToTick(maxPrice), "MAX PRICE NOT MAX TICK");
    }

    /// @dev book search can reach min price
    function test_Tick_MinTickVSMinPrice() public view {
        assertTrue(minTick < clearingHouse.getPriceToTick(minPrice), "MIN PRICE NOT MIN TICK");
    }
}