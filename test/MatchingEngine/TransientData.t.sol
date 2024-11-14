// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../AllInTestSetup.sol";

contract MatchingEngine_TransientDataTest is AllInTestSetup {
    using AllInMath for uint256;

    function setUp() public override {
        super.setUp();

        // note: upgrade
        matchingEngine_logic = address(new ME_TransientData(address(usdb)));
        clearingHouse_logic = address(new MockClearingHouse({
            oracle_ : address(0),
            matchingEngine_: matchingEngine_logic,
            orderCreator_: orderCreator_logic,
            usdb_: address(usdb)
        }));
        vm.prank(owner);
        factory.upgrade({
            proxy: address(clearingHouse),
            implementation: clearingHouse_logic
        });
    }

    /*//////////////////////////////////////////////////////////////
                           TRANSIENT POSITION
    //////////////////////////////////////////////////////////////*/

    /// @dev tests position is t-stored and updated correctly
    function test_TransientData_Position() public {
        // note: create pre-existing position
        _createPosition(rite, 20 ether, true);

        LimitOrder[] memory orders = new LimitOrder[](1);

        // note: create orders
        LimitOrder memory order1 = orders[0] = LimitOrder({
            market: trump,
            maker: aster,
            baseAmount: 15 ether,
            price: .25 ether,
            bid: false,
            reduceOnly: false
        });
        vm.prank(order1.maker);
        clearingHouse.createLimitOrders(orders);

        LimitOrder memory order2 = orders[0]= LimitOrder({
            market: trump,
            maker: joe,
            baseAmount: 20 ether,
            price: .24 ether,
            bid: false,
            reduceOnly: false
        });
        vm.prank(order2.maker);
        clearingHouse.createLimitOrders(orders);

        Position memory position = clearingHouse.getPosition(trump, rite);

        // note: calc new position
        uint expectedOpenNotional = position.openNotional + order1.baseAmount.mul(order1.price) + order2.baseAmount.mul(order2.price);
        int expectedSize = position.size + int(order1.baseAmount + order2.baseAmount);
        order1.bid = true; // note: changing direction to get taker margin
        order2.bid = true;
        uint expectedMargin = position.margin + _getOrderMarginRequired(order1) + _getOrderMarginRequired(order2);

        vm.roll(block.number + 5);

        // note: execute taker trade
        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit TransientPositionBefore({
            size: position.size,
            openNotional: position.openNotional,
            margin: position.margin,
            lastBlock: position.lastBlock
        });
        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit TransientPositionAfter({
            size: expectedSize,
            openNotional: expectedOpenNotional,
            margin: expectedMargin,
            lastBlock: block.number
        });
        vm.prank(rite);
        clearingHouse.openPosition(trump, order1.baseAmount + order2.baseAmount, 0, true);

        // note: check position
        Position memory newPosition = clearingHouse.getPosition(trump, rite);
        assertEq(newPosition.size, expectedSize, "SIZE NOT UPDATED");
        assertEq(newPosition.openNotional, expectedOpenNotional, "OPEN NOTIONAL NOT UPDATED");
        assertEq(newPosition.margin, expectedMargin, "MARGIN NOT UPDATED");
        assertEq(newPosition.lastBlock, block.number, "LAST BLOCK NOT UPDATED");
    }

    /*//////////////////////////////////////////////////////////////
                      TRANSIENT LAST TRADED PRICE
    //////////////////////////////////////////////////////////////*/

    /// @dev tests last traded price is t-stored and updated correctly
    function test_TransientData_LastTradedPrice() public {
        LimitOrder[] memory orders = new LimitOrder[](2);
        LimitOrder memory firstFilledOrder = orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 20 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });
        LimitOrder memory lastFilledOrder = orders[1] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 20 ether,
            price: .6 ether,
            bid: false,
            reduceOnly: false
        });

        assertTrue(!lastFilledOrder.bid && !firstFilledOrder.bid && firstFilledOrder.price < lastFilledOrder.price, "LIMIT ORDERS ARE ORDERED WRONG");

        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        // note: execute taker trade
        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit TransientLastTradedPriceBefore(clearingHouse.getLastPrice(trump));
        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit TransientLastTradedPriceAfter(lastFilledOrder.price);

        vm.prank(rite);
        clearingHouse.openPosition(trump, 40 ether, 0, true);

        assertEq(clearingHouse.getLastPrice(trump), lastFilledOrder.price, "MARK PRICE NOT UPDATED");
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSIENT FEES
    //////////////////////////////////////////////////////////////*/
    
    /// @dev tests fees are t-stored and not changed
    function test_TransientData_Fees() public {
        uint baseFee = clearingHouse.getBaseTakerFee();
        uint makerFee = clearingHouse.getMakerFee();

        LimitOrder[] memory orders = new LimitOrder[](2);
        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 20 ether,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });
        orders[1] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 20 ether,
            price: .6 ether,
            bid: false,
            reduceOnly: false
        });

        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        // note: execute taker trade
        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit TransientFeesBefore({
            baseFee: baseFee,
            makerFee: makerFee
        });
        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit TransientFeesAfter({
            baseFee: baseFee,
            makerFee: makerFee
        });

        vm.prank(rite);
        clearingHouse.openPosition(trump, 40 ether, 0, true);
    }

    /*//////////////////////////////////////////////////////////////
                          TRANSIENT BEST PRICE
    //////////////////////////////////////////////////////////////*/

    function test_TransientData_BestPrice() public {
        _createPosition(rite, 20 ether, false);

        LimitOrder[] memory orders = new LimitOrder[](2);
        LimitOrder memory secondBestBid = orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 20 ether,
            price: .45 ether,
            bid: true,
            reduceOnly: false
        });
        LimitOrder memory bestAsk = orders[1] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: 20 ether,
            price: .6 ether,
            bid: false,
            reduceOnly: false // note: this order will be removed via fill
        });

        LimitOrder[] memory orders2 = new LimitOrder[](2);
        LimitOrder memory bestBid = orders2[0] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount: 20 ether,
            price: .5 ether,
            bid: true,
            reduceOnly: true // note: this order will be removed via reduce only link
        });
        LimitOrder memory secondBestAsk = orders2[1] = LimitOrder({
            market: trump,
            maker: rite,
            baseAmount: 20 ether,
            price: .65 ether,
            bid: false,
            reduceOnly: false
        });


        vm.prank(daniel);
        clearingHouse.createLimitOrders(orders);

        vm.prank(rite);
        clearingHouse.createLimitOrders(orders2);

        // note: execute taker trade
        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit TransientBestPriceBefore({
            bestBid: bestBid.price,
            bestAsk: bestAsk.price
        });
        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit TransientBestPriceAfter({
            bestBid: secondBestBid.price,  // best bid is reduce only and deleted on maker's close
            bestAsk: secondBestAsk.price  // best ask is filled 
        });

        vm.prank(rite);
        clearingHouse.closePosition(trump, 20 ether, 0);

        // note: check best price
        uint bestPriceBid = clearingHouse.getBestPrice(trump, true);
        uint bestPriceAsk = clearingHouse.getBestPrice(trump, false);
        assertEq(bestPriceBid, secondBestBid.price, "BEST BID NOT UPDATED");
        assertEq(bestPriceAsk, secondBestAsk.price, "BEST ASK NOT UPDATED");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTION
    //////////////////////////////////////////////////////////////*/

    function _createPosition(
        address trader,
        uint baseAmount,
        bool yes
    ) internal {
        LimitOrder[] memory orders = new LimitOrder[](1);
        orders[0] = LimitOrder({
            market: trump,
            maker: jd,
            baseAmount: baseAmount,
            price: .5 ether,
            bid: !yes,
            reduceOnly: false
        });
        vm.prank(jd);
        clearingHouse.createLimitOrders(orders);

        vm.prank(trader);
        clearingHouse.openPosition(trump, baseAmount, 0, yes);

        vm.roll(block.number + 1);
    }
}

/*//////////////////////////////////////////////////////////////
                            HELPER EVENTS
//////////////////////////////////////////////////////////////*/


event ReentrancyGuard(bool locked);
event TransientPositionBefore(
    int256 size,
    uint256 openNotional,
    uint256 margin,
    uint256 lastBlock
);
event TransientPositionAfter(
    int256 size,
    uint256 openNotional,
    uint256 margin,
    uint256 lastBlock
);
event TransientLastTradedPriceBefore(uint256 price);
event TransientLastTradedPriceAfter(uint256 price);
event TransientFeesBefore(uint256 baseFee, uint256 makerFee);
event TransientFeesAfter(uint256 baseFee, uint256 makerFee);
event TransientBestPriceBefore(uint256 bestBid, uint256 bestAsk);
event TransientBestPriceAfter(uint256 bestBid, uint256 bestAsk);

/*//////////////////////////////////////////////////////////////
                        HELPER CONTRACT
//////////////////////////////////////////////////////////////*/

contract ME_TransientData is MatchingEngine {
    bool constant public IS_SCRIPT = true;

    constructor(address usdb_) MatchingEngine(usdb_) {}

    function takerTrade(
        uint160 market,
        address taker,
        uint256 baseAmount,
        uint256,
        bool yes,
        address keeper
    ) external override useTransientData(market, taker) returns (uint256 quoteAmount) {
        // reentrancy guard
        emit ReentrancyGuard(_isTransientReentrancyGuardLocked());

        // transient position before
        Position memory position = _getTransientPosition();
        emit TransientPositionBefore({
            size: position.size,
            openNotional: position.openNotional,
            margin: position.margin,
            lastBlock: position.lastBlock
        });

        // transient last traded price before
        uint256 lastTradedPrice = _getTransientMarkPrice();
        emit TransientLastTradedPriceBefore(lastTradedPrice);

        // transient fees before
        uint baseFee = _getTransientBaseFee();
        uint makerFee = _getTransientMakerFee();
        emit TransientFeesBefore({
            baseFee: baseFee,
            makerFee: makerFee
        });

        // transient best price before
        uint bestBid = _getTransientBestPrice(true);
        uint bestAsk = _getTransientBestPrice(false);
        emit TransientBestPriceBefore({
            bestBid: bestBid,
            bestAsk: bestAsk
        });

        quoteAmount = _takerTrade({
            market: market,
            taker: taker,
            baseAmount: baseAmount,
            yes: yes,
            keeper: keeper
        });

        // transient position after
        position = _getTransientPosition();
        emit TransientPositionAfter({
            size: position.size,
            openNotional: position.openNotional,
            margin: position.margin,
            lastBlock: position.lastBlock
        });

        // transient last traded price after
        lastTradedPrice = _getTransientMarkPrice();
        emit TransientLastTradedPriceAfter(lastTradedPrice);

        // transient fees after
        baseFee = _getTransientBaseFee();
        makerFee = _getTransientMakerFee();
        emit TransientFeesAfter({
            baseFee: baseFee,
            makerFee: makerFee
        });

        // transient best price after
        bestBid = _getTransientBestPrice(true);
        bestAsk = _getTransientBestPrice(false);
        emit TransientBestPriceAfter({
            bestBid: bestBid,
            bestAsk: bestAsk
        });
    }

    // note: copy pasted from MatchingEngine — real takerTrade logic
    function _takerTrade( 
        uint160 market,
        address taker,
        uint256 baseAmount,
        bool yes,
        address keeper
    ) internal returns (uint256 quoteAmount) {
        MarketTradeResponse memory response = _match(
            MarketOrder({
                market: market,
                taker: taker,
                baseAmount: baseAmount,
                yes: yes
            })
        );

        if ((quoteAmount = response.exchangedQuote) == 0) return 0;

        Position memory position = _getTransientPosition();

        _setPosition(market, taker, position);

        _distributeFunds({
            market: market,
            fundsTransferred: response.fundsTransferred,
            marginToTrader: -response.marginDelta,
            rpnl: response.realizedPnL,
            taker: taker,
            keeper: keeper
        });

        uint mark = _lastPrice[market] = _getTransientMarkPrice();
        _bestPrice[market][true] = _getTransientBestPrice(true);
        _bestPrice[market][false] = _getTransientBestPrice(false);

        emit PositionChanged({
            market: market,
            trader: taker,
            markPrice: mark,
            openNotional: position.openNotional,
            size: position.size,
            margin: position.margin,
            realizedPnL: response.realizedPnL,
            exchangedQuote: response.exchangedQuote,
            exchangedSize: response.exchangedSize,
            maker : false
        });
    }


}