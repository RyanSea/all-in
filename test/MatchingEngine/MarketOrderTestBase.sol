// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../AllInTestSetup.sol";

import { AllInBase } from "src/AllInBase.sol";

contract MarketOrderTestBase is AllInTestSetup {
    using AllInMath for uint;
    using FixedPointMathLib for *;

    LimitOrder order1;
    LimitOrder order2;
    LimitOrder order3;

    uint orderID1;
    uint orderID2;

    Position oldPosition1;
    Position oldPosition2;
    Position oldPosition3;

    Position expectedPosition1;
    Position expectedPosition2;
    Position expectedPosition3;

    uint maker1BalBefore;
    uint maker2BalBefore;
    uint takerBalBefore;
    uint protocolBalBefore;
    uint ownerBalBefore;

    int expectedRpnl;
    uint expectedMarginClosed;

    uint expectedMakerFee1;
    uint expectedMakerFee2;
    uint expectedBaseFee;
    uint expectedProtocolFee;

    function _checkExpectedEmits(
        address taker, 
        uint limitFill1, 
        uint limitFill2
    ) internal returns (uint exchangedNotional) {
        uint expectedMark = order1.price;
        int expectedSize = order1.bid ? int(limitFill1) : -int(limitFill1);
        uint expectedOpenNotional = limitFill1.mul(order1.price);
        uint expectedMargin = _getTakerMarginRequired(expectedOpenNotional, expectedSize);

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        if (limitFill1 == order1.baseAmount) {
            emit AllInBase.LimitOrderRemoved({
                id: 1,
                filled: true
            });
        } else {
            emit AllInBase.LimitOrderUpdated({
                id: 1,
                market: order1.market,
                maker: order1.maker,
                baseAmount: order1.baseAmount - limitFill1,
                price: order1.price,
                bid: order1.bid,
                reduceOnly: order1.reduceOnly,
                fill: true
            });
        }

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.PositionChanged({
            market: trump,
            trader: order1.maker,
            markPrice: expectedMark,
            openNotional: expectedOpenNotional,
            size: expectedSize,
            margin: expectedMargin,
            realizedPnL: 0,
            exchangedQuote: expectedOpenNotional,
            exchangedSize: expectedSize,
            maker : true
        });

        if (limitFill2 > 0) {
            expectedMark = order2.price;
            expectedSize = order2.bid ? int(limitFill2) : -int(limitFill2);
            expectedOpenNotional = limitFill2.mul(order2.price);
            expectedMargin = _getTakerMarginRequired(expectedOpenNotional, expectedSize);

            vm.expectEmit(true, true, true, true, address(clearingHouse));
            if (limitFill2 == order2.baseAmount) {
                    emit AllInBase.LimitOrderRemoved({
                    id: 2,
                    filled: true
                });
            } else {
                emit AllInBase.LimitOrderUpdated({
                    id: 2,
                    market: order2.market,
                    maker: order2.maker,
                    baseAmount: order2.baseAmount - limitFill2,
                    price: order2.price,
                    bid: order2.bid,
                    reduceOnly: order2.reduceOnly,
                    fill: true
                });
            }

            vm.expectEmit(true, true, true, true, address(clearingHouse));
            emit AllInBase.PositionChanged({
                market: trump,
                trader: order2.maker,
                markPrice: expectedMark,
                openNotional: expectedOpenNotional,
                size: expectedSize,
                margin: expectedMargin,
                realizedPnL: 0,
                exchangedQuote: expectedOpenNotional,
                exchangedSize: expectedSize,
                maker : true
            });
        }

        expectedMark = limitFill2 > 0 ? order2.price : order1.price;
        expectedSize = order1.bid ? -int(limitFill1 + limitFill2) : int(limitFill1 + limitFill2);
        exchangedNotional = expectedOpenNotional = limitFill1.mul(order1.price) + limitFill2.mul(order2.price);
        expectedMargin = _getTakerMarginRequired(expectedOpenNotional, expectedSize);

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.PositionChanged({
            market: trump,
            trader: taker,
            markPrice: expectedMark,
            openNotional: expectedOpenNotional,
            size: expectedSize,
            margin: expectedMargin,
            realizedPnL: 0,
            exchangedQuote: expectedOpenNotional,
            exchangedSize: expectedSize,
            maker : false
        });
    }

    function _checkRemainingBookAndOrders(uint limitFill1, uint limitFill2) internal view {
        bool order1Filled = limitFill1 == order1.baseAmount;
        bool order2Filled = limitFill2 == order2.baseAmount;
        bool ordersOnSameTick = order1.price == order2.price;

        if (order1Filled) {
            assertEq(clearingHouse.getLimitOrder(orderID1).baseAmount, 0, "INCORRECT ORDER1 BASE AMOUNT: FILLED");
        } else {
            assertEq(clearingHouse.getLimitOrder(orderID1).baseAmount, order1.baseAmount - limitFill1, "INCORRECT ORDER1 BASE AMOUNT: PARTIAL");
        }
        if (order2Filled) {
            assertEq(clearingHouse.getLimitOrder(orderID2).baseAmount, 0, "INCORRECT ORDER2 BASE AMOUNT: FILLED");
        } else {
            assertEq(clearingHouse.getLimitOrder(orderID2).baseAmount, order2.baseAmount - limitFill2, "INCORRECT ORDER2 BASE AMOUNT: PARTIAL");
        }

        uint[] memory expectedIds;
        if ((order1Filled && order2Filled) && ordersOnSameTick) { // both filled same tick
            _checkOrdersOnTickAmount(order1.market, order1.price, 0);
            _checkTickInitialized(order1, false);
        } else if (order1Filled && order2Filled) {              // both filled different tick
            _checkOrdersOnTickAmount(order1.market, order1.price, 0);
            _checkOrdersOnTickAmount(order2.market, order2.price, 0);
            _checkTickInitialized(order1, false);
            _checkTickInitialized(order2, false);
        } else if (!order1Filled) {                             // both unfilled (order1 not filled requires order2 to not be filled)
            if (ordersOnSameTick) {
                expectedIds = new uint[](2);
                expectedIds[0] = orderID1;
                expectedIds[1] = orderID2;
                _checkOrdersOnTick(order1.market, order1.price, expectedIds);
            } else {
                expectedIds = new uint[](1);
                expectedIds[0] = orderID1;
                _checkOrdersOnTick(order1.market, order1.price, expectedIds);
                expectedIds[0] = orderID2;
                _checkOrdersOnTick(order2.market, order2.price, expectedIds);
            }
            _checkTickInitialized(order1, true);
            _checkTickInitialized(order2, true);
        } else if (!order2Filled) {                             // order1 filled, order2 not filled
            if (!ordersOnSameTick) {
                _checkTickInitialized(order1, false);
                _checkOrdersOnTickAmount(order1.market, order1.price, 0);
            }
            _checkTickInitialized(order2, true);
            expectedIds = new uint[](1);
            expectedIds[0] = orderID2;
            _checkOrdersOnTick(order2.market, order2.price, expectedIds);
        } 
    }

    function _getMarkAndLimitParams(
        uint amount, 
        bool marketYes
    ) internal view returns (
        uint limitAmount1, 
        uint limitAmount2,
        uint limitPrice1,
        uint limitPrice2
    ){
        uint256 size = clearingHouse.getTickSize();

        if (marketYes) {
            limitPrice1 = bound(amount, minPrice + size, maxPrice);
            limitPrice2 = bound(amount, limitPrice1, maxPrice);
        } else {
            limitPrice1 = bound(amount, minPrice, maxPrice - size);
            limitPrice2 = bound(amount, minPrice, limitPrice1);
        }

        if (limitPrice1 % size != 0) limitPrice1 -= (limitPrice1 % size);
        if (limitPrice2 % size != 0) limitPrice2 -= (limitPrice2 % size);

        limitAmount1 = bound(amount, 5000 ether, 10_000 ether);
        limitAmount2 = bound(amount, 5000 ether, 10_000 ether);
    }
}