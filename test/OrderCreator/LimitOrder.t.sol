// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../AllInTestSetup.sol";

import { AllInBase } from "src/AllInBase.sol";

contract OrderCreator_LimitOrderTest is AllInTestSetup {
    using AllInMath for uint256;

    uint makerBalBefore;
    uint protocolBalBefore;
    uint margin;

    /*//////////////////////////////////////////////////////////////
                           LIMIT ORDER CREATE
    //////////////////////////////////////////////////////////////*/

    function test_OrderCreator_LimitOrder_Create() public {
        LimitOrder[] memory orders = new LimitOrder[](2);

        LimitOrder memory order1 = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .7 ether,
            bid: false,
            reduceOnly: false
        });
        LimitOrder memory order2 = orders[1] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .3 ether,
            bid: true,
            reduceOnly: false
        });

        /// BOOK STORAGE BEFORE ///
        _checkTickInitialized(order1, false);
        _checkTickInitialized(order2, false);
        _checkOrdersOnTickAmount(order1.market, order1.price, 0);
        _checkOrdersOnTickAmount(order2.market, order2.price, 0);

        margin += _getOrderMarginRequired(order1);
        margin += _getOrderMarginRequired(order2);

        makerBalBefore = usdb.balanceOf(rite);
        protocolBalBefore = usdb.balanceOf(address(clearingHouse));

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.LimitOrderUpdated({
            id: 1,
            market: order1.market,
            maker: order1.maker,
            baseAmount: order1.baseAmount,
            price: order1.price,
            bid: order1.bid,
            reduceOnly: order1.reduceOnly,
            fill: false
        });
        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.LimitOrderUpdated({
            id: 2,
            market: order2.market,
            maker: order2.maker,
            baseAmount: order2.baseAmount,
            price: order2.price,
            bid: order2.bid,
            reduceOnly: order2.reduceOnly,
            fill: false
        });
        vm.prank(rite);
        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        /// ORDERS STORAGE ///
        assertEq(ids[0], 1, "INCORRECT ID");
        assertEq(ids[1], 2, "INCORRECT ID");
        _checkOrdersInStorage(ids, orders);

        uint256[] memory idsExpected1 = new uint256[](1);
        idsExpected1[0] = 1;
        uint256[] memory idsExpected2 = new uint256[](1);
        idsExpected2[0] = 2;

        /// BOOK STORAGE AFTER ///
        _checkTickInitialized(order1, true);
        _checkTickInitialized(order2, true);
        _checkOrdersOnTick(order1.market, order1.price, idsExpected1);
        _checkOrdersOnTick(order2.market, order2.price, idsExpected2);

        /// BEST PRICE ///
        assertEq(clearingHouse.getBestPrice(trump, true), order2.price, "INCORRECT BEST PRICE");
        assertEq(clearingHouse.getBestPrice(trump, false), order1.price, "INCORRECT BEST PRICE");

        /// MARGIN ///
        assertEq(usdb.balanceOf(rite), makerBalBefore - margin, "INCORRECT MAKER BALANCE");
        assertEq(usdb.balanceOf(address(clearingHouse)), protocolBalBefore + margin, "INCORRECT PROTOCOL BALANCE");
    }

    /*//////////////////////////////////////////////////////////////
                           LIMIT ORDER UPDATE
    //////////////////////////////////////////////////////////////*/

    function test_OrderCreator_LimitOrder_Update_NewTick_IncreaseMargin() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        LimitOrder memory oldOrder = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .7 ether,
            bid: false,
            reduceOnly: false
        });

        vm.startPrank(rite);
        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        LimitOrder memory newOrder = orders[0] = LimitOrder({
            market: oldOrder.market,
            maker: oldOrder.maker,
            baseAmount : oldOrder.baseAmount,
            price: oldOrder.price - .1 ether,
            bid: oldOrder.bid,
            reduceOnly: oldOrder.reduceOnly
        });

        uint marginIncrease = _getOrderMarginRequired(newOrder) - _getOrderMarginRequired(oldOrder);

        makerBalBefore = usdb.balanceOf(rite);
        protocolBalBefore = usdb.balanceOf(address(clearingHouse));

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.LimitOrderUpdated({
            id: 1,
            market: newOrder.market,
            maker: newOrder.maker,
            baseAmount: newOrder.baseAmount,
            price: newOrder.price,
            bid: newOrder.bid,
            reduceOnly: newOrder.reduceOnly,
            fill: false
        });
        clearingHouse.updateLimitOrders(ids, orders);

        /// BOOK STORAGE OLD ORDER ///
        _checkTickInitialized(oldOrder, false);
        _checkOrdersOnTickAmount(oldOrder.market, oldOrder.price, 0);

        /// BOOK STORAGE NEW ORDER ///
        _checkTickInitialized(newOrder, true);
        _checkOrdersOnTick(newOrder.market, newOrder.price, ids);

        /// BEST PRICE ///
        assertEq(clearingHouse.getBestPrice(trump, newOrder.bid), newOrder.price, "INCORRECT BEST PRICE");

        /// MARGIN ///
        assertEq(usdb.balanceOf(rite), makerBalBefore - marginIncrease, "INCORRECT MAKER BALANCE");
        assertEq(usdb.balanceOf(address(clearingHouse)), protocolBalBefore + marginIncrease, "INCORRECT PROTOCOL BALANCE");
    }

    function test_OrderCreator_LimitOrder_Update_NewTick_DecreaseMargin() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        LimitOrder memory oldOrder = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .7 ether,
            bid: false,
            reduceOnly: false
        });

        vm.startPrank(rite);
        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        LimitOrder memory newOrder = orders[0] = LimitOrder({
            market: oldOrder.market,
            maker: oldOrder.maker,
            baseAmount : oldOrder.baseAmount,
            price: oldOrder.price + .1 ether,
            bid: oldOrder.bid,
            reduceOnly: oldOrder.reduceOnly
        });

        uint marginDecrease = _getOrderMarginRequired(oldOrder) - _getOrderMarginRequired(newOrder);

        makerBalBefore = usdb.balanceOf(rite);
        protocolBalBefore = usdb.balanceOf(address(clearingHouse));

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.LimitOrderUpdated({
            id: 1,
            market: newOrder.market,
            maker: newOrder.maker,
            baseAmount: newOrder.baseAmount,
            price: newOrder.price,
            bid: newOrder.bid,
            reduceOnly: newOrder.reduceOnly,
            fill: false
        });
        clearingHouse.updateLimitOrders(ids, orders);

        /// BOOK STORAGE OLD ORDER ///
        _checkTickInitialized(oldOrder, false);
        _checkOrdersOnTickAmount(oldOrder.market, oldOrder.price, 0);

        /// BOOK STORAGE NEW ORDER ///
        _checkTickInitialized(newOrder, true);
        _checkOrdersOnTick(newOrder.market, newOrder.price, ids);

        /// BEST PRICE ///
        assertEq(clearingHouse.getBestPrice(trump, newOrder.bid), newOrder.price, "INCORRECT BEST PRICE");

        /// MARGIN ///
        assertEq(usdb.balanceOf(rite), makerBalBefore + marginDecrease, "INCORRECT MAKER BALANCE");
        assertEq(usdb.balanceOf(address(clearingHouse)), protocolBalBefore - marginDecrease, "INCORRECT PROTOCOL BALANCE");
    }

    function test_OrderCreator_LimitOrder_Update_SameTick_IncreaseMargin() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        LimitOrder memory oldOrder = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .7 ether,
            bid: false,
            reduceOnly: false
        });

        vm.startPrank(rite);
        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        LimitOrder memory newOrder = orders[0] = LimitOrder({
            market: oldOrder.market,
            maker: oldOrder.maker,
            baseAmount : oldOrder.baseAmount + 10 ether,
            price: oldOrder.price,
            bid: oldOrder.bid,
            reduceOnly: oldOrder.reduceOnly
        });

        uint marginIncrease = _getOrderMarginRequired(newOrder) - _getOrderMarginRequired(oldOrder);

        makerBalBefore = usdb.balanceOf(rite);
        protocolBalBefore = usdb.balanceOf(address(clearingHouse));

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.LimitOrderUpdated({
            id: 1,
            market: newOrder.market,
            maker: newOrder.maker,
            baseAmount: newOrder.baseAmount,
            price: newOrder.price,
            bid: newOrder.bid,
            reduceOnly: newOrder.reduceOnly,
            fill: false
        });
        clearingHouse.updateLimitOrders(ids, orders);

        /// BOOK STORAGE OLD ///
        _checkTickInitialized(oldOrder, true);
        _checkOrdersOnTickAmount(oldOrder.market, oldOrder.price, 1);

        /// BEST PRICE ///
        assertEq(clearingHouse.getBestPrice(trump, oldOrder.bid), oldOrder.price, "INCORRECT BEST PRICE");

        /// MARGIN ///
        assertEq(usdb.balanceOf(rite), makerBalBefore - marginIncrease, "INCORRECT MAKER BALANCE");
        assertEq(usdb.balanceOf(address(clearingHouse)), protocolBalBefore + marginIncrease, "INCORRECT PROTOCOL BALANCE");
    }

    function test_OrderCreator_LimitOrder_Update_SameTick_DecreaseMargin() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        LimitOrder memory oldOrder = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .7 ether,
            bid: false,
            reduceOnly: false
        });

        vm.startPrank(rite);
        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        LimitOrder memory newOrder = orders[0] = LimitOrder({
            market: oldOrder.market,
            maker: oldOrder.maker,
            baseAmount : oldOrder.baseAmount - 1 ether,
            price: oldOrder.price,
            bid: oldOrder.bid,
            reduceOnly: oldOrder.reduceOnly
        });

        uint marginDecrease = _getOrderMarginRequired(oldOrder) - _getOrderMarginRequired(newOrder);

        makerBalBefore = usdb.balanceOf(rite);
        protocolBalBefore = usdb.balanceOf(address(clearingHouse));

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.LimitOrderUpdated({
            id: 1,
            market: newOrder.market,
            maker: newOrder.maker,
            baseAmount: newOrder.baseAmount,
            price: newOrder.price,
            bid: newOrder.bid,
            reduceOnly: newOrder.reduceOnly,
            fill: false
        });
        clearingHouse.updateLimitOrders(ids, orders);

        /// BOOK STORAGE OLD ///
        _checkTickInitialized(oldOrder, true);
        _checkOrdersOnTickAmount(oldOrder.market, oldOrder.price, 1);

        /// BEST PRICE ///
        assertEq(clearingHouse.getBestPrice(trump, oldOrder.bid), oldOrder.price, "INCORRECT BEST PRICE");

        /// MARGIN ///
        assertEq(usdb.balanceOf(rite), makerBalBefore + marginDecrease, "INCORRECT MAKER BALANCE");
        assertEq(usdb.balanceOf(address(clearingHouse)), protocolBalBefore - marginDecrease, "INCORRECT PROTOCOL BALANCE");
    }

    function test_OrderCreator_LimitOrder_Update_NewMarket() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        LimitOrder memory oldOrder = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .7 ether,
            bid: false,
            reduceOnly: false
        });

        vm.startPrank(rite);
        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        LimitOrder memory newOrder = orders[0] = LimitOrder({
            market: sport,
            maker: oldOrder.maker,
            baseAmount : oldOrder.baseAmount,
            price: oldOrder.price,
            bid: oldOrder.bid,
            reduceOnly: oldOrder.reduceOnly
        });

        makerBalBefore = usdb.balanceOf(rite);
        protocolBalBefore = usdb.balanceOf(address(clearingHouse));

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.LimitOrderUpdated({
            id: 1,
            market: newOrder.market,
            maker: newOrder.maker,
            baseAmount: newOrder.baseAmount,
            price: newOrder.price,
            bid: newOrder.bid,
            reduceOnly: newOrder.reduceOnly,
            fill: false
        });
        clearingHouse.updateLimitOrders(ids, orders);

        /// BOOK STORAGE OLD ORDER ///
        _checkTickInitialized(oldOrder, false);
        _checkOrdersOnTickAmount(oldOrder.market, oldOrder.price, 0);

        /// BOOK STORAGE NEW ORDER ///
        _checkTickInitialized(newOrder, true);
        _checkOrdersOnTick(newOrder.market, newOrder.price, ids);

        /// BEST PRICE OLD ORDER///
        assertEq(clearingHouse.getBestPrice(trump, oldOrder.bid), oldOrder.bid ? minPrice : maxPrice, "INCORRECT BEST PRICE");

        /// BEST PRICE NEW ORDER ///
        assertEq(clearingHouse.getBestPrice(sport, newOrder.bid), newOrder.price, "INCORRECT BEST PRICE");

        /// MARGIN ///
        assertEq(usdb.balanceOf(rite), makerBalBefore, "INCORRECT MAKER BALANCE");
        assertEq(usdb.balanceOf(address(clearingHouse)), protocolBalBefore, "INCORRECT PROTOCOL BALANCE");
    }

    function test_OrderCreator_LimitOrder_Update_ToReduceOnly() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount : 50 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });
        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        vm.startPrank(rite);
        clearingHouse.openPosition(trump, 50 ether, 0, true);

        LimitOrder memory order = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 30 ether,
            price: .4 ether,
            bid: false,
            reduceOnly: false
        });

        uint[] memory ids = clearingHouse.createLimitOrders(orders);
        uint[] memory linkedIds = clearingHouse.getLinkedLimitOrders(order.market, order.maker);

        /// REDUCE ONLY LINK BEFORE ///
        assertEq(linkedIds.length, 0, "SHOULD NOT BE LINKED");

        margin = _getOrderMarginRequired(order);

        order.reduceOnly = true;

        makerBalBefore = usdb.balanceOf(rite);
        protocolBalBefore = usdb.balanceOf(address(clearingHouse));

        clearingHouse.updateLimitOrders(ids, orders);

        linkedIds = clearingHouse.getLinkedLimitOrders(order.market, order.maker);

        /// REDUCE ONLY LINK AFTER ///
        assertEq(linkedIds.length, 1, "SHOULD BE LINKED");
        assertEq(linkedIds[0], ids[0], "INCORRECT LINKED ID");

        /// BOOK STORAGE ///
        _checkTickInitialized(order, true);
        _checkOrdersOnTick(order.market, order.price, ids);

        /// BEST PRICE ///
        assertEq(clearingHouse.getBestPrice(trump, order.bid), order.price, "INCORRECT BEST PRICE");

        /// MARGIN ///
        assertEq(usdb.balanceOf(rite) - makerBalBefore, margin, "INCORRECT MAKER BALANCE");
        assertEq(protocolBalBefore - usdb.balanceOf(address(clearingHouse)), margin, "INCORRECT PROTOCOL BALANCE");
    }

    function test_OrderCreator_LimitOrder_Update_FromReduceOnly() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount : 50 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });
        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        vm.startPrank(rite);
        clearingHouse.openPosition(trump, 50 ether, 0, true);

        LimitOrder memory order = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 30 ether,
            price: .4 ether,
            bid: false,
            reduceOnly: true
        });

        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        uint[] memory linkedIds = clearingHouse.getLinkedLimitOrders(order.market, order.maker);

        /// REDUCE ONLY LINK BEFORE ///
        assertEq(linkedIds.length, 1, "SHOULD BE LINKED");
        assertEq(linkedIds[0], ids[0], "INCORRECT LINKED ID");

        order.reduceOnly = false;

        margin = _getOrderMarginRequired(order);

        makerBalBefore = usdb.balanceOf(rite);
        protocolBalBefore = usdb.balanceOf(address(clearingHouse));

        clearingHouse.updateLimitOrders(ids, orders);

        linkedIds = clearingHouse.getLinkedLimitOrders(order.market, order.maker);

        /// REDUCE ONLY LINK AFTER ///
        assertEq(linkedIds.length, 0, "SHOULD NOT BE LINKED");

        /// BOOK STORAGE ///
        _checkTickInitialized(order, true);
        _checkOrdersOnTick(order.market, order.price, ids);

        /// BEST PRICE ///
        assertEq(clearingHouse.getBestPrice(trump, order.bid), order.price, "INCORRECT BEST PRICE");

        /// MARGIN ///
        assertEq(makerBalBefore - usdb.balanceOf(rite), margin, "INCORRECT MAKER BALANCE");
        assertEq(usdb.balanceOf(address(clearingHouse)) - protocolBalBefore, margin, "INCORRECT PROTOCOL BALANCE");
    }

    function test_OrderCreator_LimitOrder_Update_ReduceOnlyToReduceOnly() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount : 50 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });
        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        vm.startPrank(rite);
        clearingHouse.openPosition(trump, 50 ether, 0, true);

        LimitOrder memory order = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 30 ether,
            price: .4 ether,
            bid: false,
            reduceOnly: true
        });

        uint[] memory ids = clearingHouse.createLimitOrders(orders);
        uint[] memory linkedIds = clearingHouse.getLinkedLimitOrders(order.market, order.maker);

        /// REDUCE ONLY LINK BEFORE ///
        assertEq(linkedIds.length, 1, "SHOULD BE LINKED");
        assertEq(linkedIds[0], ids[0], "INCORRECT LINKED ID");

        order.price = .35 ether;

        makerBalBefore = usdb.balanceOf(rite);
        protocolBalBefore = usdb.balanceOf(address(clearingHouse));

        clearingHouse.updateLimitOrders(ids, orders);

        linkedIds = clearingHouse.getLinkedLimitOrders(order.market, order.maker);

        /// REDUCE ONLY LINK AFTER ///
        assertEq(linkedIds.length, 1, "SHOULD BE LINKED");
        assertEq(linkedIds[0], ids[0], "INCORRECT LINKED ID");

        /// BOOK STORAGE ///
        _checkTickInitialized(order, true);
        _checkOrdersOnTick(order.market, order.price, ids);

        /// BEST PRICE ///
        assertEq(clearingHouse.getBestPrice(trump, order.bid), order.price, "INCORRECT BEST PRICE");

        /// MARGIN ///
        assertEq(usdb.balanceOf(rite), makerBalBefore, "INCORRECT MAKER BALANCE");
        assertEq(usdb.balanceOf(address(clearingHouse)), protocolBalBefore, "INCORRECT PROTOCOL BALANCE");
    }

    /*//////////////////////////////////////////////////////////////
                           LIMIT ORDER DELETE
    //////////////////////////////////////////////////////////////*/

    function test_OrderCreator_LimitOrder_Delete() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        LimitOrder memory order1 = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .7 ether,
            bid: true,
            reduceOnly: false
        });


        vm.startPrank(rite);
        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        LimitOrder memory order2 = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .3 ether,
            bid: true,
            reduceOnly: false
        });

        clearingHouse.createLimitOrders(orders);

        margin = _getOrderMarginRequired(order1);

        makerBalBefore = usdb.balanceOf(rite);
        protocolBalBefore = usdb.balanceOf(address(clearingHouse));

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.LimitOrderRemoved({
            id: ids[0],
            filled: false
        });
        clearingHouse.deleteLimitOrders(ids);

        /// BOOK STORAGE ///
        _checkTickInitialized(order1, false);
        _checkOrdersOnTickAmount(order1.market, order1.price, 0);

        /// BEST PRICE ///
        assertEq(clearingHouse.getBestPrice(trump, true), order2.price, "INCORRECT BEST PRICE");

        /// MARGIN ///
        assertEq(usdb.balanceOf(rite), makerBalBefore + margin, "INCORRECT MAKER BALANCE");
        assertEq(usdb.balanceOf(address(clearingHouse)), protocolBalBefore - margin, "INCORRECT PROTOCOL BALANCE");
    }

    function test_OrderCreator_LimitOrder_AdminDelete() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        LimitOrder memory order1 = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .7 ether,
            bid: true,
            reduceOnly: false
        });

        vm.prank(rite);
        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        margin = _getOrderMarginRequired(order1);

        makerBalBefore = usdb.balanceOf(rite);
        protocolBalBefore = usdb.balanceOf(address(clearingHouse));

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit AllInBase.LimitOrderRemoved({
            id: ids[0],
            filled: false
        });
        vm.prank(owner);
        clearingHouse.adminDeleteLimitOrders(ids);

        /// BOOK STORAGE ///
        _checkTickInitialized(order1, false);
        _checkOrdersOnTickAmount(order1.market, order1.price, 0);

        /// BEST PRICE ///
        assertEq(clearingHouse.getBestPrice(trump, true), minPrice, "INCORRECT BEST PRICE");

        /// MARGIN ///
        assertEq(usdb.balanceOf(rite) - makerBalBefore, margin, "INCORRECT MAKER BALANCE");
        assertEq(protocolBalBefore - usdb.balanceOf(address(clearingHouse)), margin, "INCORRECT PROTOCOL BALANCE");
    }

    /*//////////////////////////////////////////////////////////////
                           CREATE ASSERTIONS
    //////////////////////////////////////////////////////////////*/

    function test_OrderCreator_LimitOrder_Assertions_Create_NotMaker() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount : 50 ether,
            price: .7 ether,
            bid: true,
            reduceOnly: false
        });

        vm.expectRevert(OrderCreator.NOT_MAKER.selector);
        vm.prank(rite);
        clearingHouse.createLimitOrders(orders);
    }

    function test_OrderCreator_LimitOrder_Assertions_Create_InvalidTick() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        LimitOrder memory order = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: minPrice - 1,
            bid: true,
            reduceOnly: false
        });

        vm.startPrank(rite);

        // note: price under min
        vm.expectRevert(OrderCreator.INVALID_LIMIT_PRICE.selector);
        clearingHouse.createLimitOrders(orders);

        order.price = .5 ether + 1;

        // note: invalid tick
        vm.expectRevert(OrderCreator.INVALID_LIMIT_PRICE.selector);
        clearingHouse.createLimitOrders(orders);

        order.price = maxPrice + 1;

        // note: price over max
        vm.expectRevert(OrderCreator.INVALID_LIMIT_PRICE.selector);
        clearingHouse.createLimitOrders(orders);
    }

    function test_OrderCreator_LimitOrder_Assertions_Create_BestPrice() public {
        LimitOrder[] memory orders = new LimitOrder[](2);
        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount : 50 ether,
            price: .4 ether,
            bid: true,
            reduceOnly: false
        });
        orders[1] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount : 50 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });

        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        orders = new LimitOrder[](1);

        orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .4 ether - .001 ether,
            bid: false,
            reduceOnly: false
        });

        vm.startPrank(rite);
        vm.expectRevert(OrderCreator.ASK_BELOW_BID.selector);
        clearingHouse.createLimitOrders(orders);

        orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .5 ether + .001 ether,
            bid: true,
            reduceOnly: false
        });

        vm.expectRevert(OrderCreator.BID_ABOVE_ASK.selector);
        clearingHouse.createLimitOrders(orders);
    }

    function test_OrderCreator_LimitOrder_Assertions_Create_ReduceOnly_NoPosition() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount : 500 ether,
            price: .4 ether,
            bid: true,
            reduceOnly: true
        });
        
        vm.expectRevert(OrderCreator.NOT_REDUCE_ONLY.selector);
        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);
    }

    function test_OrderCreator_LimitOrder_Assertions_Create_ReduceOnly_WrongSide() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        orders[0] = LimitOrder({
            market: trump,
            maker: jd,
            baseAmount : 500 ether,
            price: .4 ether,
            bid: true,
            reduceOnly: false
        });

        vm.prank(jd);
        clearingHouse.createLimitOrders(orders);

        vm.prank(daniel);
        clearingHouse.openPosition(trump, 500 ether, 0, false);

        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount : 500 ether,
            price: .7 ether,
            bid: false,
            reduceOnly: true
        });

        vm.expectRevert(OrderCreator.NOT_REDUCE_ONLY.selector);
        vm.startPrank(daniel);
        clearingHouse.createLimitOrders(orders);

        orders[0].bid = true;

        clearingHouse.createLimitOrders(orders);
    }

    function test_OrderCreator_LimitOrder_Assertions_Create_ReduceOnly_ReduceOnlyCap() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        orders[0] = LimitOrder({
            market: trump,
            maker: jd,
            baseAmount : 500 ether,
            price: .4 ether,
            bid: true,
            reduceOnly: false
        });

        vm.prank(jd);
        clearingHouse.createLimitOrders(orders);

        vm.prank(daniel);
        clearingHouse.openPosition(trump, 500 ether, 0, false);

        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount : 500 ether,
            price: .7 ether,
            bid: true,
            reduceOnly: true
        });

        vm.startPrank(daniel);
        clearingHouse.createLimitOrders(orders);

        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount : 500 ether,
            price: .5 ether,
            bid: true,
            reduceOnly: true
        });

        vm.expectRevert(OrderCreator.REDUCE_ONLY_CAP.selector);
        clearingHouse.createLimitOrders(orders);
    }

    /*//////////////////////////////////////////////////////////////
                           UPDATE ASSERTIONS
    //////////////////////////////////////////////////////////////*/

    function test_OrderCreator_LimitOrder_Assertions_Update_NotMaker() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .5 ether,
            bid: true,
            reduceOnly: false
        });

        vm.prank(rite);
        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount : 50 ether,
            price: .4 ether,
            bid: true,
            reduceOnly: false
        });

        // note: old order not maker
        vm.expectRevert(OrderCreator.NOT_MAKER.selector);
        vm.prank(daniel);
        clearingHouse.updateLimitOrders(ids, orders);

        // note: new order not maker
        vm.expectRevert(OrderCreator.NOT_MAKER.selector);
        vm.prank(rite);
        clearingHouse.updateLimitOrders(ids, orders);
    }

    function test_OrderCreator_LimitOrder_Assertions_Update_InvalidTick() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        LimitOrder memory order = orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .3 ether,
            bid: true,
            reduceOnly: false
        });

        vm.startPrank(rite);
        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        order.price = minPrice - 1;

        // note: price under min
        vm.expectRevert(OrderCreator.INVALID_LIMIT_PRICE.selector);
        clearingHouse.updateLimitOrders(ids, orders);

        order.price = .5 ether + 1;

        // note: invalid tick
        vm.expectRevert(OrderCreator.INVALID_LIMIT_PRICE.selector);
        clearingHouse.updateLimitOrders(ids, orders);

        order.price = maxPrice + 1;

        // note: price over max
        vm.expectRevert(OrderCreator.INVALID_LIMIT_PRICE.selector);
        clearingHouse.updateLimitOrders(ids, orders);
    }

    /*//////////////////////////////////////////////////////////////
                           DELETE ASSERTIONS
    //////////////////////////////////////////////////////////////*/
    
    function test_OrderCreator_LimitOrder_Assertions_Delete_NotMaker() public {
        LimitOrder[] memory orders = new LimitOrder[](1);
        orders[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount : 50 ether,
            price: .3 ether,
            bid: true,
            reduceOnly: false
        });

        vm.prank(rite);
        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        // note: not maker
        vm.expectRevert(OrderCreator.NOT_MAKER.selector);
        vm.prank(daniel);
        clearingHouse.deleteLimitOrders(ids);
    }

}