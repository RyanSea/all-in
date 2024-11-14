// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./MarketOrderTestBase.sol";

import { AllInBase } from "src/AllInBase.sol";

contract MatchingEngine_MarketOrderTakerCloseTest is MarketOrderTestBase {
    using FixedPointMathLib for *;
    using AllInMath for *;

    function test_MarketOrderClose_PartialTakerClose_Yes(uint random) public {
        uint size = clearingHouse.getTickSize();
        
        uint openAmount = bound(random, 10_500 ether, 20_000 ether);
        uint openPrice = bound(random, minPrice + size, maxPrice);

        if (openPrice % size != 0) openPrice -= (openPrice % size);

        _createLimitOrder(daniel, openPrice, openAmount, false);

        changePrank(rite);
        clearingHouse.openPosition(trump, openAmount, 0, true);

        oldPosition1 = clearingHouse.getPosition(trump, rite);

        (
            uint limitAmount1, 
            uint limitAmount2,
            uint limitPrice1,
            uint limitPrice2
        ) =  _getLimitParamsInRange(
            random,
            openAmount - 10000, 
            false
        );

        order1 = _createLimitOrder(aster, limitPrice1, limitAmount1, true);
        order2 = _createLimitOrder(aster, limitPrice2, limitAmount2, true);
        orderID1 = 2;
        orderID2 = 3;

        uint closeAmount = bound(random, 1 ether, (limitAmount1 + limitAmount2));

        limitAmount1 = limitAmount1.min(closeAmount);
        limitAmount2 = closeAmount > limitAmount1 ? closeAmount - limitAmount1 : 0;

        _simulateCloseAndCacheData(limitAmount1, limitAmount2);

        vm.roll(block.number + 1);

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.PositionChanged({
            market: trump,
            trader: rite,
            markPrice: limitAmount2 > 0 ? order2.price : order1.price,
            openNotional: expectedPosition3.openNotional,
            size: expectedPosition3.size,   
            margin: expectedPosition3.margin,
            realizedPnL: expectedRpnl,
            exchangedQuote: limitAmount1.mul(order1.price) + limitAmount2.mul(order2.price),
            exchangedSize: -int(limitAmount1 + limitAmount2),
            maker : false
        });

        changePrank(rite);
        clearingHouse.closePosition(trump, closeAmount, 0);

        _checkRemainingBookAndOrders(limitAmount1, limitAmount2);
    }

    function _simulateCloseAndCacheData(
        uint limitAmount1,
        uint limitAmount2
    ) internal {
        (
            int rpnl,
            uint marginClosed,
            Position memory remainingPosition
        ) = _estimatePartialCloseRpnl(
            oldPosition1,
            limitAmount1,
            order1.price
        );

        expectedRpnl = rpnl;
        expectedMarginClosed = marginClosed;
        expectedPosition3 = remainingPosition;

        if (limitAmount2 > 0) {
            (
                rpnl,
                marginClosed,
                remainingPosition
            ) = _estimatePartialCloseRpnl(
                expectedPosition3,
                limitAmount2,
                order2.price
            );

            expectedRpnl += rpnl;
            expectedMarginClosed += marginClosed;
            expectedPosition3 = remainingPosition;
        }
    }

    function _estimatePartialCloseRpnl(
        Position memory position,
        uint baseAmount,
        uint price
    ) internal view returns (
        int rpnl, 
        uint marginClosed,
        Position memory remainingPosition
    ) {
        uint ratio = baseAmount.div(position.size.abs());

        uint tradedOpenNotional = position.openNotional.mul(ratio);

        rpnl = _getPnL(
            int(tradedOpenNotional), 
            int(baseAmount.mul(price)),
            position.size > 0
        );

        uint remainingOpenNotional = position.openNotional - tradedOpenNotional;
        int remainingSize = position.size > 0 ? position.size - int(baseAmount) : position.size + int(baseAmount);
        uint marginRequired = _getTakerMarginRequired(remainingOpenNotional, remainingSize);

        marginClosed = position.margin - marginRequired;

        remainingPosition = Position({
            size: remainingSize,
            openNotional: remainingOpenNotional,
            margin: marginRequired,
            lastBlock: block.number
        });
    }

    function _getPnL(
        int256 openNotional,
        int256 currentNotional,
        bool buy
    ) internal pure returns (int256) {
        return buy ? currentNotional - openNotional : openNotional - currentNotional;
    }

    function _getLimitParamsInRange(
        uint amount,
        uint sum,
        bool marketBuy
    ) internal view returns (
        uint limitAmount1, 
        uint limitAmount2,
        uint limitPrice1,
        uint limitPrice2
    ){
        uint256 size = clearingHouse.getTickSize();

        if (marketBuy) {
            limitPrice1 = bound(amount, minPrice + size, maxPrice);
            limitPrice2 = bound(amount, limitPrice1, maxPrice);
        } else {
            limitPrice1 = bound(amount, minPrice, maxPrice - size);
            limitPrice2 = bound(amount, minPrice, limitPrice1);
        }

        if (limitPrice1 % size != 0) limitPrice1 -= (limitPrice1 % size);
        if (limitPrice2 % size != 0) limitPrice2 -= (limitPrice2 % size);

        sum = sum / 2;

        limitAmount1 = bound(amount, 5_000 ether, sum);
        limitAmount2 = bound(amount, 5_000 ether, sum);
    }

}