// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../AllInTestSetup.sol";
import { AllInBase } from "src/AllInBase.sol";
import { TickBitmap } from "src/utils/TickBitmap.sol";

/// @notice tests functionality of _matchPair() (including _boundPair() & _boundReduceOnly())
contract MatchingEngine_MatchPair is AllInTestSetup {
    using AllInMath for *;

    ME_MatchPair me;

    function setUp() public override {
        super.setUp();
        me = new ME_MatchPair(address(usdb));
    }

    LimitOrder filledLimitOrder;
    MatchingEngine.MarketOrder filledMarketOrder;
    MatchingEngine.MarketTradeResponse response;

    /*//////////////////////////////////////////////////////////////
                            FILL PAIR TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev tests case where both market & limit orders are mutually filled
    function test_MatchPair_BothFilled() public {
        LimitOrder memory limitOrder = LimitOrder({
            market: trump,
            maker: joe,
            baseAmount: 1 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });

        uint id = me.placeLimitOrder(limitOrder);

        MatchingEngine.MarketOrder memory marketOrder = MatchingEngine.MarketOrder({
            taker: rite,
            baseAmount: 1 ether,
            yes: true,
            market: trump
        });

        vm.expectEmit(true, true, true, true, address(me));
        emit AllInBase.LimitOrderRemoved({
            id: id,
            filled: true
        });

        response = me.matchPair(id, marketOrder);

        console.log(response.exchangedSize);
        console.log(response.exchangedQuote);

        assertEq(response.exchangedSize, int(limitOrder.baseAmount), "EXCHANGED SIZE WRONG");

        filledLimitOrder = me.filledLimitOrder();
        filledMarketOrder = me.filledMarketOrder();

        ///  FILLED LIMIT ORDER   ///
        assertEq(filledLimitOrder.market, limitOrder.market, "FILLED LIMIT ORDER: MARKET WRONG");
        assertEq(filledLimitOrder.maker, limitOrder.maker, "FILLED LIMIT ORDER: MAKER WRONG");
        assertEq(filledLimitOrder.baseAmount, limitOrder.baseAmount, "FILLED LIMIT ORDER: BASE AMOUNT WRONG");
        assertEq(filledLimitOrder.price, limitOrder.price, "FILLED LIMIT ORDER: PRICE WRONG");
        assertEq(filledLimitOrder.bid, limitOrder.bid, "FILLED LIMIT ORDER: BUY WRONG");
        assertEq(filledLimitOrder.reduceOnly, limitOrder.reduceOnly, "FILLED LIMIT ORDER: REDUCE ONLY WRONG");

        ///  FILLED MARKET ORDER   ///
        assertEq(filledMarketOrder.taker, marketOrder.taker, "FILLED MARKET ORDER: TAKER WRONG");
        assertEq(filledMarketOrder.baseAmount, marketOrder.baseAmount, "FILLED MARKET ORDER: BASE AMOUNT WRONG");
        assertEq(filledMarketOrder.yes, marketOrder.yes, "FILLED MARKET ORDER: BUY WRONG");
        assertEq(filledMarketOrder.market, marketOrder.market, "FILLED MARKET ORDER: MARKET WRONG");

        ///  REMAINING LIMIT ORDER   ///
        assertEq(me.getLimitOrder(id).maker, address(0), "LIMIT ORDER NOT REMOVED: MAKER");
        assertEq(me.getLimitOrder(id).baseAmount, 0, "LIMIT ORDER NOT REMOVED: BASE AMOUNT");
        
        ///  BOOK   ///
        assertEq(me.getOrdersOnTick(trump, .5 ether).length, 0, "ORDER ON TICK");
        assertFalse(me.isTickInitialized(trump, .5 ether, false), "TICK INITIALIZED");
    }

    /// @dev tests case where market order is partially filled by limit order
    function test_MatchPair_PartialMarketFill() public {
        LimitOrder memory limitOrder = LimitOrder({
            market: trump,
            maker: joe,
            baseAmount: 1 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });

        uint id = me.placeLimitOrder(limitOrder);

        MatchingEngine.MarketOrder memory marketOrder = MatchingEngine.MarketOrder({
            taker: rite,
            baseAmount: 1.5 ether,
            yes: true,
            market: trump
        });

        vm.expectEmit(true, true, true, true, address(me));
        emit AllInBase.LimitOrderRemoved({
            id: id,
            filled: true
        });

        response = me.matchPair(id, marketOrder);

        console.log(response.exchangedSize);
        console.log(response.exchangedQuote);

        assertEq(response.exchangedSize, int(limitOrder.baseAmount), "INCORRECT EXCHANGED SIZE");

        filledLimitOrder = me.filledLimitOrder();
        filledMarketOrder = me.filledMarketOrder();

        ///  FILLED LIMIT ORDER   ///
        assertEq(filledLimitOrder.market, limitOrder.market, "FILLED LIMIT ORDER: MARKET WRONG");
        assertEq(filledLimitOrder.maker, limitOrder.maker, "FILLED LIMIT ORDER: MAKER WRONG");
        assertEq(filledLimitOrder.baseAmount, limitOrder.baseAmount, "FILLED LIMIT ORDER: BASE AMOUNT WRONG");
        assertEq(filledLimitOrder.price, limitOrder.price, "FILLED LIMIT ORDER: PRICE WRONG");
        assertEq(filledLimitOrder.bid, limitOrder.bid, "FILLED LIMIT ORDER: BUY WRONG");
        assertEq(filledLimitOrder.reduceOnly, limitOrder.reduceOnly, "FILLED LIMIT ORDER: REDUCE ONLY WRONG");

        ///  FILLED MARKET ORDER   ///
        assertEq(filledMarketOrder.taker, marketOrder.taker, "FILLED MARKET ORDER: TAKER WRONG");
        assertEq(filledMarketOrder.baseAmount, limitOrder.baseAmount, "FILLED MARKET ORDER: BASE AMOUNT WRONG");
        assertEq(filledMarketOrder.yes, marketOrder.yes, "FILLED MARKET ORDER: BUY WRONG");
        assertEq(filledMarketOrder.market, marketOrder.market, "FILLED MARKET ORDER: MARKET WRONG");

        ///  REMAINING LIMIT ORDER   ///
        assertEq(me.getLimitOrder(id).maker, address(0), "LIMIT ORDER NOT REMOVED: MAKER");
        assertEq(me.getLimitOrder(id).baseAmount, 0, "LIMIT ORDER NOT REMOVED: BASE AMOUNT");
        
        ///  BOOK   ///
        assertEq(me.getOrdersOnTick(trump, .5 ether).length, 0, "ORDER ON TICK");
        assertFalse(me.isTickInitialized(trump, .5 ether, false), "TICK INITIALIZED");
    }

    /// @dev tests case where limit order is partially filled by market order
    function test_MatchPair_PartialLimitFill() public {
        LimitOrder memory limitOrder = LimitOrder({
            market: trump,
            maker: joe,
            baseAmount: 1.5 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });

        uint id = me.placeLimitOrder(limitOrder);

        MatchingEngine.MarketOrder memory marketOrder = MatchingEngine.MarketOrder({
            taker: rite,
            baseAmount: 1 ether,
            yes: true,
            market: trump
        });

        vm.expectEmit(true, true, true, true, address(me));
        emit AllInBase.LimitOrderUpdated({
            id: id,
            market: limitOrder.market,
            maker: limitOrder.maker,
            baseAmount: limitOrder.baseAmount - marketOrder.baseAmount,
            price: limitOrder.price,
            bid: limitOrder.bid,
            reduceOnly: limitOrder.reduceOnly,
            fill: true
        });

        response = me.matchPair(id, marketOrder);

        assertEq(response.exchangedSize, int(marketOrder.baseAmount), "INCORRECT EXCHANGED SIZE");

        filledLimitOrder = me.filledLimitOrder();
        filledMarketOrder = me.filledMarketOrder();

        ///  FILLED LIMIT ORDER   ///
        assertEq(filledLimitOrder.market, limitOrder.market, "FILLED LIMIT ORDER: MARKET WRONG");
        assertEq(filledLimitOrder.maker, limitOrder.maker, "FILLED LIMIT ORDER: MAKER WRONG");
        assertEq(filledLimitOrder.baseAmount, marketOrder.baseAmount, "FILLED LIMIT ORDER: BASE AMOUNT WRONG");
        assertEq(filledLimitOrder.price, limitOrder.price, "FILLED LIMIT ORDER: PRICE WRONG");
        assertEq(filledLimitOrder.bid, limitOrder.bid, "FILLED LIMIT ORDER: BUY WRONG");
        assertEq(filledLimitOrder.reduceOnly, limitOrder.reduceOnly, "FILLED LIMIT ORDER: REDUCE ONLY WRONG");

        ///  FILLED MARKET ORDER   ///
        assertEq(filledMarketOrder.taker, marketOrder.taker, "FILLED MARKET ORDER: TAKER WRONG");
        assertEq(filledMarketOrder.baseAmount, marketOrder.baseAmount, "FILLED MARKET ORDER: BASE AMOUNT WRONG");
        assertEq(filledMarketOrder.yes, marketOrder.yes, "FILLED MARKET ORDER: BUY WRONG");
        assertEq(filledMarketOrder.market, marketOrder.market, "FILLED MARKET ORDER: MARKET WRONG");

        ///  REMAINING LIMIT ORDER   ///
        assertEq(me.getLimitOrder(id).maker, joe, "LIMIT ORDER: MAKER WRONG");
        assertEq(me.getLimitOrder(id).baseAmount, limitOrder.baseAmount - marketOrder.baseAmount, "LIMIT ORDER: BASE AMOUNT WRONG");

        ///  BOOK   ///
        assertEq(me.getOrdersOnTick(trump, .5 ether).length, 1, "ORDER NOT ON TICK");
        assertEq(me.getOrdersOnTick(trump, .5 ether)[0], id, "ORDER NOT ON TICK: ID MISMATCH");
    }

    /// @dev tests case where both limit & market orders are partially filled due to reduce only bound
    function test_MatchPair_ReduceOnlyBound() public {
        uint base = .5 ether;
        uint openNotional = base.mul(base); // opened at .5 for .5

        me.placePosition(
            trump, 
            joe, 
            Position({
                margin: openNotional,
                size: int(base),
                openNotional: openNotional,
                lastBlock: block.number
            })
        );

        vm.prank(whale);
        usdb.transfer(address(me), openNotional);

        LimitOrder memory limitOrder = LimitOrder({
            market: trump,
            maker: joe,
            baseAmount: 1.5 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: true
        });

        uint id = me.placeLimitOrder(limitOrder);

        MatchingEngine.MarketOrder memory marketOrder = MatchingEngine.MarketOrder({
            taker: rite,
            baseAmount: 1 ether,
            yes: true,
            market: trump
        });

        vm.expectEmit(true, true, true, true, address(me));
        emit AllInBase.LimitOrderUpdated({                       // from fill
            id: id,
            market: limitOrder.market,
            maker: limitOrder.maker,
            baseAmount: limitOrder.baseAmount - base,
            price: limitOrder.price,
            bid: limitOrder.bid,
            reduceOnly: limitOrder.reduceOnly,
            fill: true
        });

        vm.expectEmit(true, true, true, true, address(me));     // from close -> reduce only link
        emit AllInBase.LimitOrderRemoved({
            id: id,
            filled: false
        });

        response = me.matchPair(id, marketOrder);

        assertEq(response.exchangedSize, int(base), "INCORRECT EXCHANGED SIZE");

        filledLimitOrder = me.filledLimitOrder();
        filledMarketOrder = me.filledMarketOrder();

        ///  FILLED LIMIT ORDER   ///
        assertEq(filledLimitOrder.market, limitOrder.market, "FILLED LIMIT ORDER: MARKET WRONG");
        assertEq(filledLimitOrder.maker, limitOrder.maker, "FILLED LIMIT ORDER: MAKER WRONG");
        assertEq(filledLimitOrder.baseAmount, base, "FILLED LIMIT ORDER: BASE AMOUNT WRONG");
        assertEq(filledLimitOrder.price, limitOrder.price, "FILLED LIMIT ORDER: PRICE WRONG");
        assertEq(filledLimitOrder.bid, limitOrder.bid, "FILLED LIMIT ORDER: BUY WRONG");

        ///  FILLED MARKET ORDER   ///
        assertEq(filledMarketOrder.taker, marketOrder.taker, "FILLED MARKET ORDER: TAKER WRONG");
        assertEq(filledMarketOrder.baseAmount, base, "FILLED MARKET ORDER: BASE AMOUNT WRONG");
        assertEq(filledMarketOrder.yes, marketOrder.yes, "FILLED MARKET ORDER: BUY WRONG");
        assertEq(filledMarketOrder.market, marketOrder.market, "FILLED MARKET ORDER: MARKET WRONG");

        ///  REMAINING LIMIT ORDER   ///
        assertEq(me.getLimitOrder(id).maker, address(0), "LIMIT ORDER NOT REMOVED: MAKER");
        assertEq(me.getLimitOrder(id).baseAmount, 0, "LIMIT ORDER NOT REMOVED: BASE AMOUNT");
    }

    /*//////////////////////////////////////////////////////////////
                            UNFILLABLE TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @dev tests that noop on an attempted fill of a deleted order
    /// note: this case will happen if a maker closes on one order and has a reduce only on another order of the same tick
    function test_MatchPair_UnfillableOrder_AlreadyDeleted() public {
        MatchingEngine.MarketOrder memory marketOrder = MatchingEngine.MarketOrder({
            taker: rite,
            baseAmount: 1 ether,
            yes: true,
            market: trump
        });

        response = me.matchPair(1, marketOrder);

        assertEq(response.exchangedSize, 0, "NOT NOOP");

        assertFalse(me.fillMarketAttempted(), "MARKET ORDER SHOULD NOT ATTEMPT TO FILL");
        assertFalse(me.fillLimitAttempted(), "LIMIT ORDER SHOULD NOT ATTEMPT TO FILL");
    }

    /// @dev tests that order is deleted and skipped if taker is maker
    function test_FillPair_UnfillableOrder_MakerIsTaker() public {
        LimitOrder memory limitOrder = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount: 1 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });

        uint margin = _getOrderMarginRequired(limitOrder);

        usdb.mint(address(me), margin);

        uint id = me.placeLimitOrder(limitOrder);
        
        MatchingEngine.MarketOrder memory marketOrder = MatchingEngine.MarketOrder({
            taker: rite,
            baseAmount: 1 ether,
            yes: true,
            market: trump
        });

        uint makerBalBefore = usdb.balanceOf(rite);

        vm.expectEmit(true, true, true, true, address(me));
        emit AllInBase.LimitOrderRemoved({
            id: id,
            filled: false
        });

        response = me.matchPair(id, marketOrder);

        assertEq(response.exchangedSize, 0, "NOT NOOP");

        assertEq(usdb.balanceOf(rite) - makerBalBefore, margin, "MAKER NOT REFUNDED");

        assertEq(me.getOrdersOnTick(trump, .5 ether).length, 0, "ORDER ON TICK");
        assertFalse(me.isTickInitialized(trump, .5 ether, false), "TICK INITIALIZED");

        assertFalse(me.fillMarketAttempted(), "MARKET ORDER SHOULD NOT ATTEMPT TO FILL");
        assertFalse(me.fillLimitAttempted(), "LIMIT ORDER SHOULD NOT ATTEMPT TO FILL");
    }

    /*//////////////////////////////////////////////////////////////
                           MOCK FUNCTION TEST
    //////////////////////////////////////////////////////////////*/

    /// @dev tests mock function me.placeLimitOrder() works and initializes tick (so we don't need to check book every time we place an order)
    function test_FillPair_MetaTest_PlaceLimitOrderWorks() public {
        LimitOrder memory order = LimitOrder({
            market: trump,
            maker: joe,
            baseAmount: 1 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });

        assertEq(me.getOrdersOnTick(trump, order.price).length, 0, "ORDER ON TICK");
        assertFalse(me.isTickInitialized(trump, order.price, false), "TICK INITIALIZED");

        uint id = me.placeLimitOrder(order);

        assertEq(me.getOrdersOnTick(trump, order.price).length, 1, "ORDER NOT ON TICK");
        assertEq(me.getOrdersOnTick(trump, order.price)[0], id, "ORDER NOT ON TICK: ID MISMATCH");
        assertTrue(me.isTickInitialized(trump, order.price, false), "TICK NOT INITIALIZED");
    }
}

/*//////////////////////////////////////////////////////////////
                            MOCK CONTRACT
//////////////////////////////////////////////////////////////*/
contract ME_MatchPair is MatchingEngine {
    using TickBitmap for mapping(int16 => uint256);

    bool constant public IS_SCRIPT = true;

    uint256 internal constant randomSlot = uint256(keccak256("AllIn.TEST.randomSlot"));

    constructor(address usdb_) MatchingEngine(usdb_) {}

    bool public fillMarketAttempted;
    bool public fillLimitAttempted;

    function filledLimitOrder() external view returns (LimitOrder memory) {
        return _filledLimitOrder;
    }

    function filledMarketOrder() external view returns (MarketOrder memory) {
        return _filledMarketOrder;
    }

    MarketOrder public _filledMarketOrder;
    LimitOrder public _filledLimitOrder;

    address public filledMaker;
    uint256 public filledPrice;

    function getLimitOrder(uint id) external view returns (LimitOrder memory) {
        return _limitOrder[id];
    }

    function getPosition(uint160 market, address trader) external view returns (Position memory) {
        return _position[market][trader];
    }

    function matchPair(
        uint id,
        MarketOrder memory marketOrder
    ) external returns (MarketTradeResponse memory response) {
       return _matchPair(id, marketOrder);
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

    function isTickInitialized(
        uint160 market, 
        uint256 price, 
        bool lte
    ) external view returns (bool initialized) {
        int24 tick = _priceToTick(price);
        int24 tick_ = tick;

        // note: tick bitmap doesn't check current tick if iterating up
        if (!lte) --tick_;

        (tick_, initialized) = _book[market].nextInitializedTickWithinOneWord(
            tick_,
            1,
            lte // true checks down, false iterates up
        );

        return (initialized && tick_ == tick);
    }

    function getOrdersOnTick(
        uint160 market,
        uint256 price
    ) external view returns (uint[] memory) {
        return _tick[market][_priceToTick(price)];
    }

    function _fillLimitOrder(LimitOrder memory limitOrder) internal override {
        fillLimitAttempted = true;
        _filledLimitOrder = limitOrder;
        MatchingEngine._fillLimitOrder(limitOrder);
    }

    function _fillMarketOrder(
        MarketOrder memory marketOrder,
        uint256 price,
        address maker
    ) internal override returns (MarketTradeResponse memory response) {
        fillMarketAttempted = true;
        _filledMarketOrder = marketOrder;
        filledMaker = maker;
        filledPrice = price;
        return MatchingEngine._fillMarketOrder(marketOrder, price, maker);
    }
}