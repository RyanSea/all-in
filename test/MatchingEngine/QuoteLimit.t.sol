// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../AllInTestSetup.sol";

contract MatchingEngine_QuoteLimit is AllInTestSetup {
    using AllInMath for *;

    function test_QuoteLimit_Open_Yes() public {
        LimitOrder[] memory orders = new LimitOrder[](2);

        LimitOrder memory goodOrder1 = orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 50 ether,
            price: .6 ether,
            bid: false,
            reduceOnly: false
        });
        orders[1] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 100 ether,
            price: .8 ether,
            bid: false,
            reduceOnly: false
        });

        LimitOrder memory goodOrder2 = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 50 ether,
            price: .7 ether,
            bid: false,
            reduceOnly: false
        });

        uint quoteLimit = goodOrder1.baseAmount.mul(goodOrder1.price) + goodOrder2.baseAmount.mul(goodOrder2.price);

        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        orders = new LimitOrder[](1);
        orders[0] = goodOrder2;

        vm.expectRevert(MatchingEngine.QUOTE_LIMIT_EXCEEDED.selector);
        vm.prank(rite);
        clearingHouse.openPosition(trump, 100 ether, quoteLimit, true);

        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        vm.prank(rite);
        clearingHouse.openPosition(trump, 100 ether, quoteLimit, true);
    }

    function test_QuoteLimit_Open_No() public {
        LimitOrder[] memory orders = new LimitOrder[](2);

        LimitOrder memory goodOrder1 = orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 50 ether,
            price: .4 ether,
            bid: true,
            reduceOnly: false
        });
        orders[1] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 100 ether,
            price: .2 ether,
            bid: true,
            reduceOnly: false
        });

        LimitOrder memory goodOrder2 = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 50 ether,
            price: .3 ether,
            bid: true,
            reduceOnly: false
        });

        uint quoteLimit = goodOrder1.baseAmount.mul(goodOrder1.price) + goodOrder2.baseAmount.mul(goodOrder2.price);

        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        vm.expectRevert(MatchingEngine.QUOTE_LIMIT_UNMET.selector);
        vm.prank(rite);
        clearingHouse.openPosition(trump, 100 ether, quoteLimit, false);

        orders = new LimitOrder[](1);
        orders[0] = goodOrder2;

        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        vm.prank(rite);
        clearingHouse.openPosition(trump, 100 ether, quoteLimit, false);
    }

    function test_QuoteLimit_Close_Yes() public {
        LimitOrder[] memory orders = new LimitOrder[](1);

        orders[0] = LimitOrder({
            market: trump,
            maker: jd,
            baseAmount: 100 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });

        vm.prank(jd);
        clearingHouse.createLimitOrders(orders);

        vm.prank(rite);
        clearingHouse.openPosition(trump, 100 ether, 0, true);

        vm.roll(block.number + 1);

        orders = new LimitOrder[](2);

        LimitOrder memory goodOrder1 = orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 50 ether,
            price: .4 ether,
            bid: true,
            reduceOnly: false
        });
        orders[1] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 100 ether,
            price: .2 ether,
            bid: true,
            reduceOnly: false
        });

        LimitOrder memory goodOrder2 = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 50 ether,
            price: .3 ether,
            bid: true,
            reduceOnly: false
        });

        uint quoteLimit = goodOrder1.baseAmount.mul(goodOrder1.price) + goodOrder2.baseAmount.mul(goodOrder2.price);

        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        vm.expectRevert(MatchingEngine.QUOTE_LIMIT_UNMET.selector);
        vm.prank(rite);
        clearingHouse.closePosition(trump, 100 ether, quoteLimit);

        orders = new LimitOrder[](1);
        orders[0] = goodOrder2;

        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        vm.prank(rite);
        clearingHouse.closePosition(trump, 100 ether, quoteLimit);
    }

    function test_QuoteLimit_Close_No() public {
        LimitOrder[] memory orders = new LimitOrder[](1);

        orders[0] = LimitOrder({
            market: trump,
            maker: jd,
            baseAmount: 100 ether,
            price: .5 ether,
            bid: true,
            reduceOnly: false
        });

        vm.prank(jd);
        clearingHouse.createLimitOrders(orders);

        vm.prank(rite);
        clearingHouse.openPosition(trump, 100 ether, 0, false);

        vm.roll(block.number + 1);

        orders = new LimitOrder[](2);

        LimitOrder memory goodOrder1 = orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 50 ether,
            price: .6 ether,
            bid: false,
            reduceOnly: false
        });
        orders[1] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 100 ether,
            price: .8 ether,
            bid: false,
            reduceOnly: false
        });

        LimitOrder memory goodOrder2 = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 50 ether,
            price: .7 ether,
            bid: false,
            reduceOnly: false
        });

        uint quoteLimit = goodOrder1.baseAmount.mul(goodOrder1.price) + goodOrder2.baseAmount.mul(goodOrder2.price);

        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        orders = new LimitOrder[](1);
        orders[0] = goodOrder2;

        vm.expectRevert(MatchingEngine.QUOTE_LIMIT_EXCEEDED.selector);
        vm.prank(rite);
        clearingHouse.closePosition(trump, 100 ether, quoteLimit);

        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        vm.prank(rite);
        clearingHouse.closePosition(trump, 100 ether, quoteLimit);
    }
}