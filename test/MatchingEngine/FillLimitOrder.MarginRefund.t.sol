// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../AllInTestSetup.sol";
import { AllInBase } from "src/AllInBase.sol";
import { TickBitmap } from "src/utils/TickBitmap.sol";

/// @notice tests functionality of _fillLimitOrder()
/// note: tests valuation of remaining order after a partial fill & margin refund on non-reduceOnly closes
contract MatchingEngine_FillLimitOrder_MarginRefund is AllInTestSetup {
    using AllInMath for *;
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
                    NON-REDUCE-ONLY REFUND: DECREASE
    //////////////////////////////////////////////////////////////*/

    /// @dev tests margin refund on non-reduceOnly decrease
    function test_FillLimit_Decrease_Yes_Profit(
        uint openAmount,
        uint priceOpen,
        uint closeAmount,
        uint priceClose
    ) public {
        openAmount = bound(openAmount, 5 ether, 1000 ether);
        priceOpen = bound(priceOpen, .1 ether, .5 ether);
        closeAmount = bound(closeAmount, 4 ether, openAmount - .01 ether);
        priceClose = bound(priceClose, priceOpen + .1 ether, .9 ether);

        uint fraction = closeAmount.div(openAmount);

        uint positionMargin = clearingHouse.getOrderMarginRequired(openAmount, priceOpen, true);

        position = Position({
            openNotional: openAmount.mul(priceOpen),
            size: int(openAmount),
            margin : positionMargin,
            lastBlock: block.number
        });

        uint closedNotional = position.openNotional.mul(fraction);

        me.placePosition({
            market: trump,
            trader: rite,
            position: position
        });

        order = LimitOrder({
            maker: rite,
            market: trump,
            price: priceClose,
            baseAmount: closeAmount,
            bid: false,
            reduceOnly: false
        });

        assertFalse(order.bid, "NOT CLOSING");

        me.placeLimitOrder(order);

        uint remainingMargin = _getTakerMarginRequired(position.openNotional - closedNotional, position.size - int(closeAmount));
        int rpnl = int(closeAmount.mul(priceClose)) - int(closedNotional);
        uint closedMargin = positionMargin - remainingMargin;

        assertTrue(rpnl > 0, "POSITION IN LOSS");

        margin = _getOrderMarginRequired(order);

        vm.prank(whale);
        usdb.transfer(address(me), margin + positionMargin + uint(rpnl));

        uint balanceBefore = usdb.balanceOf(rite);

        me.fillLimitOrder(order);

        uint balanceAfter = usdb.balanceOf(rite);

        assertEq(int(balanceAfter - balanceBefore), int(closedMargin + margin) + rpnl, "INCORRECT FUNDS RETURNED");
        assertEq(usdb.balanceOf(address(me)), remainingMargin, "INCORRECT PROTOCOL BALANCE");
    }

    function test_FillLimit_Decrease_Yes_Loss(
        uint openAmount,
        uint priceOpen,
        uint closeAmount,
        uint priceClose
    ) public {
        openAmount = bound(openAmount, 5 ether, 1000 ether);
        priceOpen = bound(priceOpen, .5 ether, .9 ether);
        closeAmount = bound(closeAmount, 4 ether, openAmount - .01 ether);
        priceClose = bound(priceClose, .1 ether, priceOpen - .1 ether);

        uint fraction = closeAmount.div(openAmount);

        uint positionMargin = clearingHouse.getOrderMarginRequired(openAmount, priceOpen, true);

        position = Position({
            openNotional: openAmount.mul(priceOpen),
            size: int(openAmount),
            margin : positionMargin,
            lastBlock: block.number
        });

        uint closedNotional = position.openNotional.mul(fraction);

        me.placePosition({
            market: trump,
            trader: rite,
            position: position
        });

        order = LimitOrder({
            maker: rite,
            market: trump,
            price: priceClose,
            baseAmount: closeAmount,
            bid: false,
            reduceOnly: false
        });

        assertFalse(order.bid, "NOT CLOSING");

        me.placeLimitOrder(order);

        uint remainingMargin = _getTakerMarginRequired(position.openNotional - closedNotional, position.size - int(closeAmount));
        int rpnl = int(closeAmount.mul(priceClose)) - int(closedNotional);
        uint closedMargin = positionMargin - remainingMargin;

        assertTrue(rpnl < 0, "POSITION IN PROFIT");

        margin = _getOrderMarginRequired(order);

        vm.prank(whale);
        usdb.transfer(address(me), margin + positionMargin);

        uint balanceBefore = usdb.balanceOf(rite);

        me.fillLimitOrder(order);

        uint balanceAfter = usdb.balanceOf(rite);

        assertEq(int(balanceAfter - balanceBefore), int(closedMargin + margin) + rpnl, "INCORRECT FUNDS RETURNED");
        assertEq(usdb.balanceOf(address(me)), remainingMargin + rpnl.abs(), "INCORRECT PROTOCOL BALANCE");
    }

    function test_FillLimit_Decrease_No_Profit(
        uint openAmount,
        uint priceOpen,
        uint closeAmount,
        uint priceClose
    ) public {
        openAmount = bound(openAmount, 5 ether, 1000 ether);
        priceOpen = bound(priceOpen, .5 ether, .9 ether);
        closeAmount = bound(closeAmount, 4 ether, openAmount - .01 ether);
        priceClose = bound(priceClose, .1 ether, priceOpen - .1 ether);

        uint fraction = closeAmount.div(openAmount);

        uint positionMargin = clearingHouse.getOrderMarginRequired(openAmount, priceOpen, false);

        position = Position({
            openNotional: openAmount.mul(priceOpen),
            size: -int(openAmount),
            margin : positionMargin,
            lastBlock: block.number
        });

        uint closedNotional = position.openNotional.mul(fraction);

        me.placePosition({
            market: trump,
            trader: rite,
            position: position
        });

        order = LimitOrder({
            maker: rite,
            market: trump,
            price: priceClose,
            baseAmount: closeAmount,
            bid: true,
            reduceOnly: false
        });

        assertTrue(order.bid, "NOT CLOSING");

        me.placeLimitOrder(order);

        uint remainingMargin = _getTakerMarginRequired(position.openNotional - closedNotional, position.size + int(closeAmount));
        int rpnl = int(closedNotional) - int(closeAmount.mul(priceClose));
        uint closedMargin = positionMargin - remainingMargin;

        assertTrue(rpnl > 0, "POSITION IN LOSS");

        margin = _getOrderMarginRequired(order);

        vm.prank(whale);
        usdb.transfer(address(me), margin + positionMargin + uint(rpnl));

        uint balanceBefore = usdb.balanceOf(rite);

        me.fillLimitOrder(order);

        uint balanceAfter = usdb.balanceOf(rite);

        assertEq(int(balanceAfter - balanceBefore), int(closedMargin + margin) + rpnl, "INCORRECT FUNDS RETURNED");
        assertEq(usdb.balanceOf(address(me)), remainingMargin, "INCORRECT PROTOCOL BALANCE");
    }

    function test_FillLimit_Decrease_No_Loss(
        uint openAmount,
        uint priceOpen,
        uint closeAmount,
        uint priceClose
    ) public {
        openAmount = bound(openAmount, 5 ether, 1000 ether);
        priceOpen = bound(priceOpen, .1 ether, .5 ether);
        closeAmount = bound(closeAmount, 4 ether, openAmount - .01 ether);
        priceClose = bound(priceClose, priceOpen + .1 ether, .9 ether);

        uint fraction = closeAmount.div(openAmount);

        uint positionMargin = clearingHouse.getOrderMarginRequired(openAmount, priceOpen, false);

        position = Position({
            openNotional: openAmount.mul(priceOpen),
            size: -int(openAmount),
            margin : positionMargin,
            lastBlock: block.number
        });

        uint closedNotional = position.openNotional.mul(fraction);

        me.placePosition({
            market: trump,
            trader: rite,
            position: position
        });

        order = LimitOrder({
            maker: rite,
            market: trump,
            price: priceClose,
            baseAmount: closeAmount,
            bid: true,
            reduceOnly: false
        });

        assertTrue(order.bid, "NOT CLOSING");

        me.placeLimitOrder(order);

        uint remainingMargin = _getTakerMarginRequired(position.openNotional - closedNotional, position.size + int(closeAmount));
        int rpnl = int(closedNotional) - int(closeAmount.mul(priceClose));
        uint closedMargin = positionMargin - remainingMargin;

        assertTrue(rpnl < 0, "POSITION IN PROFIT");

        margin = _getOrderMarginRequired(order);
    
        vm.prank(whale);
        usdb.transfer(address(me), margin + positionMargin);

        uint balanceBefore = usdb.balanceOf(rite);

        me.fillLimitOrder(order);

        uint balanceAfter = usdb.balanceOf(rite);

        assertEq(int(balanceAfter - balanceBefore), int(closedMargin + margin) + rpnl, "INCORRECT FUNDS RETURNED");
        assertEq(usdb.balanceOf(address(me)), remainingMargin + rpnl.abs(), "INCORRECT PROTOCOL BALANCE");
    }

    /*//////////////////////////////////////////////////////////////
                     NON-REDUCE-ONLY REFUND: CLOSE
    //////////////////////////////////////////////////////////////*/

    function test_FillLimit_Close_Yes_Profit(
        uint amount,
        uint priceOpen,
        uint priceClose
    ) public {
        amount = bound(amount, 5 ether, 1000 ether);
        priceOpen = bound(priceOpen, .1 ether, .5 ether);
        priceClose = bound(priceClose, priceOpen + .1 ether, .9 ether);

        uint positionMargin = clearingHouse.getOrderMarginRequired(amount, priceOpen, true);

        position = Position({
            openNotional: amount.mul(priceOpen),
            size: int(amount),
            margin : positionMargin,
            lastBlock: block.number
        });

        me.placePosition({
            market: trump,
            trader: rite,
            position: position
        });

        order = LimitOrder({
            maker: rite,
            market: trump,
            price: priceClose,
            baseAmount: amount,
            bid: false,
            reduceOnly: false
        });

        assertFalse(order.bid, "NOT CLOSING");

        me.placeLimitOrder(order);

        int rpnl = int(amount.mul(priceClose)) - int(position.openNotional);

        assertTrue(rpnl > 0, "POSITION IN LOSS");

        margin = _getOrderMarginRequired(order);

        vm.prank(whale);
        usdb.transfer(address(me), margin + positionMargin + uint(rpnl));

        uint balanceBefore = usdb.balanceOf(rite);

        me.fillLimitOrder(order);

        uint balanceAfter = usdb.balanceOf(rite);

        assertEq(int(balanceAfter - balanceBefore), int(positionMargin + margin) + rpnl, "INCORRECT FUNDS RETURNED");
        assertEq(usdb.balanceOf(address(me)), 0, "INCORRECT PROTOCOL BALANCE");
    }

    function test_FillLimit_Close_Yes_Loss(
        uint amount,
        uint priceOpen,
        uint priceClose
    ) public {
        amount = bound(amount, 5 ether, 1000 ether);
        priceOpen = bound(priceOpen, .5 ether, .9 ether);
        priceClose = bound(priceClose, .1 ether, priceOpen - .1 ether);

        uint positionMargin = clearingHouse.getOrderMarginRequired(amount, priceOpen, true);

        position = Position({
            openNotional: amount.mul(priceOpen),
            size: int(amount),
            margin : positionMargin,
            lastBlock: block.number
        });

        me.placePosition({
            market: trump,
            trader: rite,
            position: position
        });

        order = LimitOrder({
            maker: rite,
            market: trump,
            price: priceClose,
            baseAmount: amount,
            bid: false,
            reduceOnly: false
        });

        assertFalse(order.bid, "NOT CLOSING");

        me.placeLimitOrder(order);

        int rpnl = int(amount.mul(priceClose)) - int(position.openNotional);

        assertTrue(rpnl < 0, "POSITION IN PROFIT");

        margin = _getOrderMarginRequired(order);

        vm.prank(whale);
        usdb.transfer(address(me), margin + positionMargin);

        uint balanceBefore = usdb.balanceOf(rite);

        me.fillLimitOrder(order);

        uint balanceAfter = usdb.balanceOf(rite);

        assertEq(int(balanceAfter - balanceBefore), int(positionMargin + margin) + rpnl, "INCORRECT FUNDS RETURNED");
        assertEq(usdb.balanceOf(address(me)), rpnl.abs(), "INCORRECT PROTOCOL BALANCE");
    }

    function test_FillLimit_Close_No_Profit(
        uint amount,
        uint priceOpen,
        uint priceClose
    ) public {
        amount = bound(amount, 5 ether, 1000 ether);
        priceOpen = bound(priceOpen, .5 ether, .9 ether);
        priceClose = bound(priceClose, .1 ether, priceOpen - .1 ether);

        uint positionMargin = clearingHouse.getOrderMarginRequired(amount, priceOpen, false);

        position = Position({
            openNotional: amount.mul(priceOpen),
            size: -int(amount),
            margin : positionMargin,
            lastBlock: block.number
        });

        me.placePosition({
            market: trump,
            trader: rite,
            position: position
        });

        order = LimitOrder({
            maker: rite,
            market: trump,
            price: priceClose,
            baseAmount: amount,
            bid: true,
            reduceOnly: false
        });

        assertTrue(order.bid, "NOT CLOSING");

        me.placeLimitOrder(order);

        int rpnl = int(position.openNotional) - int(amount.mul(priceClose));

        assertTrue(rpnl > 0, "POSITION IN LOSS");

        margin = _getOrderMarginRequired(order);

        vm.prank(whale);
        usdb.transfer(address(me), margin + positionMargin + uint(rpnl));

        uint balanceBefore = usdb.balanceOf(rite);

        me.fillLimitOrder(order);

        uint balanceAfter = usdb.balanceOf(rite);

        assertEq(int(balanceAfter - balanceBefore), int(positionMargin + margin) + rpnl, "INCORRECT FUNDS RETURNED");
        assertEq(usdb.balanceOf(address(me)), 0, "INCORRECT PROTOCOL BALANCE");
    }

    function test_FillLimit_Close_No_Loss(
        uint amount,
        uint priceOpen,
        uint priceClose
    ) public {
        amount = bound(amount, 5 ether, 1000 ether);
        priceOpen = bound(priceOpen, .1 ether, .5 ether);
        priceClose = bound(priceClose, priceOpen + .1 ether, .9 ether);

        uint positionMargin = clearingHouse.getOrderMarginRequired(amount, priceOpen, false);

        position = Position({
            openNotional: amount.mul(priceOpen),
            size: -int(amount),
            margin : positionMargin,
            lastBlock: block.number
        });

        me.placePosition({
            market: trump,
            trader: rite,
            position: position
        });

        order = LimitOrder({
            maker: rite,
            market: trump,
            price: priceClose,
            baseAmount: amount,
            bid: true,
            reduceOnly: false
        });

        assertTrue(order.bid, "NOT CLOSING");

        me.placeLimitOrder(order);

        int rpnl = int(position.openNotional) - int(amount.mul(priceClose));

        assertTrue(rpnl < 0, "POSITION IN PROFIT");

        margin = _getOrderMarginRequired(order);

        vm.prank(whale);
        usdb.transfer(address(me), margin + positionMargin);

        uint balanceBefore = usdb.balanceOf(rite);

        me.fillLimitOrder(order);

        uint balanceAfter = usdb.balanceOf(rite);

        assertEq(int(balanceAfter - balanceBefore), int(positionMargin + margin) + rpnl, "INCORRECT FUNDS RETURNED");
        assertEq(usdb.balanceOf(address(me)), rpnl.abs(), "INCORRECT PROTOCOL BALANCE");
    }

    /*//////////////////////////////////////////////////////////////
                  NON-REDUCE-ONLY REFUND: REVERSE OPEN
    //////////////////////////////////////////////////////////////*/

    function test_FillLimit_ReverseOpen_Yes_Profit(
        uint openAmount,
        uint priceOpen,
        uint reverseAmount,
        uint priceReverse
    ) public {
        openAmount = bound(openAmount, 5 ether, 1000 ether);
        priceOpen = bound(priceOpen, .1 ether, .5 ether);
        reverseAmount = bound(reverseAmount, openAmount + .1 ether, 5000 ether);
        priceReverse = bound(priceReverse, priceOpen + .1 ether, .9 ether);

        uint positionMargin = clearingHouse.getOrderMarginRequired(openAmount, priceOpen, true);

        position = Position({
            openNotional: openAmount.mul(priceOpen),
            size: int(openAmount),
            margin : positionMargin,
            lastBlock: block.number
        });

        me.placePosition({
            market: trump,
            trader: rite,
            position: position
        });

        order = LimitOrder({
            maker: rite,
            market: trump,
            price: priceReverse,
            baseAmount: reverseAmount,
            bid: false,
            reduceOnly: false
        });

        assertFalse(order.bid, "NOT CLOSING");

        me.placeLimitOrder(order);

        int rpnl = int(openAmount.mul(priceReverse)) - int(position.openNotional);

        assertTrue(rpnl > 0, "POSITION IN LOSS");

        margin = _getOrderMarginRequired(order);

        uint newPositionMargin = clearingHouse.getOrderMarginRequired(reverseAmount - openAmount, priceReverse, false);

        vm.prank(whale);
        usdb.transfer(address(me), margin + positionMargin + uint(rpnl));

        uint balanceBefore = usdb.balanceOf(rite);

        me.fillLimitOrder(order);

        uint balanceAfter = usdb.balanceOf(rite);

        assertEq(int(balanceAfter - balanceBefore), int(positionMargin + margin - newPositionMargin) + rpnl, "INCORRECT FUNDS RETURNED");
        assertEq(usdb.balanceOf(address(me)), newPositionMargin, "INCORRECT PROTOCOL BALANCE");
    }

    function test_FillLimit_ReverseOpen_Yes_Loss(
        uint openAmount,
        uint priceOpen,
        uint reverseAmount,
        uint priceReverse
    ) public {
        openAmount = bound(openAmount, 5 ether, 1000 ether);
        priceOpen = bound(priceOpen, .5 ether, .9 ether);
        reverseAmount = bound(reverseAmount, openAmount + .1 ether, 5000 ether);
        priceReverse = bound(priceReverse, .1 ether, priceOpen - .1 ether);

        uint positionMargin = clearingHouse.getOrderMarginRequired(openAmount, priceOpen, true);

        position = Position({
            openNotional: openAmount.mul(priceOpen),
            size: int(openAmount),
            margin : positionMargin,
            lastBlock: block.number
        });

        me.placePosition({
            market: trump,
            trader: rite,
            position: position
        });

        order = LimitOrder({
            maker: rite,
            market: trump,
            price: priceReverse,
            baseAmount: reverseAmount,
            bid: false,
            reduceOnly: false
        });

        assertFalse(order.bid, "NOT CLOSING");

        me.placeLimitOrder(order);

        int rpnl = int(openAmount.mul(priceReverse)) - int(position.openNotional);

        assertTrue(rpnl < 0, "POSITION IN PROFIT");

        margin = _getOrderMarginRequired(order);

        uint newPositionMargin = clearingHouse.getOrderMarginRequired(reverseAmount - openAmount, priceReverse, false);

        vm.prank(whale);
        usdb.transfer(address(me), margin + positionMargin);

        uint balanceBefore = usdb.balanceOf(rite);

        me.fillLimitOrder(order);

        uint balanceAfter = usdb.balanceOf(rite);

        assertEq(int(balanceAfter - balanceBefore), int(positionMargin + margin - newPositionMargin) + rpnl, "INCORRECT FUNDS RETURNED");
        assertEq(usdb.balanceOf(address(me)), newPositionMargin + rpnl.abs(), "INCORRECT PROTOCOL BALANCE");
    }

    function test_FillLimit_ReverseOpen_No_Profit(
        uint openAmount,
        uint priceOpen,
        uint reverseAmount,
        uint priceReverse
    ) public {
        openAmount = bound(openAmount, 5 ether, 1000 ether);
        priceOpen = bound(priceOpen, .5 ether, .9 ether);
        reverseAmount = bound(reverseAmount, openAmount + .1 ether, 5000 ether);
        priceReverse = bound(priceReverse, .1 ether, priceOpen - .1 ether);

        uint positionMargin = clearingHouse.getOrderMarginRequired(openAmount, priceOpen, false);

        position = Position({
            openNotional: openAmount.mul(priceOpen),
            size: -int(openAmount),
            margin : positionMargin,
            lastBlock: block.number
        });

        me.placePosition({
            market: trump,
            trader: rite,
            position: position
        });

        order = LimitOrder({
            maker: rite,
            market: trump,
            price: priceReverse,
            baseAmount: reverseAmount,
            bid: true,
            reduceOnly: false
        });

        assertTrue(order.bid, "NOT CLOSING");

        int rpnl = int(position.openNotional) - int(openAmount.mul(priceReverse));

        assertTrue(rpnl > 0, "POSITION IN LOSS");

        margin = _getOrderMarginRequired(order);

        uint newPositionMargin = clearingHouse.getOrderMarginRequired(reverseAmount - openAmount, priceReverse, true);

        vm.prank(whale);
        usdb.transfer(address(me), margin + positionMargin + uint(rpnl));

        uint balanceBefore = usdb.balanceOf(rite);

        me.fillLimitOrder(order);

        uint balanceAfter = usdb.balanceOf(rite);

        assertEq(int(balanceAfter - balanceBefore), int(positionMargin + margin - newPositionMargin) + rpnl, "INCORRECT FUNDS RETURNED");
        assertEq(usdb.balanceOf(address(me)), newPositionMargin, "INCORRECT PROTOCOL BALANCE");
    }

    function test_FillLimit_ReverseOpen_No_Loss(
        uint openAmount,
        uint priceOpen,
        uint reverseAmount,
        uint priceReverse
    ) public {
        openAmount = bound(openAmount, 5 ether, 1000 ether);
        priceOpen = bound(priceOpen, .1 ether, .5 ether);
        reverseAmount = bound(reverseAmount, openAmount + .1 ether, 5000 ether);
        priceReverse = bound(priceReverse, priceOpen + .1 ether, .9 ether);

        uint positionMargin = clearingHouse.getOrderMarginRequired(openAmount, priceOpen, false);

        position = Position({
            openNotional: openAmount.mul(priceOpen),
            size: -int(openAmount),
            margin : positionMargin,
            lastBlock: block.number
        });

        me.placePosition({
            market: trump,
            trader: rite,
            position: position
        });

        order = LimitOrder({
            maker: rite,
            market: trump,
            price: priceReverse,
            baseAmount: reverseAmount,
            bid: true,
            reduceOnly: false
        });

        assertTrue(order.bid, "NOT CLOSING");

        int rpnl = int(position.openNotional) - int(openAmount.mul(priceReverse));

        assertTrue(rpnl < 0, "POSITION IN PROFIT");

        margin = _getOrderMarginRequired(order);

        uint newPositionMargin = clearingHouse.getOrderMarginRequired(reverseAmount - openAmount, priceReverse, true);

        vm.prank(whale);
        usdb.transfer(address(me), margin + positionMargin);

        uint balanceBefore = usdb.balanceOf(rite);

        me.fillLimitOrder(order);

        uint balanceAfter = usdb.balanceOf(rite);

        assertEq(int(balanceAfter - balanceBefore), int(positionMargin + margin - newPositionMargin) + rpnl, "INCORRECT FUNDS RETURNED");
        assertEq(usdb.balanceOf(address(me)), newPositionMargin + rpnl.abs(), "INCORRECT PROTOCOL BALANCE");
    }


}

/*//////////////////////////////////////////////////////////////
                            MOCK CONTRACT
//////////////////////////////////////////////////////////////*/

contract ME_FillLimitOrder is MatchingEngine {
    using TickBitmap for mapping(int16 => uint256);

    bool constant public IS_SCRIPT = true;

    constructor(address usdb_) MatchingEngine(usdb_) {}

    function getPosition(uint160 market, address trader) external view returns (Position memory) {
        return _position[market][trader];
    }

    function fillLimitOrder(LimitOrder memory order) external {
        _fillLimitOrder(order);
    }

    function cloneLimitOrder(LimitOrder memory order) external pure returns (LimitOrder memory) {
        return _cloneLimitOrder(order);
    }

    function placePosition(
        uint160 market,
        address trader,
        Position memory position
    ) external {
        _position[market][trader] = position;
        _openInterest[market] += position.openNotional;
    }

    function placeLimitOrder(LimitOrder memory order) external returns (uint id) {
        _limitOrder[id = ++_orderCounter] = order;

        if (order.reduceOnly) _linkedLimitOrders[order.maker][order.market].push(id);

        int24 tick = _priceToTick(order.price);

        if (_tick[order.market][tick].length == 0) _book[order.market].flipTick(tick, 1);

        _tick[order.market][tick].push(id);
    }
}
    