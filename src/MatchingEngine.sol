// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

///  TYPES  ///
import { Position, LimitOrder } from "./utils/AllInStructs.sol";

///  UTILS  ///
import { AllInMath } from "./utils/AllInMath.sol";
import { TickBitmap } from "./utils/TickBitmap.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

///  BASE  ///
import { AllInBase } from "./AllInBase.sol";

/// @title All-In Matching Engine
/// @notice sidecar proxy used to match & fill market orders w/ limit orders
contract MatchingEngine is AllInBase {
    using TickBitmap for mapping(int16 => uint256);
    using SafeCastLib for uint256;
    using SafeTransferLib for address;
    using FixedPointMathLib for *;
    using AllInMath for *;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error QUOTE_LIMIT_EXCEEDED();
    error QUOTE_LIMIT_UNMET();
    error POSITION_INSOLVENT();
    error MAKER_OWES_MARGIN_AFTER_INVERSE_TRADE();

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor (address usdb_) { usdb = usdb_;} 

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant tPositionSlot = uint256(keccak256("ALLIN.TRANSIENT.POSITION.SLOT"));
    uint256 internal constant tMarkPriceSlot = uint256(keccak256("ALLIN.TRANSIENT.MARK.PRICE.SLOT"));
    uint256 internal constant tFeeSlot = uint256(keccak256("ALLIN.TRANSIENT.FEE.SLOT"));

    /*//////////////////////////////////////////////////////////////
                              CUSTOM TYPES
    //////////////////////////////////////////////////////////////*/

    struct MarketOrder {
        uint160 market;
        address taker;
        uint256 baseAmount;
        bool yes;
    }

    struct MarketTradeResponse {
        uint256 exchangedQuote;
        int256 exchangedSize;
        int256 realizedPnL;
        int256 marginDelta;
        uint256 fundsTransferred;
    }

    struct TradeResponse {
        Position position;
        uint256 exchangedQuote;
        int256 exchangedSize;
        int256 realizedPnL;
        int256 marginDelta;
    }

    modifier useTransientData(uint160 market, address trader) {
        _setTransientPosition(
            _getPosition({
                market: market,
                trader: trader
            })
        );
        _setTransientBestPrice(true, _bestPrice[market][true]);
        _setTransientBestPrice(false, _bestPrice[market][false]);
        _setTransientMarkPrice(_getLastPrice(market));
        _setTransientFees();
        _;
        _lastPrice[market] = _getTransientMarkPrice();
        _bestPrice[market][true] = _getTransientBestPrice(true);
        _bestPrice[market][false] = _getTransientBestPrice(false);
    }

    /*//////////////////////////////////////////////////////////////
                              TAKER ORDERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice market order for prediction market
     * 
     * @dev only called via delegatecall
     * 
     * @param market being traded
     * @param taker address
     * @param baseAmount being traded
     * @param yes?
     * @param keeper address (optional)
     * 
     * @return quoteAmount exchanged
     */
    function takerTrade(
        uint160 market,
        address taker,
        uint256 baseAmount,
        uint256 quoteLimit,
        bool yes,
        address keeper
    ) external virtual useTransientData(market, taker) returns (uint256 quoteAmount) {
        MarketTradeResponse memory response = _match(
            MarketOrder({
                market: market,
                taker: taker,
                baseAmount: baseAmount,
                yes: yes
            })
        );

        if ((quoteAmount = response.exchangedQuote) == 0) return 0;

        if (quoteLimit != 0) {
            // bound quote limit by % of fill
            quoteLimit = response.exchangedSize.abs().div(baseAmount).mul(quoteLimit);

            if (yes && quoteAmount > quoteLimit) revert QUOTE_LIMIT_EXCEEDED();
            else if (!yes && quoteAmount < quoteLimit) revert QUOTE_LIMIT_UNMET();
        }

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

        emit PositionChanged({
            market: market,
            trader: taker,
            markPrice: _getTransientMarkPrice(),
            openNotional: position.openNotional,
            size: position.size,
            margin: position.margin,
            realizedPnL: response.realizedPnL,
            exchangedQuote: response.exchangedQuote,
            exchangedSize: response.exchangedSize,
            maker : false
        });
    }

    /*//////////////////////////////////////////////////////////////
                                MATCHING
    //////////////////////////////////////////////////////////////*/

    function _match(MarketOrder memory order) internal virtual returns (MarketTradeResponse memory response) {
        uint nextPrice; uint[] memory ids; uint length; MarketTradeResponse memory newResponse;

        while (order.baseAmount > 0) {
            nextPrice = _getTransientBestPrice(!order.yes);

            ids = _tick[order.market][_priceToTick(nextPrice)];

            if ((length = ids.length) == 0) break;

            for (uint i; i < length; ++i) {
                if (order.baseAmount > 0) { // remaining market order
                    newResponse = _matchPair({
                        id: ids[i],
                        marketOrder: order
                    });

                    if (newResponse.exchangedQuote > 0) _accumulateResponse({
                        response: response,
                        newResponse: newResponse
                    });

                } else break;                 // filled market order
            }
        }
    }

    function _matchPair(
        uint256 id,
        MarketOrder memory marketOrder
    ) internal virtual returns (MarketTradeResponse memory response) {
        LimitOrder memory limitOrder = _getLimitOrder(id);
        
        if (limitOrder.maker == address(0)) return response;          // order already deleted (via reduceOnly link)
        if (marketOrder.taker == limitOrder.maker) {                // self fill
            _handleUnfillableLimitOrder(id, limitOrder);
            return response;
        }

        (
            MarketOrder memory filledMarketOrder, 
            LimitOrder memory filledLimitOrder
        ) = _boundPair(marketOrder, limitOrder); 

        _handleFilledLimitOrder({
            id: id, 
            remainingOrder: limitOrder
        });

        response = _fillMarketOrder({
            order: filledMarketOrder,
            price: filledLimitOrder.price,
            maker: limitOrder.maker
        });

        _fillLimitOrder(filledLimitOrder);
    }

    /*//////////////////////////////////////////////////////////////
                                FILLING
    //////////////////////////////////////////////////////////////*/

    function _fillLimitOrder(LimitOrder memory order) internal virtual {
        Position memory position = _getPosition({
            market: order.market,
            trader: order.maker
        });

        bool increase = order.bid ? position.size >= 0 : position.size <= 0;

        (TradeResponse memory response, ) = _routeTrade({
            market: order.market,
            trader: order.maker,
            oldPosition: position,
            baseAmount: order.baseAmount,
            price: order.price,
            increase: increase,
            yes: order.bid
        }); 

        response.marginDelta -= response.realizedPnL;

        if (!order.reduceOnly && !increase) { // needlessly deposited margin, and should be refunded 
            response.marginDelta += _getOrderMarginRequired({
                bid: order.bid, 
                baseAmount: order.baseAmount, 
                price: order.price
            }).mul(-1 ether);
        } 

        if (!increase && response.marginDelta > 0) revert MAKER_OWES_MARGIN_AFTER_INVERSE_TRADE();
        
        _setPosition(order.market, order.maker, response.position);

        if (response.marginDelta < 0) usdb.safeTransfer({
            to: order.maker, 
            amount: response.marginDelta.abs()
        });

        emit PositionChanged({
            market: order.market,
            trader: order.maker,
            markPrice: order.price,
            openNotional: response.position.openNotional,
            size: response.position.size,
            margin: response.position.margin,
            realizedPnL: response.realizedPnL,
            exchangedQuote: response.exchangedQuote,
            exchangedSize: response.exchangedSize,
            maker : true
        });
    }

    function _fillMarketOrder(
        MarketOrder memory order,
        uint256 price,
        address maker
    ) internal virtual returns (MarketTradeResponse memory response) {
        Position memory position = _getTransientPosition();

        (TradeResponse memory tradeResponse, uint256 fundsTransferred) = _routeTrade({
            market: order.market,
            trader: order.taker,
            oldPosition: position,
            baseAmount: order.baseAmount,
            price: price,
            increase: order.yes ? position.size >= 0 : position.size <= 0,
            yes: order.yes
        });

        response = MarketTradeResponse({
            exchangedQuote: tradeResponse.exchangedQuote,
            exchangedSize: tradeResponse.exchangedSize,
            realizedPnL: tradeResponse.realizedPnL,
            marginDelta: tradeResponse.marginDelta,
            fundsTransferred: fundsTransferred
        });

        _feeStore[maker] += fundsTransferred.mul(_getTransientMakerFee());

        _setTransientPosition(tradeResponse.position);
        _setTransientMarkPrice(price);
    }


    function _routeTrade(
        uint160 market,
        address trader,
        Position memory oldPosition,
        uint256 baseAmount,
        uint256 price,
        bool increase,
        bool yes
    ) internal virtual returns (TradeResponse memory response, uint256 fundsTransferred) {
        if (increase) {                              
            response = _increasePosition({
                market : market,
                oldPosition: oldPosition,
                baseAmount: baseAmount,
                price: price,
                yes: yes
            });
            fundsTransferred = response.marginDelta.abs();
        } else if (oldPosition.size.abs() > baseAmount) {
            response = _decreasePosition({
                market: market,
                oldPosition: oldPosition,
                baseAmount: baseAmount,
                price: price
            });
            fundsTransferred = response.marginDelta.abs();
        } else {
            (response, fundsTransferred) = _closeOrReverseOpen({
                market: market,
                trader: trader,
                oldPosition: oldPosition,
                baseAmount: baseAmount,
                price: price
            });
        }
    }

    function _increasePosition(
        uint160 market,
        Position memory oldPosition,
        uint256 baseAmount,
        uint256 price,
        bool yes
    ) internal virtual returns (TradeResponse memory response) {
        response.exchangedSize = yes ? baseAmount.toInt256() : baseAmount.mul(-1 ether);
        response.exchangedQuote = baseAmount.mul(price);

        response.marginDelta = _getOrderMarginRequired({
            bid: yes, 
            baseAmount: baseAmount, 
            price: price
        }).toInt256();

        response.position = Position({
            size: oldPosition.size + response.exchangedSize,
            openNotional: oldPosition.openNotional + response.exchangedQuote,
            margin: oldPosition.margin + uint(response.marginDelta),
            lastBlock: block.number
        });

        if (
            !_hasSufficientMargin(
                response.position.openNotional, 
                response.position.size, 
                response.position.margin
            )
        ) revert POSITION_INSOLVENT(); 

        _openInterest[market] += response.exchangedQuote;
    }
    
    function _decreasePosition(
        uint160 market,
        Position memory oldPosition,
        uint256 baseAmount,
        uint256 price
    ) internal virtual returns (TradeResponse memory response) {
        response.exchangedSize = oldPosition.size > 0 ? baseAmount.mul(-1 ether) : baseAmount.toInt256();
        response.exchangedQuote = baseAmount.mul(price);

        // traded open notional = old open notional * % of close
        uint tradedOpenNotional = oldPosition.openNotional.mul(baseAmount.div(oldPosition.size.abs()));

        response.position = Position({
            size: oldPosition.size + response.exchangedSize,
            openNotional: oldPosition.openNotional - tradedOpenNotional,
            margin: _getPositionMarginRequired({
                size: oldPosition.size + response.exchangedSize, 
                openNotional: oldPosition.openNotional - tradedOpenNotional
            }),
            lastBlock: block.number
        });

        response.realizedPnL = _getPnL({
            openNotional: tradedOpenNotional.toInt256(), 
            currentNotional: response.exchangedQuote.toInt256(),
            yes: oldPosition.size > 0
        });

        response.marginDelta = (oldPosition.margin - response.position.margin).mul(-1 ether);

        require(response.marginDelta - response.realizedPnL <= 0, "INSOLVENT AFTER RPNL");

        if (
            !_hasSufficientMargin(
                response.position.openNotional, 
                response.position.size, 
                response.position.margin
            )
        ) revert POSITION_INSOLVENT(); 

        _openInterest[market] -= tradedOpenNotional;
    }

    function _closePosition(
        uint160 market,
        Position memory oldPosition,
        uint256 price
    ) internal virtual returns (TradeResponse memory response) {
        response.exchangedSize = -oldPosition.size;
        response.exchangedQuote = oldPosition.size.abs().mul(price);

        response.realizedPnL = _getPnL({
            openNotional : oldPosition.openNotional.toInt256(), 
            currentNotional : response.exchangedQuote.toInt256(),
            yes : oldPosition.size > 0
        });

        response.marginDelta = int(oldPosition.margin).mul(-1 ether);

        if (response.marginDelta - response.realizedPnL > 0) revert POSITION_INSOLVENT();

        response.position = Position({
            size: 0,
            openNotional: 0,
            margin: 0,
            lastBlock: block.number
        });

        _openInterest[market] -= oldPosition.openNotional;
    }

    function _closeOrReverseOpen(
        uint160 market,
        address trader,
        Position memory oldPosition,
        uint256 baseAmount,
        uint256 price
    ) internal virtual returns (TradeResponse memory response, uint256 fundsTransferred) {
        TradeResponse memory closeResponse = _closePosition(market, oldPosition, price);

        baseAmount -= oldPosition.size.abs();

        fundsTransferred = closeResponse.marginDelta.abs();

        _clearLinkedOrders({
            market: market, 
            trader: trader
        });

        if (baseAmount == 0) return (closeResponse, fundsTransferred);

        TradeResponse memory openResponse = _increasePosition({
            market: market,
            oldPosition: closeResponse.position,
            baseAmount: baseAmount,
            price: price,
            yes: oldPosition.size < 0
        });

        fundsTransferred += openResponse.marginDelta.abs();

        response = TradeResponse({
            position: openResponse.position,
            exchangedQuote: closeResponse.exchangedQuote + openResponse.exchangedQuote,
            exchangedSize: closeResponse.exchangedSize + openResponse.exchangedSize,
            realizedPnL: closeResponse.realizedPnL,
            marginDelta: closeResponse.marginDelta + openResponse.marginDelta
        });
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    
    function _boundPair(
        MarketOrder memory marketOrder,
        LimitOrder memory limitOrder
    ) internal view returns (
        MarketOrder memory filledMarketOrder, 
        LimitOrder memory filledLimitOrder
    ) {
        filledMarketOrder = _cloneMarketOrder(marketOrder);
        filledLimitOrder = _cloneLimitOrder(limitOrder);

        uint maxLimitFill = limitOrder.reduceOnly ? _boundReduceOnly(limitOrder.market, limitOrder.maker, limitOrder.baseAmount) : limitOrder.baseAmount;

        uint fillAmount = marketOrder.baseAmount.min(maxLimitFill);

        filledMarketOrder.baseAmount = fillAmount;
        filledLimitOrder.baseAmount = fillAmount;

        marketOrder.baseAmount -= fillAmount;
        limitOrder.baseAmount -= fillAmount;
    }

    /// @notice bounds a reduce-only order to the maker's position
    function _boundReduceOnly(
        uint160 market,
        address maker,
        uint256 orderAmount
    ) internal view returns (uint256 fillableOrder) {
        uint size = _position[market][maker].size.abs();
        return orderAmount.min(size);
    }

    function _cloneMarketOrder(MarketOrder memory order) internal pure returns (MarketOrder memory) {
        return MarketOrder({
            market: order.market,
            taker: order.taker,
            baseAmount: order.baseAmount,
            yes: order.yes
        });
    }
    
    function _cloneLimitOrder(LimitOrder memory order) internal pure returns (LimitOrder memory) {
        return LimitOrder({
            market: order.market,
            maker: order.maker,
            baseAmount: order.baseAmount,
            price: order.price,
            bid: order.bid,
            reduceOnly: order.reduceOnly
        });
    }

    function _accumulateResponse(
        MarketTradeResponse memory response,
        MarketTradeResponse memory newResponse
    ) internal pure {
        response.exchangedQuote += newResponse.exchangedQuote;
        response.exchangedSize += newResponse.exchangedSize;
        response.realizedPnL += newResponse.realizedPnL;
        response.marginDelta += newResponse.marginDelta;
        response.fundsTransferred += newResponse.fundsTransferred;
    }

    function _distributeFunds(
        uint160 market,
        uint fundsTransferred,
        int256 marginToTrader,
        int256 rpnl,
        address taker,
        address keeper
    ) internal {
        uint makerFee = fundsTransferred.mul(_getTransientMakerFee());
        uint creatorFee = fundsTransferred.mul(_getTransientBaseFee().mul(_creatorTakerFee));
        uint protocolFee = fundsTransferred.mul(_getTransientBaseFee());

        if (keeper != address(0)) {
            uint keeperFee = fundsTransferred.mul(_keeperFee);

            marginToTrader -= int(keeperFee);

            _feeStore[keeper] += keeperFee;
        }

        marginToTrader += rpnl - int(protocolFee);

        if (marginToTrader > 0) {
            usdb.safeTransfer({
                to: taker, 
                amount: marginToTrader.abs()
            });
        } else if (marginToTrader < 0) {
            usdb.safeTransferFrom({
                from: taker, 
                to: address(this), 
                amount: marginToTrader.abs()
            });
        }

        protocolFee = protocolFee - makerFee - creatorFee;

        if (protocolFee > 0) _feeStore[owner()] += protocolFee;
        if (creatorFee > 0) _feeStore[_creator[market]] += creatorFee;
    }

    /**
     * @notice handles storage & events for partially & fully filled limit orders
     */
    function _handleFilledLimitOrder(
        uint256 id,
        LimitOrder memory remainingOrder
    ) internal {
        if (remainingOrder.baseAmount > 0) {
            _limitOrder[id] = remainingOrder;

            emit LimitOrderUpdated({
                id: id,
                market: remainingOrder.market,
                maker: remainingOrder.maker,
                baseAmount: remainingOrder.baseAmount,
                price: remainingOrder.price,
                bid: remainingOrder.bid,
                reduceOnly: remainingOrder.reduceOnly,
                fill: true
            });
        } else {
            if (remainingOrder.reduceOnly) _unlinkLimitOrder({
                market: remainingOrder.market, 
                id: id, 
                maker: remainingOrder.maker
            });

            _removeOrderFromBook({
                market: remainingOrder.market,
                id: id, 
                price: remainingOrder.price,
                bid: remainingOrder.bid,
                useTransient: true
            });

            emit LimitOrderRemoved({
                id: id,
                filled: true
            });

            delete _limitOrder[id];
        }

        if (hasAllRoles(remainingOrder.maker, orderbookPoolRole)) {
            _orderbookPoolHook({
                pool: remainingOrder.maker,
                market: remainingOrder.market,
                id: id,
                margin: remainingOrder.reduceOnly ? 0 : _getOrderMarginRequired({
                    baseAmount: remainingOrder.baseAmount, 
                    price: remainingOrder.price,
                    bid: remainingOrder.bid
                })
            });
        }
    }

    function _handleUnfillableLimitOrder(uint256 id, LimitOrder memory order) internal {
        if (order.reduceOnly) {
            _unlinkLimitOrder({
                market: order.market, 
                id: id, 
                maker: order.maker
            });
        } else {
            usdb.safeTransfer({
                to: order.maker, 
                amount: _getOrderMarginRequired({
                    bid: order.bid, 
                    baseAmount: order.baseAmount, 
                    price: order.price
                })
            });
        }

        _removeOrderFromBook({
            id: id, 
            market: order.market,
            price: order.price,
            bid: order.bid,
            useTransient: true
        });

        delete _limitOrder[id];

        emit LimitOrderRemoved({
            id: id,
            filled: false
        });

        if (hasAllRoles(order.maker, orderbookPoolRole)) {
            _orderbookPoolHook({
                pool: order.maker,
                market: order.market,
                id: id,
                margin: 0
            });
        }
    }

    function _setTransientPosition(Position memory position) internal {
        uint slot = tPositionSlot;

        int size = position.size;   
        uint openNotional = position.openNotional;
        uint margin = position.margin;
        uint lastBlock = position.lastBlock;

        assembly {
            tstore(slot, size)
            tstore(add(slot, 1), openNotional)
            tstore(add(slot, 2), margin)
            tstore(add(slot, 3), lastBlock)
        }
    }

    function _setTransientMarkPrice(uint256 mark) internal {
        uint slot = tMarkPriceSlot;

        assembly { tstore(slot, mark) }
    }

    function _setTransientFees() internal {
        uint slot = tFeeSlot;
        
        uint baseFee = _baseTakerFee;
        uint makerFee = baseFee.mul(_makerFee);

        assembly {
            tstore(slot, baseFee)
            tstore(add(slot, 1), makerFee)
        }
    }

    function _getTransientPosition() internal view returns (Position memory position) {
        uint slot = tPositionSlot;

        int size;
        uint openNotional;
        uint margin;
        uint lastBlock;

        assembly {
            size := tload(slot)
            openNotional := tload(add(slot, 1))
            margin := tload(add(slot, 2))
            lastBlock := tload(add(slot, 3))
        }

        position = Position({
            size: size,
            openNotional: openNotional,
            margin: margin,
            lastBlock: lastBlock
        });
    }

    function _getTransientMarkPrice() internal view returns (uint mark) {
        uint slot = tMarkPriceSlot;

        assembly { mark := tload(slot) }
    }

    function _getTransientBaseFee() internal view returns (uint baseFee) {
        uint slot = tFeeSlot;

        assembly {
            baseFee := tload(slot)
        }
    }

    function _getTransientMakerFee() internal view returns (uint makerFee) {
        uint slot = tFeeSlot;

        assembly {
            makerFee := tload(add(slot, 1))
        }
    }
}