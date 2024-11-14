// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./MarketOrderTestBase.sol";

import { AllInBase } from "src/AllInBase.sol";

/// @dev broad market order tests
contract MatchingEngine_MarketOrderOpenTest is MarketOrderTestBase {
    using AllInMath for uint;
    using FixedPointMathLib for *;

    mapping(address trader => Position oldPosition) internal _oldPosition;

    function test_MarketOrder_Open_Yes(uint random) public {
        ( 
            uint limitAmount1, 
            uint limitAmount2,
            uint limitPrice1,
            uint limitPrice2
        ) =  _getMarkAndLimitParams(random, true);

        order1 = _createLimitOrder(daniel, limitPrice1, limitAmount1, false);
        order2 = _createLimitOrder(aster, limitPrice2, limitAmount2, false);
        orderID1 = 1;
        orderID2 = 2;

        uint marketOrderAmount = bound(random, 50 ether, limitAmount1 + limitAmount2);

        limitAmount1 = limitAmount1.min(marketOrderAmount);
        limitAmount2 = marketOrderAmount > limitAmount1 ? marketOrderAmount - limitAmount1 : 0;

        uint exchangedNotional = _checkExpectedEmits(rite, limitAmount1, limitAmount2);

        changePrank(rite);
        uint notional = clearingHouse.openPosition(trump, marketOrderAmount, 0, true);

        if (limitAmount2 != 0) {
            assertEq(clearingHouse.getLastPrice(trump), order2.price, "INCORRECT LAST TRADED PRICE");
        } else {
            assertEq(clearingHouse.getLastPrice(trump), order1.price, "INCORRECT LAST TRADED PRICE");
        }

        assertEq(notional, exchangedNotional, "INCORRECT RETURN VALUE");

        _checkRemainingBookAndOrders(limitAmount1, limitAmount2);
        assertEq(clearingHouse.getOpenInterest(trump), exchangedNotional + limitAmount1.mul(order1.price) + limitAmount2.mul(order2.price), "INCORRECT OPEN INTEREST");
    }

    function test_MarketOrder_Open_No(uint random) public {
        ( 
            uint limitAmount1, 
            uint limitAmount2,
            uint limitPrice1,
            uint limitPrice2
        ) =  _getMarkAndLimitParams(random, false);

        order1 = _createLimitOrder(daniel, limitPrice1, limitAmount1, true);
        order2 = _createLimitOrder(aster, limitPrice2, limitAmount2, true);
        orderID1 = 1;
        orderID2 = 2;

        uint marketOrderAmount = bound(random, 50 ether, limitAmount1 + limitAmount2);

        limitAmount1 = limitAmount1.min(marketOrderAmount);
        limitAmount2 = marketOrderAmount > limitAmount1 ? marketOrderAmount - limitAmount1 : 0;

        uint exchangedNotional = _checkExpectedEmits(rite, limitAmount1, limitAmount2);

        changePrank(rite);
        uint notional = clearingHouse.openPosition(trump, marketOrderAmount, 0, false);

        assertEq(notional, exchangedNotional, "INCORRECT RETURN VALUE");

        if (limitAmount2 != 0) {
            assertEq(clearingHouse.getLastPrice(trump), order2.price, "INCORRECT LAST TRADED PRICE");
        } else {
            assertEq(clearingHouse.getLastPrice(trump), order1.price, "INCORRECT LAST TRADED PRICE");
        }

        assertEq(notional, exchangedNotional, "INCORRECT QUOTE AMOUNT RETURN");

        _checkRemainingBookAndOrders(limitAmount1, limitAmount2);
        assertEq(clearingHouse.getOpenInterest(trump), exchangedNotional + limitAmount1.mul(order1.price) + limitAmount2.mul(order2.price), "INCORRECT OPEN INTEREST");
    }

}