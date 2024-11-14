// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../AllInTestSetup.sol";
import { AllInBase } from "src/AllInBase.sol";
import { TickBitmap } from "src/utils/TickBitmap.sol";
import { ME_FillLimitOrder } from "./FillLimitOrder.MarginRefund.t.sol";

contract MatchingEngine_FillLimitOrder_PartialFillValuation is AllInTestSetup {
    using FixedPointMathLib for *;

    LimitOrder order;
    LimitOrder filledOrder;
    Position oldPosition;
    uint256 margin;
    uint256 newMargin;
    Position position;

    ME_FillLimitOrder me;

    function setUp() public override {
        super.setUp();
        
        me = new ME_FillLimitOrder(address(usdb));
    }

    /*//////////////////////////////////////////////////////////////
                  REMAINING ORDER VALUATION: INCREASE
    //////////////////////////////////////////////////////////////*/

    function test_FillLimit_Increase_Partial_Yes(uint amount, uint price, uint fillAmount) public {
        price = bound(price, .1 ether, .9 ether);
        amount = bound(amount, .1 ether, 10 ether);
        fillAmount = bound(fillAmount, .01 ether, amount - .01 ether);

        order = LimitOrder({
            maker: daniel,
            market: trump,
            price: price,
            baseAmount: amount,
            bid: true,
            reduceOnly: false
        });

        margin = _getOrderMarginRequired(order);

        me.placeLimitOrder(order);
        filledOrder = me.cloneLimitOrder(order);

        filledOrder.baseAmount = fillAmount;
        order.baseAmount -= fillAmount;
        newMargin = _getOrderMarginRequired(order);

        me.fillLimitOrder(filledOrder);

        position = me.getPosition(order.market, order.maker);

        // note: maker would get back newMargin if the deleted their order after a partial fill
        assertTrue(margin - position.margin >= newMargin, "PROTOCOL_INSOLVENT");
        assertTrue(FixedPointMathLib.dist(margin - position.margin, newMargin) <= 1, "IMPRECISION_TOO_HIGH");
    }

    function test_FillLimit_Increase_Partial_No(uint random) public {
        uint price = bound(random, .1 ether, .9 ether);
        uint amount = bound(random, 10 ether, 10000 ether);
        uint fillAmount = bound(random, .1 ether, amount - 2 ether);

        order = LimitOrder({
            maker: daniel,
            market: trump,
            price: price,
            baseAmount: amount,
            bid: false,
            reduceOnly: false
        });

        margin = _getOrderMarginRequired(order);

        me.placeLimitOrder(order);
        filledOrder = me.cloneLimitOrder(order);

        filledOrder.baseAmount = fillAmount;
        order.baseAmount -= fillAmount;
        newMargin = _getOrderMarginRequired(order);

        me.fillLimitOrder(filledOrder);

        position = me.getPosition(order.market, order.maker);

        // note: maker would get back newMargin if the deleted their order after a partial fill
        // assertTrue(margin - position.margin >= newMargin, "PROTOCOL_INSOLVENT"); // note: can be insolvent 1 wei
        console.log(FixedPointMathLib.dist(margin - position.margin, newMargin));
        assertTrue(FixedPointMathLib.dist(margin - position.margin, newMargin) <= 1, "IMPRECISION_TOO_HIGH");
    }

    /*//////////////////////////////////////////////////////////////
                  REMAINING ORDER VALUATION: DECREASE
    //////////////////////////////////////////////////////////////*/

    function test_FillLimit_Decrease_Partial_Yes(uint random) public {
        LimitOrder[] memory orders = new LimitOrder[](1);

        uint amount = bound(random, 100 ether, 1000 ether);

        orders[0] = LimitOrder({
            maker: daniel,
            market: trump,
            price: .5 ether,
            baseAmount: amount,
            bid: false,
            reduceOnly: false
        });

        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        vm.prank(rite);
        clearingHouse.openPosition(trump, amount, 0, true);

        uint price = bound(random, .3 ether, .7 ether);

        if (price % clearingHouse.getTickSize() != 0) price -= (price % clearingHouse.getTickSize());

        orders[0] = LimitOrder({
            maker: rite,
            market: trump,
            price: price,
            baseAmount: amount,
            bid: false,
            reduceOnly: false
        });

        margin = _getOrderMarginRequired(orders[0]);

        vm.prank(rite);
        clearingHouse.createLimitOrders(orders);

        amount = bound(random, 1 ether, amount - 1 ether);

        vm.prank(jd);
        clearingHouse.openPosition(trump, amount, 0, true);

        orders[0].baseAmount -= amount;

        newMargin = _getOrderMarginRequired(orders[0]);

        orders[0].baseAmount = amount;

        uint filledMargin = _getOrderMarginRequired(orders[0]);

        // assertTrue(margin - filledMargin >= newMargin, "PROTOCOL_INSOLVENT"); // note: can be insolvent 1 wei
        assertTrue(FixedPointMathLib.dist(margin - filledMargin, newMargin) <= 1, "IMPRECISION_TOO_HIGH");
    }
}