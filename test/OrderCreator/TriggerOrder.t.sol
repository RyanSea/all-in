// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../AllInTestSetup.sol";

import { AllInBase } from "src/AllInBase.sol";

contract OrderCreator_TriggerOrderTest is AllInTestSetup {
    
    /*//////////////////////////////////////////////////////////////
                          TRIGGER ORDER CREATE
    //////////////////////////////////////////////////////////////*/

    function test_OrderCreator_TriggerOrder_Create_TakeProfit_Yes() public {
        TriggerOrder[] memory orders = new TriggerOrder[](1);
        orders[0] = TriggerOrder({
            market: trump,
            taker: rite,
            baseAmount: 100 ether,
            quoteLimit: 0,
            price: .3 ether,
            stopLoss: false
        });

        _createPosition(rite, 100 ether, true);
        _placeBestBidAsk();

        vm.startPrank(rite);

        // note: best bid above below take profit price
        vm.expectRevert(OrderCreator.MARKET_ORDER.selector);
        clearingHouse.createTriggerOrders(orders);

        orders[0].price = .7 ether;

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.TriggerOrderUpdated({
            id: 4,
            market: trump,
            taker: rite,
            baseAmount: 100 ether,
            quoteLimit: 0,
            price: .7 ether,
            stopLoss: false
        });
 
        uint[] memory ids = clearingHouse.createTriggerOrders(orders);

        TriggerOrder memory order = clearingHouse.getTriggerOrder(ids[0]);

        assertEq(order.market, trump, "ORDER MARKET INCORRECT");
        assertEq(order.taker, rite, "ORDER TAKER INCORRECT");
        assertEq(order.baseAmount, 100 ether, "ORDER BASE AMOUNT INCORRECT");
        assertEq(order.price, .7 ether, "ORDER PRICE INCORRECT");
        assertEq(order.stopLoss, false, "ORDER STOP LOSS INCORRECT");
        assertFalse(clearingHouse.isTriggerOrderValid(ids[0]), "ORDER NOT YET VALID");
    }

    function test_OrderCreator_TriggerOrder_Create_StopLoss_Yes() public {
        TriggerOrder[] memory orders = new TriggerOrder[](1);
        orders[0] = TriggerOrder({
            market: trump,
            taker: rite,
            baseAmount: 100 ether,
            quoteLimit: 0,
            price: .45 ether,
            stopLoss: true
        });

        _createPosition(rite, 100 ether, true);
        _placeBestBidAsk();
 
        vm.startPrank(rite);

        // note: best bid above stop loss price
        vm.expectRevert(OrderCreator.MARKET_ORDER.selector);
        clearingHouse.createTriggerOrders(orders);

        orders[0].price = .3 ether;

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.TriggerOrderUpdated({
            id: 4,
            market: trump,
            taker: rite,
            baseAmount: 100 ether,
            quoteLimit: 0,
            price: .3 ether,
            stopLoss: true
        });

        uint[] memory ids = clearingHouse.createTriggerOrders(orders);

        TriggerOrder memory order = clearingHouse.getTriggerOrder(ids[0]);

        assertEq(order.market, trump, "ORDER MARKET INCORRECT");
        assertEq(order.taker, rite, "ORDER TAKER INCORRECT");
        assertEq(order.baseAmount, 100 ether, "ORDER BASE AMOUNT INCORRECT");
        assertEq(order.price, .3 ether, "ORDER PRICE INCORRECT");
        assertEq(order.stopLoss, true, "ORDER STOP LOSS INCORRECT");
    }

    function test_OrderCreator_TriggerOrder_Create_TakeProfit_No() public {
        TriggerOrder[] memory orders = new TriggerOrder[](1);
        orders[0] = TriggerOrder({
            market: trump,
            taker: rite,
            baseAmount: 100 ether,
            quoteLimit: 0,
            price: .7 ether,
            stopLoss: false
        });

        _createPosition(rite, 100 ether, false);
        _placeBestBidAsk();

        vm.startPrank(rite);

        // note: best ask below take profit price
        vm.expectRevert(OrderCreator.MARKET_ORDER.selector);
        clearingHouse.createTriggerOrders(orders);

        orders[0].price = .3 ether;

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.TriggerOrderUpdated({
            id: 4,
            market: trump,
            taker: rite,
            baseAmount: 100 ether,
            quoteLimit: 0,
            price: .3 ether,
            stopLoss: false
        });

        uint[] memory ids = clearingHouse.createTriggerOrders(orders);

        TriggerOrder memory order = clearingHouse.getTriggerOrder(ids[0]);

        assertEq(order.market, trump, "ORDER MARKET INCORRECT");
        assertEq(order.taker, rite, "ORDER TAKER INCORRECT");
        assertEq(order.baseAmount, 100 ether, "ORDER BASE AMOUNT INCORRECT");
        assertEq(order.price, .3 ether, "ORDER PRICE INCORRECT");
        assertEq(order.stopLoss, false, "ORDER STOP LOSS INCORRECT");
    }

    function test_OrderCreator_TriggerOrder_Create_StopLoss_No() public {
        TriggerOrder[] memory orders = new TriggerOrder[](1);
        orders[0] = TriggerOrder({
            market: trump,
            taker: rite,
            baseAmount: 100 ether,
            quoteLimit: 0,
            price: .3 ether,
            stopLoss: true
        });

        _createPosition(rite, 100 ether, false);
        _placeBestBidAsk();

        vm.startPrank(rite);

        // note: best ask above stop loss price
        vm.expectRevert(OrderCreator.MARKET_ORDER.selector);
        clearingHouse.createTriggerOrders(orders);

        orders[0].price = .7 ether;

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.TriggerOrderUpdated({
            id: 4,
            market: trump,
            taker: rite,
            baseAmount: 100 ether,
            quoteLimit: 0,
            price: .7 ether,
            stopLoss: true
        });

        uint[] memory ids = clearingHouse.createTriggerOrders(orders);

        TriggerOrder memory order = clearingHouse.getTriggerOrder(ids[0]);

        assertEq(order.market, trump, "ORDER MARKET INCORRECT");
        assertEq(order.taker, rite, "ORDER TAKER INCORRECT");
        assertEq(order.baseAmount, 100 ether, "ORDER BASE AMOUNT INCORRECT");
        assertEq(order.price, .7 ether, "ORDER PRICE INCORRECT");
        assertEq(order.stopLoss, true, "ORDER STOP LOSS INCORRECT");
    }

    /*//////////////////////////////////////////////////////////////
                        TRIGGER ORDER ASSERTIONS
    //////////////////////////////////////////////////////////////*/

    function test_OrderCreator_TriggerOrder_Assertions_NoPosition() public {
        TriggerOrder[] memory orders = new TriggerOrder[](1);
        orders[0] = TriggerOrder({
            market: trump,
            taker: rite,
            baseAmount: 100 ether,
            quoteLimit: 0,
            price: .3 ether,
            stopLoss: true
        });

        vm.expectRevert(AllInBase.NO_POSITION.selector);
        vm.prank(rite);
        clearingHouse.createTriggerOrders(orders);
    }

    function test_OrderCreator_TriggerOrder_Assertions_InsufficientSize() public {
        TriggerOrder[] memory orders = new TriggerOrder[](1);
        orders[0] = TriggerOrder({
            market: trump,
            taker: rite,
            baseAmount: 100 ether,
            quoteLimit: 0,
            price: .3 ether,
            stopLoss: true
        });

        _createPosition(rite, 50 ether, true);
        _placeBestBidAsk();

        vm.expectRevert(AllInBase.INSUFFICIENT_SIZE.selector);
        vm.prank(rite);
        clearingHouse.createTriggerOrders(orders);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createPosition(address taker, uint amount, bool yes) internal {
        LimitOrder[] memory orders = new LimitOrder[](1);
        orders[0] = LimitOrder({
            market: trump,
            maker: jd,
            baseAmount: amount,
            price: .5 ether,
            bid: !yes,
            reduceOnly: false
        });

        vm.prank(jd);
        clearingHouse.createLimitOrders(orders);

        vm.prank(taker);
        clearingHouse.openPosition(trump, amount, 0, yes);
    }

    function _createBestBidAsk() internal {
        LimitOrder[] memory orders = new LimitOrder[](2);
        orders[0] = LimitOrder({
            market: trump,
            maker: jd,
            baseAmount: 100 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });
        orders[1] = LimitOrder({
            market: trump,
            maker: jd,
            baseAmount: 100 ether,
            price: .5 ether,
            bid: true,
            reduceOnly: false
        });

        vm.prank(jd);
        clearingHouse.createLimitOrders(orders);
    }

    function _placeBestBidAsk() internal {
        LimitOrder[] memory orders = new LimitOrder[](2);
        orders[0] = LimitOrder({
            market: trump,
            maker: jd,
            baseAmount: 100 ether,
            price: .4 ether,
            bid: true,
            reduceOnly: false
        });

        orders[1] = LimitOrder({
            market: trump,
            maker: jd,
            baseAmount: 100 ether,
            price: .6 ether,
            bid: false,
            reduceOnly: false
        });

        vm.prank(jd);
        clearingHouse.createLimitOrders(orders);
    }

}