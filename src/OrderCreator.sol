// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

///  TYPES  ///
import { LimitOrder, TriggerOrder, TickData } from "./utils/AllInStructs.sol";

///  UTILS  ///
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { TickBitmap } from "./utils/TickBitmap.sol";

///  BASE  ///
import { AllInBase } from "./AllInBase.sol";

/// @title All-In Order Creator
/// @notice sidecar proxy used to create, update, and delete limit and trigger orders
contract OrderCreator is AllInBase {
    using TickBitmap for mapping(int16 => uint256);
    using SafeTransferLib for address;
    using FixedPointMathLib for int256;
    using SafeCastLib for uint256;

    error NOT_MAKER();
    error NOT_TAKER();
    error INVALID_LIMIT_PRICE();
    error REDUCE_ONLY_CAP();
    error NOT_REDUCE_ONLY();
    error NO_ORDER();
    error ID_ORDER_LENGTH_MISMATCH();
    error BELOW_MIN_ORDER();
    error BID_ABOVE_ASK();
    error ASK_BELOW_BID();
    error MARKET_ORDER();

    constructor(address usdb_) { usdb = usdb_; }

    /*//////////////////////////////////////////////////////////////
                     BATCH ORDER EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice creates limit orders as batch
     * 
     * @dev will revert on a single invalid order
     * @dev all limit orders must be for the same maker
     */
    function createLimitOrders(address maker, LimitOrder[] calldata orders) external returns (uint256[] memory ids) {
        uint length = orders.length;
        ids = new uint[](length);

        uint margin; uint newMargin;
        for (uint i; i < length; ++i) {
            (ids[i], newMargin) = _createLimitOrder({
                maker: maker,
                order: orders[i]
            });
            margin += newMargin;
        }

        if (margin > 0) usdb.safeTransferFrom({
            from: maker,
            to: address(this),
            amount: margin
        });
    }

    function updateLimitOrders(address maker, uint256[] calldata ids, LimitOrder[] calldata orders) external {
        uint length = ids.length;
        if (length != orders.length) revert ID_ORDER_LENGTH_MISMATCH();

        int vaultDelta;
        for (uint i; i < length; ++i) {
            vaultDelta += _updateLimitOrder({
                id: ids[i],
                maker: maker,
                newOrder: orders[i]
            });
        }

        if (vaultDelta > 0) {
            usdb.safeTransferFrom({
                from: maker,
                to: address(this),
                amount: vaultDelta.abs()
            });
        } else if (vaultDelta < 0) {
            usdb.safeTransfer({
                to: maker,
                amount: vaultDelta.abs()
            });
        }
    }

    function deleteLimitOrders(address maker, uint256[] calldata ids) external {
        uint length = ids.length;

        uint margin;
        for (uint i; i < length; ++i) {
            margin += _deleteLimitOrder({
                id: ids[i],
                maker: maker
            });
        }

        if (margin > 0) usdb.safeTransfer({
            to: maker,
            amount: margin
        });
    }

    function adminDeleteLimitOrders(uint256[] calldata ids) external {
        uint length = ids.length;

        for (uint i; i < length; ++i) {
            _adminDeleteOrder(ids[i]);
        }
    }

    function createTriggerOrders(address taker, TriggerOrder[] calldata orders) external returns (uint256[] memory ids) {
        uint length = orders.length;
        ids = new uint[](length);

        for (uint i; i < length; ++i) {
            ids[i] = _createTriggerOrder({
                taker: taker,
                order: orders[i]
            });
        }
    }

    function updateTriggerOrders(address taker, uint256[] calldata ids, TriggerOrder[] calldata orders) external {
        uint length = ids.length;
        if (length != orders.length) revert ID_ORDER_LENGTH_MISMATCH();

        for (uint i; i < length; ++i) {
            _updateTriggerOrder({
                id: ids[i],
                taker: taker,
                newOrder: orders[i]
            });
        }
    }

    function deleteTriggerOrders(address taker, uint256[] calldata ids) external {
        uint length = ids.length;

        for (uint i; i < length; ++i) {
            _deleteTriggerOrder({
                id: ids[i],
                taker: taker
            });
        }
    }

    /*//////////////////////////////////////////////////////////////
                    SINGLE ORDER INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createLimitOrder(address maker, LimitOrder calldata order) internal returns (uint256 id, uint256 margin) {
        if (maker != order.maker) revert NOT_MAKER();

        _validateLimitOrder({
            market: order.market,
            price: order.price
        });

        id = ++_orderCounter;

        // book
        _storeOrderOnBook({
            market: order.market,
            id: id,
            price: order.price,
            bid: order.bid
        });

        // margin / reduce only
        if (order.reduceOnly) { 
            _validateReduceOnlyOrder({
                market: order.market,
                maker: maker,
                baseAmount: order.baseAmount,
                bid: order.bid,
                create: true
            });

            _linkedLimitOrders[maker][order.market].push(id);
        } else {
            margin = _getOrderMarginRequired({
                bid: order.bid,
                baseAmount: order.baseAmount,
                price: order.price
            });
            if (margin < 5 ether) revert BELOW_MIN_ORDER();
        }

        // data
        _limitOrder[id] = order;

        emit LimitOrderUpdated({
            id: id,
            market: order.market,
            maker: order.maker,
            baseAmount: order.baseAmount,
            price: order.price,
            bid: order.bid,
            reduceOnly: order.reduceOnly,
            fill: false
        });

        if (hasAllRoles(maker, orderbookPoolRole)) _orderbookPoolHook({
            pool: maker,
            market: order.market,
            id: id,
            margin: margin
        });
    }

    function _updateLimitOrder(
        uint256 id, 
        address maker, 
        LimitOrder calldata newOrder
    ) internal returns (int256 vaultDelta) {
        LimitOrder memory oldOrder = _limitOrder[id];

        if (oldOrder.maker == address(0)) revert NO_ORDER();
        if (maker != newOrder.maker || maker != oldOrder.maker) revert NOT_MAKER();

        _validateLimitOrder({
            market: newOrder.market,
            price: newOrder.price
        });

        bool bookChange = newOrder.market != oldOrder.market || newOrder.price != oldOrder.price;
        bool sideChange = newOrder.bid != oldOrder.bid;

        // book
        if (bookChange || sideChange) {
            _removeOrderFromBook({
                market: oldOrder.market,
                id: id,
                price: oldOrder.price,
                bid: oldOrder.bid,
                useTransient: false
            });

            _storeOrderOnBook({
                market: newOrder.market,
                id: id,
                price: newOrder.price,
                bid: newOrder.bid
            });
        }

        // margin
        vaultDelta = _getVaultDelta({
            newMargin: _getOrderMarginRequired({
                bid: newOrder.bid,
                baseAmount: newOrder.baseAmount,
                price: newOrder.price
            }).toInt256(),
            oldMargin: _getOrderMarginRequired({
                bid: oldOrder.bid,
                baseAmount: oldOrder.baseAmount,
                price: oldOrder.price
            }).toInt256(),
            newReduceOnly: newOrder.reduceOnly,
            oldReduceOnly: oldOrder.reduceOnly
        });

        if (newOrder.reduceOnly) _validateReduceOnlyOrder({
            market: newOrder.market,
            maker: maker,
            baseAmount: newOrder.baseAmount,
            bid: newOrder.bid,
            create: false
        });

        // reduce only link
        if (newOrder.market != oldOrder.market) {
            if (oldOrder.reduceOnly) _unlinkLimitOrder({
                market: oldOrder.market,
                id: id,
                maker: maker
            });
            if (newOrder.reduceOnly) _linkedLimitOrders[maker][newOrder.market].push(id);
        } else if (newOrder.reduceOnly != oldOrder.reduceOnly) {
            if (newOrder.reduceOnly) {
                _linkedLimitOrders[maker][newOrder.market].push(id);
            } else {
                if (oldOrder.reduceOnly) _unlinkLimitOrder({
                    market: oldOrder.market,
                    id: id,
                    maker: maker
                });
            }
        }

        // data 
        _limitOrder[id] = newOrder;

        emit LimitOrderUpdated({
            id: id,
            market: newOrder.market,
            maker: newOrder.maker,
            baseAmount: newOrder.baseAmount,
            price: newOrder.price,
            bid: newOrder.bid,
            reduceOnly: newOrder.reduceOnly,
            fill: false
        });

        if (hasAllRoles(maker, orderbookPoolRole)) _orderbookPoolHook({
            pool: maker,
            market: newOrder.market,
            id: id,
            margin: newOrder.reduceOnly ? 0 : _getOrderMarginRequired({
                bid: newOrder.bid,
                baseAmount: newOrder.baseAmount,
                price: newOrder.price
            })
        });
    }

    function _deleteLimitOrder(uint256 id, address maker) internal returns (uint256 margin) {
        LimitOrder memory order = _getLimitOrder(id);

        if (order.maker == address(0)) revert NO_ORDER();
        if (maker != order.maker) revert NOT_MAKER();

        // book
        _removeOrderFromBook({
            id: id,
            market: order.market,
            price: order.price,
            bid: order.bid,
            useTransient: false
        });

        // data
        delete _limitOrder[id];
        
        if (order.reduceOnly) { // reduce only link
            _unlinkLimitOrder({
                market: order.market,
                id: id,
                maker: maker
            });
        } else {                // margin
            margin = _getOrderMarginRequired({
                bid: order.bid,
                baseAmount: order.baseAmount,
                price: order.price
            });
        }

        emit LimitOrderRemoved({
            id: id,
            filled: false
        });

        if (hasAllRoles(maker, orderbookPoolRole)) _orderbookPoolHook({
            pool: maker,
            market: order.market,
            id: id,
            margin: 0
        });

    }

    function _adminDeleteOrder(uint256 id) internal {
        LimitOrder memory order = _getLimitOrder(id);

        if (order.maker == address(0)) return;

        // book
        _removeOrderFromBook({
            id: id,
            market: order.market,
            price: order.price,
            bid: order.bid,
            useTransient: false
        });

        // data
        delete _limitOrder[id];

        if (order.reduceOnly) { // reduce only link
            _unlinkLimitOrder({
                market: order.market,
                id: id,
                maker: order.maker
            });
        } else {                // margin
            usdb.safeTransfer({
                to: order.maker,
                amount: _getOrderMarginRequired({
                    bid: order.bid,
                    baseAmount: order.baseAmount,
                    price: order.price
                })
            });
        }

        emit LimitOrderRemoved({
            id: id,
            filled: false
        });

        if (hasAllRoles(order.maker, orderbookPoolRole)) _orderbookPoolHook({
            pool: order.maker,
            market: order.market,
            id: id,
            margin: 0
        });

    }

    function _createTriggerOrder(address taker, TriggerOrder calldata order) internal returns (uint256 id) {
        if (taker != order.taker) revert NOT_TAKER();

        _validateTriggerOrder({
            market: order.market,
            taker: taker,
            amount: order.baseAmount,
            price: order.price,
            stopLoss: order.stopLoss
        });

        id = ++_orderCounter;

        _triggerOrder[id] = order;
        _linkedTriggerOrders[taker][order.market].push(id);

        emit TriggerOrderUpdated({
            id: id,
            market: order.market,
            taker: taker,
            baseAmount: order.baseAmount,
            quoteLimit: order.quoteLimit,
            price: order.price,
            stopLoss: order.stopLoss
        });
    }

    function _updateTriggerOrder(
        uint256 id, 
        address taker, 
        TriggerOrder calldata newOrder
    ) internal {
        TriggerOrder memory oldOrder = _triggerOrder[id];

        if (taker != newOrder.taker) revert NOT_TAKER();
        if (taker != oldOrder.taker) revert NOT_TAKER();

        _validateTriggerOrder({
            market: newOrder.market,
            taker: taker,
            amount: newOrder.baseAmount,
            price: newOrder.price,
            stopLoss: newOrder.stopLoss
        });

        if (newOrder.market != oldOrder.market) {
            _unlinkTriggerOrder({
                market: oldOrder.market,
                taker: taker,
                id: id
            });
            _linkedTriggerOrders[taker][newOrder.market].push(id);
        }

        _triggerOrder[id] = newOrder;

        emit TriggerOrderUpdated({
            id: id,
            market: newOrder.market,
            taker: taker,
            baseAmount: newOrder.baseAmount,
            quoteLimit: newOrder.quoteLimit,
            price: newOrder.price,
            stopLoss: newOrder.stopLoss
        });
    }

    function _deleteTriggerOrder(uint256 id, address taker) internal {
        TriggerOrder memory order = _triggerOrder[id];

        if (taker != order.taker) revert NOT_TAKER();

        delete _triggerOrder[id];

        _unlinkTriggerOrder({
            market: order.market,
            taker: taker,
            id: id
        });

        emit TriggerOrderRemoved({
            id: id,
            keeper: address(0)
        });
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _getVaultDelta(
        int256 newMargin,
        int256 oldMargin,
        bool newReduceOnly,
        bool oldReduceOnly
    ) internal pure returns (int256 vaultDelta) {
        if (!newReduceOnly) if (newMargin < 5 ether) revert BELOW_MIN_ORDER();

        if (newReduceOnly != oldReduceOnly) {
            vaultDelta = newReduceOnly ? -oldMargin : newMargin;
        } else if (!newReduceOnly && !oldReduceOnly) {
            vaultDelta = newMargin - oldMargin;
        }
    }

    function _storeOrderOnBook(
        uint160 market,
        uint256 id,
        uint256 price,
        bool bid
    ) internal {
        int24 tick = _priceToTick(price);
        if (_tick[market][tick].length == 0) _book[market].flipTick(tick, 1);

        _tick[market][tick].push(id);

        _updateBestPrice({
            market: market,
            price: price,
            bid: bid
        });
    }

    function _validateLimitOrder(
        uint160 market,
        uint256 price
    ) internal view {
        _validateMarket(market); 

        if (price % _tickSize != 0) revert INVALID_LIMIT_PRICE();
        if (price > maxPrice || price < minPrice) revert INVALID_LIMIT_PRICE();
    }

    function _updateBestPrice(
        uint160 market, 
        uint256 price, 
        bool bid
    ) internal {
        uint bestPrice = _bestPrice[market][bid];
        uint bestPriceOpp = _bestPrice[market][!bid];

        if (bestPriceOpp != 0) {
            if (bid && price >= bestPriceOpp) revert BID_ABOVE_ASK();
            else if (!bid && price <= bestPriceOpp) revert ASK_BELOW_BID();
        }

        if (bestPrice == 0) _bestPrice[market][bid] = price;
        else if (bid ? price > bestPrice : price < bestPrice) _bestPrice[market][bid] = price;
    }

    function _validateReduceOnlyOrder(
        uint160 market,
        address maker,
        uint256 baseAmount,
        bool bid,
        bool create
    ) internal view {
        if (create && _linkedLimitOrders[maker][market].length == 1) revert REDUCE_ONLY_CAP();

        int size = _position[market][maker].size;

        if (bid ? size >= 0 : size <= 0) revert NOT_REDUCE_ONLY();
        if (baseAmount > size.abs()) revert NOT_REDUCE_ONLY();
    }

    function _validateTriggerOrder(
        uint160 market,
        address taker,
        uint256 amount,
        uint256 price,
        bool stopLoss
    ) internal view {
        int size = _position[market][taker].size;

        if (size > 0) {
            uint bestBid = _bestPrice[market][true];
            if (stopLoss ? bestBid <= price : bestBid >= price) revert MARKET_ORDER();
        } else if (size < 0) {
            uint bestAsk = _bestPrice[market][false];
            if (stopLoss ? bestAsk >= price : bestAsk <= price) revert MARKET_ORDER();
        } else revert NO_POSITION();

        if (amount > size.abs()) revert INSUFFICIENT_SIZE();
    }
}