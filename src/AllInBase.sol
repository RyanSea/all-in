// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

///  TYPES  ///
import { Position, LimitOrder, TriggerOrder } from "./utils/AllInStructs.sol";

/// INTERFACES ///
import { IOrderbookPool } from "./interfaces/IOrderbookPool.sol";

/// UTILS  ///
import { AllInMath } from "./utils/AllInMath.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { TickMath } from "./utils/TickMath.sol";
import { TickBitmap } from "./utils/TickBitmap.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";

abstract contract AllInBase is OwnableRoles {
    using AllInMath for *;
    using FixedPointMathLib for *;
    using TickMath for uint160;
    using TickBitmap for mapping(int16 => uint256);

    event LimitOrderUpdated(
        uint256 indexed id, 
        uint160 indexed market, 
        address indexed maker, 
        uint256 price,
        uint256 baseAmount,
        bool bid,
        bool reduceOnly,
        bool fill
    );

    event LimitOrderRemoved(uint256 indexed id, bool indexed filled);

    event TriggerOrderUpdated(
        uint256 indexed id, 
        uint160 indexed market, 
        address indexed taker, 
        uint256 price,
        uint256 baseAmount,
        uint256 quoteLimit,
        bool stopLoss
    );

    event TriggerOrderRemoved(uint256 indexed id, address indexed keeper);

    event PositionChanged(
        uint160 indexed market, 
        address indexed trader, 
        uint256 markPrice,
        uint256 openNotional,
        int256 size,
        uint256 margin,
        int256 realizedPnL,
        uint256 exchangedQuote,
        int256 exchangedSize,
        bool maker
    );

    error INVALID_MARKET();
    error MARKET_SETTLED();
    error NO_POSITION();
    error NOT_WHITELISTED();
    error INSUFFICIENT_SIZE();
    error REENTRANCY_LOCKED();

    /*//////////////////////////////////////////////////////////////
                         CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public constant tBestPriceSlot = uint256(keccak256("ALLIN.TRANSIENT.BEST.PRICE.SLOT"));

    uint256 public constant tReentrantLockSlot = uint256(keccak256("ALLIN.TRANSIENT.REENTRANT.LOCK.SLOT"));

    uint256 public constant minPrice = .001 ether;

    uint256 public constant maxPrice = 1 ether - minPrice;
    
    /// @notice min supported tick — 0.0001
    int24 internal constant minTick = -92109;

    /// @notice max supported tick — 0.9999
    int24 internal constant maxTick = -2;
    
    address immutable public usdb;

    /*//////////////////////////////////////////////////////////////
                                 ROLES
    //////////////////////////////////////////////////////////////*/

    uint256 constant public adminRole = _ROLE_1;
    uint256 constant public protocolActiveRole = _ROLE_2;
    uint256 constant public orderbookPoolRole = _ROLE_3;
    uint256 constant public validMarketRole = _ROLE_4;
    uint256 constant public marketNotSettledRole = _ROLE_5;

    /*//////////////////////////////////////////////////////////////
                              TRADER DATA
    //////////////////////////////////////////////////////////////*/

    mapping(uint160 market => mapping(address trader => Position position)) internal _position;
    mapping(uint256 id => TriggerOrder order) internal _triggerOrder;
    mapping(address trader => mapping(uint160 market => uint256[] triggerOrders)) internal _linkedTriggerOrders;

    mapping(uint256 id => LimitOrder order) internal _limitOrder;
    mapping(address trader => mapping(uint160 market => uint256[] reduceOnlyOrders)) internal _linkedLimitOrders;
    
    /// @notice storage for all credited fees
    mapping(address maker => uint256 storedFees) internal _feeStore;

    /*//////////////////////////////////////////////////////////////
                             ADMIN SETTINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice base fee taken on settlement (% of profit)
    uint256 internal _baseSettlementFee;

    /// @notice base fee taken from market trades (% of collateral traded)
    uint256 internal _baseTakerFee;

    /// @notice fee taken from market trades and credited to makers (% of base taker fee)
    uint256 internal _makerFee;

    /// @notice fee taken from market trades and credited to the market creator (% of base taker fee)
    uint256 internal _creatorTakerFee;

    /// @notice fee taken from market trades and credited to keepers (% of collateral traded)
    uint256 internal _keeperFee;

    /// @notice fee taken from position settlements and credited to market creators (% of base settlement fee)
    uint256 internal _creatorSettlementFee;

    /// @notice factor for allowed limit order prices (.001 ether)
    uint256 internal _tickSize;

    /// @notice UMA proposal liveness period, where disputes can be made
    uint256 internal _liveness;

    /// @notice UMA proposer reward
    uint256 internal _reward;

    /// @notice minimum margin required for a single limit order
    uint256 internal _minOrderMargin;

    /*//////////////////////////////////////////////////////////////
                                COUNTERS
    //////////////////////////////////////////////////////////////*/
    
    uint160 internal _marketCounter;
    uint256 internal _orderCounter;

    /*//////////////////////////////////////////////////////////////
                              MARKET DATA
    //////////////////////////////////////////////////////////////*/

    mapping(uint160 market => uint256 lastPrice) internal _lastPrice;
    mapping(uint160 market => mapping(bool bid => uint256 bestPrice)) internal _bestPrice;
    mapping(uint160 market => mapping(int16 compressedTick => uint256 bitmap)) internal _book;
    mapping(uint160 market => mapping(int24 tick => uint256[] ids)) internal _tick;
    mapping(uint160 market => uint256 openInterest) internal _openInterest;
    mapping(uint160 market => bytes title) internal _title;
    mapping(uint160 market => bytes description) internal _description;
    mapping(uint160 market => address creator) internal _creator;
    mapping(uint160 market => address resolver) internal _resolver;
    mapping(bytes32 umaID => uint160 market) internal _umaID;

    /*//////////////////////////////////////////////////////////////
                             GLOBAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setPosition(
        uint160 market,
        address trader,
        Position memory position
    ) internal {
        if (position.size != 0 && position.size.abs() < 1000) { // dust position
            position.size = 0;
            position.openNotional = 0;
            position.margin = 0;

            _clearLinkedOrders({
                market: market,
                trader: trader
            });
        }
        _position[market][trader] = position;
    }

    function _hasSufficientMargin(
        uint256 openNotional,
        int256 size,
        uint256 margin
    ) internal pure returns (bool) {
        uint maxLoss = size > 0 ? openNotional : size.abs() - openNotional;
        return margin >= maxLoss;
    }

    function _getOrderMarginRequired(
        bool bid,
        uint256 baseAmount,
        uint256 price
    ) internal pure returns (uint256) {
        uint openNotional = baseAmount.mul(price);
        return bid ? openNotional : baseAmount - openNotional;
    }

    function _getPositionMarginRequired(
        uint256 openNotional,
        int256 size
    ) internal pure returns (uint256) {
        return size > 0 ? openNotional : size.abs() - openNotional;
    }

    /// @notice converts uint256 to int24 tick
    function _priceToTick(uint256 price) internal pure returns (int24 tick) {
        return uint160(((price).sqrtF() << 96) / 1e18).getTickAtSqrtRatio();
    }

    /// @notice called on a position close, to delete all reduce only limit orders + trigger orders
    ///      that 'trader' has on 'market'
    function _clearLinkedOrders(uint160 market, address trader) internal {
        _clearLinkedLimitOrders(market, trader);
        _clearLinkedTriggerOrders(market, trader);
    }

    /// @notice deletes all of 'maker's reduce-only limit orders on 'market'
    function _clearLinkedLimitOrders(uint160 market, address maker) internal {
        uint[] memory ids = _linkedLimitOrders[maker][market];
        uint length = ids.length;
        
        for (uint i; i < length; ++i) {
            _removeOrderFromBook({
                id: ids[i],
                market: market,
                price: _limitOrder[ids[i]].price,
                bid: _limitOrder[ids[i]].bid,
                useTransient: true
            });

            delete _limitOrder[ids[i]];

            emit LimitOrderRemoved({
                id: ids[i],
                filled: false
            });
        }

        delete _linkedLimitOrders[maker][market];

        if (hasAllRoles(address(maker), orderbookPoolRole)) {
            for (uint i; i < length; ++i) {
                _orderbookPoolHook({
                    pool: address(maker),
                    market: market,
                    id: ids[i],
                    margin: 0
                });
            }
        }
    }

    /// @notice deletes all of 'taker's trigger orders on 'market'
    function _clearLinkedTriggerOrders(uint160 market, address taker) internal {
        uint[] memory ids = _linkedTriggerOrders[taker][market];
        uint length = ids.length;

        for (uint i; i < length; ++i) {
            delete _triggerOrder[ids[i]];

            emit TriggerOrderRemoved({
                id: ids[i],
                keeper: address(0)
            });
        }

        delete _linkedTriggerOrders[taker][market];
    }

    /// @notice removes a single reduce-only limit order from list
    function _unlinkLimitOrder(
        uint160 market, 
        address maker,
        uint256 id
    ) internal {
        uint[] memory ids = _pruneID({
            ids: _linkedLimitOrders[maker][market],
            id: id
        });

        _linkedLimitOrders[maker][market] = ids;
    }

    /// @notice removes a single trigger order from list
    function _unlinkTriggerOrder(
        uint160 market,
        address taker,
        uint256 id
    ) internal {
        uint[] memory ids = _pruneID({
            ids: _linkedTriggerOrders[taker][market],
            id: id
        });

        _linkedTriggerOrders[taker][market] = ids;
    }

    /**
     * @notice removes an order from the orderbook, and updates the best price if necessary
     * 
     * @param market of order
     * @param id of order
     * @param price of order
     * @param bid whether order is a bid
     * @param useTransient flag called during market orders 
     */
    function _removeOrderFromBook(
        uint160 market,
        uint256 id, 
        uint256 price,
        bool bid,
        bool useTransient
    ) internal {
        int24 tick = _priceToTick(price);
        uint[] memory ids = _pruneID({
            ids : _tick[market][tick],
            id: id
        });

        _tick[market][tick] = ids;

        if (ids.length == 0) {
            _book[market].flipTick(tick, 1);

            if (useTransient && price == _getTransientBestPrice(bid)) {
                _setTransientBestPrice(bid, _findBestPrice(market, tick, bid));
            } else if (!useTransient && price == _bestPrice[market][bid]) {
                _bestPrice[market][bid] = _findBestPrice(market, tick, bid);
            }
        }
    }

    /// @notice removes an id from an array of ids, while maintaining ordering
    function _pruneID(uint256[] memory ids, uint256 id) internal pure returns (uint256[] memory) {
        uint length = ids.length;

        uint p;
        for (uint i; i < length; ++i) {
            if (ids[i] != id) {
                ids[p++] = ids[i];
            } 
        }

        assembly { mstore(ids, p) }

        return ids;
    }

    /// @notice searches 'markets' book from 'startTick', to find the next initialized tick
    function _findBestPrice(
        uint160 market, 
        int24 startTick,
        bool bid
    ) internal view returns (uint bestPrice) {
        int24 finalTick = bid ? minTick : maxTick;

        // note: lib doesn't check current tick if iterating up
        if (!bid) --startTick;

        bool initialized; LimitOrder memory order;
        while (bid ? startTick > finalTick : startTick < finalTick) {
            (startTick, initialized) = _book[market].nextInitializedTickWithinOneWord({
                tick: startTick,
                tickSpacing: 1,
                lte: bid
            });

            if (initialized) {
                order = _getLimitOrder(_tick[market][startTick][0]);

                if (order.bid == bid) return order.price;
            }

            // note: lib doesn't iterate down
            if (bid) --startTick;
        }

        // set best price to default value if none is found
        bestPrice = bid ? minPrice : maxPrice;
    }

    function _getPnL(
        int256 openNotional,
        int256 currentNotional,
        bool yes
    ) internal pure returns (int256) {
        return yes ? currentNotional - openNotional : openNotional - currentNotional;
    }

    function _orderbookPoolHook(
        address pool,
        uint160 market,
        uint256 id,
        uint256 margin
    ) internal {
        IOrderbookPool(pool).orderUpdated({
            market: market,
            id: id,
            margin: margin
        });
    }

    function _getLastPrice(uint160 market) internal view returns (uint256) {
        return _lastPrice[market];
    }

    function _getPosition(uint160 market, address trader) internal view returns (Position memory) {
        return _position[market][trader];
    }

    function _getLimitOrder(uint256 id) internal view returns (LimitOrder memory) {
        return _limitOrder[id];
    }

    function _getTriggerOrder(uint256 id) internal view returns (TriggerOrder memory) {
        return _triggerOrder[id];
    }

    function _setTransientBestPrice(bool bid, uint price) internal {
        uint slot = tBestPriceSlot;
        assembly { tstore(add(slot, bid), price) }
    }

    function _setTransientReentrancyLock(bool lock) internal {
        uint slot = tReentrantLockSlot;

        assembly { tstore(slot, lock) }
    }

    function _getTransientBestPrice(bool bid) internal view returns (uint price) {
        uint slot = tBestPriceSlot;
        assembly { price := tload(add(slot, bid)) }
    }

    function _isTransientReentrancyGuardLocked() internal view returns (bool locked) {
        uint slot = tReentrantLockSlot;

        assembly { locked := iszero(iszero(tload(slot))) }
    }

    function _assertNotLocked() internal view {
        if (_isTransientReentrancyGuardLocked()) revert REENTRANCY_LOCKED();
    }

    function _validateMarket(uint160 market) internal view {
        if (!hasAllRoles(address(market), validMarketRole)) revert INVALID_MARKET();
        if (!hasAllRoles(address(market), marketNotSettledRole)) revert MARKET_SETTLED();
    }
}