// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

///  TYPES  ///
import { LimitOrder, TriggerOrder, Position } from "./utils/AllInStructs.sol";

///  INTERFACES  ///
import { IMatchingEngine } from "./interfaces/IMatchingEngine.sol";
import { IOrderCreator } from "./interfaces/IOrderCreator.sol";
import { IUMA } from "./interfaces/IUMA.sol";

///  UTILS  ///
import { AllInMath } from "./utils/AllInMath.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { Initializable } from "solady/utils/Initializable.sol";
import { LibString } from "solady/utils/LibString.sol";

///  BASE  ///
import { AllInBase } from "./AllInBase.sol";

//   /$$$$$$  /$$       /$$             /$$$$$$ /$$   /$$                                                                      
//  /$$__  $$| $$      | $$            |_  $$_/| $$$ | $$                                                                      
// | $$  \ $$| $$      | $$              | $$  | $$$$| $$                                                                      
// | $$$$$$$$| $$      | $$              | $$  | $$ $$ $$                                                                      
// | $$__  $$| $$      | $$              | $$  | $$  $$$$                                                                      
// | $$  | $$| $$      | $$              | $$  | $$\  $$$                                                                      
// | $$  | $$| $$$$$$$$| $$$$$$$$       /$$$$$$| $$ \  $$                                                                      
// |__/  |__/|________/|________/      |______/|__/  \__/  

/// @title All-In Clearing House
contract ClearingHouse is AllInBase, Initializable {
    using FixedPointMathLib for *;
    using AllInMath for *;
    using SafeCastLib for *;
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event MarketCreated(uint160 indexed market, address indexed creator, address indexed resolver, bytes title, bytes description);
    event MarketSettled(uint160 indexed market, uint256 result);
    event MarketResolutionProposed(uint160 indexed market, int256 result);
    event MarketResolutionDisputed(uint160 indexed market);
    event TakerFeeChanged(uint256 baseFee, uint256 makerFee, uint256 creatorFee, uint256 keeperFee);
    event SettlementFeeChanged(uint256 baseFee, uint256 creatorFee);
    event FeesClaimed(address indexed user, address indexed to, uint256 amount);
    event CategoryMarketCreated(bytes categoryTitle, uint160[] markets, address indexed creator, address indexed resolver);
    event ProtocolPaused();
    event ProtocolResumed();

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error PROTOCOL_CLOSED();
    error MARKET_INVALID_FOR_SETTLEMENT();
    error MARKET_NOT_SETTLED();
    error BET_LOST();
    error INVALID_ODDS();
    error NOT_RESOLVER();
    error NOT_UMA();
    error EMPTY_METADATA();
    error INVALID_RESULT();
    error INVALID_FEE();
    error MARKET_METADATA_TOO_LONG();
    error TRIGGER_ORDER_INVALID();
    error CATEGORY_PARAM_MISMATCH();

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor (
        address oracle_,
        address matchingEngine_, 
        address orderCreator_,
        address usdb_
    ) {
        oracle = IUMA(oracle_);
        matchingEngine = matchingEngine_;
        orderCreator = orderCreator_;
        usdb = usdb_;
        _disableInitializers();
    }

    function initialize(
        address owner_,
        uint256 tickSize,
        uint256 proposalLiveness,
        uint256 reward
    ) external initializer {
        _tickSize = tickSize;
        _liveness = proposalLiveness;
        _reward = reward;

        _grantRoles(address(this), protocolActiveRole);
        _initializeOwner(owner_);
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier validMarket(uint160 market) {
        _validateMarket(market);
        
        _;
    }

    modifier checkLock {
        _assertNotLocked();
        _;
    }

    modifier setLock {
        _setTransientReentrancyLock(true);
        _;
        _setTransientReentrancyLock(false);
    }

    modifier protocolOpen {
        if (!hasAllRoles(address(this), protocolActiveRole)) revert PROTOCOL_CLOSED();
        _;
    }

    modifier Admin {
        _checkOwnerOrRoles(adminRole);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                         CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IUMA public immutable oracle;
    bytes32 constant yesNoIdentifier = "YES_OR_NO_QUERY";

    /*//////////////////////////////////////////////////////////////
                            SIDECAR PROXIES
    //////////////////////////////////////////////////////////////*/

    address immutable public matchingEngine;
    address immutable public orderCreator;

    /*//////////////////////////////////////////////////////////////
                             MARKET ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice executes a directional trade on the matching engine
    ///
    /// @dev supports closing & reverse opens
    ///
    /// @param market to trade
    /// @param baseAmount to trade
    /// @param quoteLimit if 'yes', max quote to spend, if no, min quote to receive (the same for closes, and reverse opens)
    /// @param yes direction of trade
    function openPosition(
        uint160 market,
        uint256 baseAmount,
        uint256 quoteLimit,
        bool yes
    ) external protocolOpen validMarket(market) checkLock setLock returns (uint256 quoteAmount) {
        return _trade({
            market: market,
            taker: msg.sender,
            baseAmount: baseAmount,
            quoteLimit: quoteLimit,
            yes: yes,
            keeper: address(0)
        });
    }

    /// @notice executes a closing trade on the matching engine
    ///
    /// @param market to trade
    /// @param baseAmount to close
    /// @param quoteLimit if 'yes', max quote to spend, if no, min quote to receive
    function closePosition(
        uint160 market, 
        uint256 baseAmount,
        uint256 quoteLimit
    ) external validMarket(market) checkLock setLock returns (uint256 quoteAmount) {
        int size = _position[market][msg.sender].size;

        if (size == 0) revert NO_POSITION();
        if (baseAmount > size.abs()) revert INSUFFICIENT_SIZE();

        return _trade({
            market: market,
            taker: msg.sender,
            baseAmount: baseAmount,
            quoteLimit: quoteLimit,
            yes: size < 0,
            keeper: address(0)
        });
    }

    /// @notice executes an approved closing trade an a taker's behalf
    ///
    /// @dev caller gets credited keeper fees proportional to the collateral value of the trade
    /// @dev will execute MIN(position base amount, order base amount)
    function closePositionTrigger(uint256 id) external checkLock setLock returns (uint256 quoteAmount) {
        TriggerOrder memory order = _getTriggerOrder(id);

        int size = _position[order.market][order.taker].size;

        _validateTriggerOrder({
            market: order.market,
            price: order.price,
            yes: size > 0,
            stopLoss: order.stopLoss
        });

        _unlinkTriggerOrder({
            market: order.market,
            taker: order.taker,
            id: id
        });

        quoteAmount = _trade({
            market: order.market,
            taker: order.taker,
            baseAmount: order.baseAmount.min(size.abs()),
            quoteLimit: order.quoteLimit,
            yes: size < 0,
            keeper: msg.sender
        });

        delete _triggerOrder[id];

        emit TriggerOrderRemoved({
            id: id,
            keeper: msg.sender
        });
    }

    /*//////////////////////////////////////////////////////////////
                              LIMIT ORDERS
    //////////////////////////////////////////////////////////////*/

    function createLimitOrders(LimitOrder[] calldata orders) external protocolOpen checkLock returns (uint256[] memory ids) {
        bytes memory data = abi.encodeCall(
            IOrderCreator.createLimitOrders, (
                msg.sender,
                orders
            )
        );
        return abi.decode(_delegateCall(orderCreator, data), (uint256[]));
    }

    function updateLimitOrders(uint256[] calldata ids, LimitOrder[] calldata orders) external protocolOpen checkLock {
        bytes memory data = abi.encodeCall(
            IOrderCreator.updateLimitOrders, (
                msg.sender,
                ids,
                orders
            )
        );
        _delegateCall(orderCreator, data);
    }

    function deleteLimitOrders(uint256[] calldata ids) external checkLock {
        bytes memory data = abi.encodeCall(
            IOrderCreator.deleteLimitOrders, (
                msg.sender,
                ids
            )
        );
        _delegateCall(orderCreator, data);
    }

    /*//////////////////////////////////////////////////////////////
                             TRIGGER ORDERS
    //////////////////////////////////////////////////////////////*/

    function createTriggerOrders(TriggerOrder[] calldata orders) external protocolOpen returns (uint256[] memory ids) {
        bytes memory data = abi.encodeCall(
            IOrderCreator.createTriggerOrders, (
                msg.sender,
                orders
            )
        );
        return abi.decode(_delegateCall(orderCreator, data), (uint256[]));
    }

    function updateTriggerOrders(uint256[] calldata ids, TriggerOrder[] calldata orders) external protocolOpen {
        bytes memory data = abi.encodeCall(
            IOrderCreator.updateTriggerOrders, (
                msg.sender,
                ids,
                orders
            )
        );
        _delegateCall(orderCreator, data);
    }

    function deleteTriggerOrders(uint256[] calldata ids) external {
        bytes memory data = abi.encodeCall(
            IOrderCreator.deleteTriggerOrders, (
                msg.sender,
                ids
            )
        );
        _delegateCall(orderCreator, data);
    }

    /*//////////////////////////////////////////////////////////////
                            MARKET CREATION
    //////////////////////////////////////////////////////////////*/

    /// @notice creates a new market prediction market
    ///
    /// @dev makes a price request to UMA
    ///
    /// @param title of market
    /// @param description of market
    /// @param orders initial orders
    function createMarket(
        bytes calldata title,
        bytes calldata description,
        LimitOrder[] calldata orders,
        address resolver
    ) external returns (uint160 market, uint256[] memory ids) {
        uint reward = _reward;

        usdb.safeTransferFrom({
            from: msg.sender,
            to: address(this),
            amount: reward
        });

        return _createMarket({
            title: title,
            description: description,
            orders: orders,
            resolver: resolver,
            reward: reward
        });
    }

    function createMarketCategory(
        bytes calldata categoryTitle,
        bytes[] calldata titles,
        bytes[] calldata descriptions,
        LimitOrder[][] calldata orders,
        address resolver
    ) external returns (uint160[] memory markets, uint256[][] memory ids){
        uint length = titles.length;

        if (length != descriptions.length) revert CATEGORY_PARAM_MISMATCH();
        if (length != orders.length) revert CATEGORY_PARAM_MISMATCH();

        uint reward = _reward;
        
        usdb.safeTransferFrom({
            from: msg.sender,
            to: address(this),
            amount: reward * length
        });

        markets = new uint160[](length);
        ids = new uint256[][](length);

        for (uint i; i < length; ++i) {
            (markets[i], ids[i]) = _createMarket({
                title: titles[i],
                description: descriptions[i],
                orders: orders[i],
                resolver: resolver,
                reward: reward
            });
        }

        emit CategoryMarketCreated(categoryTitle, markets, msg.sender, resolver);
    }

    /*//////////////////////////////////////////////////////////////
                               UMA HOOKS
    //////////////////////////////////////////////////////////////*/

    /// @notice called by UMA oracle when price is settled
    function priceSettled(
        bytes32,
        uint256,
        bytes memory question,
        int256 price
    ) external {
        if (msg.sender != address(oracle)) revert NOT_UMA();

        uint160 market = _umaID[keccak256(abi.encodePacked(question))];

        if (_resolver[market] != address(oracle)) revert NOT_RESOLVER();

        if (price != 1 ether && price != 0 && price != .5 ether) revert INVALID_RESULT();

        if (!hasAllRoles(address(market), validMarketRole | marketNotSettledRole)) revert MARKET_INVALID_FOR_SETTLEMENT();

        _lastPrice[market] = uint(price);

        _removeRoles(address(market), marketNotSettledRole);

        emit MarketSettled(market, uint(price));
    }

    function priceProposed(
        bytes32 identifier,
        uint256 timestamp,
        bytes memory question
    ) external {
        if (msg.sender != address(oracle)) revert NOT_UMA();

        uint160 market = _umaID[keccak256(abi.encodePacked(question))];

        if (_resolver[market] != address(oracle)) revert NOT_RESOLVER();

        emit MarketResolutionProposed({
            market: market,
            result: IUMA(oracle).requests(keccak256(abi.encodePacked(address(this), identifier, timestamp, question))).proposedPrice
        });

    }

    /// @notice called by UMA when price is disputed
    ///
    /// @dev proposer reward is refunded on dispute
    function priceDisputed(
        bytes32,
        uint256,
        bytes memory question,
        uint256 refund
    ) external {
        if (msg.sender != address(oracle)) revert NOT_UMA();

        uint160 market = _umaID[keccak256(abi.encodePacked(question))];

        if (_resolver[market] != address(oracle)) revert NOT_RESOLVER();

        _feeStore[owner()] += refund;

        emit MarketResolutionDisputed(market);
    }

    /*//////////////////////////////////////////////////////////////
                             CUSTOM RESOLVE
    //////////////////////////////////////////////////////////////*/

    function resolveMarket(uint160 market, uint256 price) external {
        if (msg.sender != _resolver[market]) revert NOT_RESOLVER();

        if (!hasAllRoles(address(market), validMarketRole | marketNotSettledRole)) revert MARKET_INVALID_FOR_SETTLEMENT();

        _removeRoles(address(market), marketNotSettledRole);

        _lastPrice[market] = price;

        emit MarketSettled(market, price);
    }

    /*//////////////////////////////////////////////////////////////
                    POSITION SETTLEMENT & FEE CLAIM
    //////////////////////////////////////////////////////////////*/
    
    /// @notice settles a position after a market has been resolved
    function settlePosition(uint160 market) external returns (uint256 totalReturn) {
        if (hasAllRoles(address(market), marketNotSettledRole)) revert MARKET_NOT_SETTLED();

        Position memory position = _getPosition(market, msg.sender);
        uint mark = _getLastPrice(market);

        if (position.size == 0) revert NO_POSITION();
        if (mark == (position.size > 0 ? 0 : 1 ether)) revert BET_LOST();

        int pnl = _getPnL({
            openNotional: position.openNotional.toInt256(),
            currentNotional: position.size.abs().mul(mark).toInt256(),
            yes: position.size > 0
        });

        if (pnl > 0) { // profit
            uint protocolFee = uint(pnl).mul(_baseSettlementFee);
            uint creatorFee = protocolFee.mul(_creatorSettlementFee);

            pnl -= int(protocolFee);
            protocolFee -= creatorFee;

            _feeStore[owner()] += protocolFee;
            _feeStore[_creator[market]] += creatorFee;
        }

        totalReturn = uint(int(position.margin) + pnl);

        delete _position[market][msg.sender];

        usdb.safeTransfer(msg.sender, totalReturn);

        emit PositionChanged({
            market: market,
            trader: msg.sender,
            markPrice: mark,
            openNotional: 0,
            size: 0,
            margin: 0,
            realizedPnL: pnl,
            exchangedQuote: 0,
            exchangedSize: 0,
            maker : false
        });
    }

    /// @notice claims fees for maker, market creator, or protocol
    function claimFees(address to) external {
        uint256 fees = _feeStore[msg.sender];
        delete _feeStore[msg.sender];

        usdb.safeTransfer(to, fees);

        emit FeesClaimed(msg.sender, to, fees);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN - PROTOCOL
    //////////////////////////////////////////////////////////////*/

    /// @notice admin function to set taker fees
    ///
    /// @dev any remaining base fee goes protocol
    ///
    /// @param baseFee % of traded margin (rpnl excluded) charged to taker orders
    /// @param creatorFee % taken out of base fee, goes to market creator
    /// @param makerFee % taken out of base fee, goes to makers
    /// @param keeperFee % of traded margin (rpnl excluded) charged to keeper orders
    function setTakerFees(
        uint256 baseFee,
        uint256 creatorFee,
        uint256 makerFee,
        uint256 keeperFee
    ) external Admin {
        if (baseFee > .005 ether) revert INVALID_FEE();
        if (creatorFee + makerFee > 1 ether) revert INVALID_FEE();
        if (keeperFee > .005 ether) revert INVALID_FEE();

        _baseTakerFee = baseFee;
        _creatorTakerFee = creatorFee;
        _makerFee = makerFee;
        _keeperFee = keeperFee;

        emit TakerFeeChanged({
            baseFee: baseFee,
            makerFee: makerFee,
            creatorFee: creatorFee,
            keeperFee: keeperFee
        });
    }

    /// @notice admin function to set settlement fees
    ///
    /// @dev any remaining base fee goes protocol
    ///
    /// @param baseFee % of profit charged at settlement
    /// @param creatorFee % taken out of base fee, goes to market creator
    function setSettlementFees(uint256 baseFee, uint256 creatorFee) external Admin {
        if (baseFee > .05 ether) revert INVALID_FEE();
        if (creatorFee > 1 ether) revert INVALID_FEE();

        _baseSettlementFee = baseFee;
        _creatorSettlementFee = creatorFee;

        emit SettlementFeeChanged({
            baseFee: baseFee,
            creatorFee: creatorFee
        });
    }

    function setProposerReward(uint256 reward) external Admin {
        _reward = reward;
    }

    /// @notice admin function to delete limit orders | DOS mitigation
    function adminDeleteLimitOrders(uint256[] calldata ids) external Admin {
        bytes memory data = abi.encodeCall(
            IOrderCreator.adminDeleteLimitOrders, (
                ids
            )
        );
        _delegateCall(orderCreator, data);
    }

    function grantAdmin(address user) external Admin {
        _grantRoles(user, adminRole);
    }

    function revokeAdmin(address user) external Admin {
        _removeRoles(user, adminRole);
    }

    function setProposalLiveness(uint256 liveness) external Admin {
        _liveness = liveness;
    }

    function grantOrderbookPool(address pool) external Admin {
        _grantRoles(pool, orderbookPoolRole);
    }

    function revokeOrderbookPool(address pool) external Admin {
        _removeRoles(pool, orderbookPoolRole);
    }

    /// @notice admin function to unpause protocol
    function openProtocol() external Admin {
        _grantRoles(address(this), protocolActiveRole);
        emit ProtocolResumed();
    }

    /// @notice admin function to pause protocol
    function pauseProtocol() external Admin {
        _removeRoles(address(this), protocolActiveRole);
        emit ProtocolPaused();
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getLastPrice(uint160 market) external view returns (uint256) {
        return _getLastPrice(market);
    }

    function getBestPrice(uint160 market, bool bid) external view returns (uint256) {
        return _bestPrice[market][bid];
    }

    function getTickSize() external view returns (uint256) {
        return _tickSize;
    }

    function getMarketTitle(uint160 market) external view returns (bytes memory) {
        return _title[market];
    }

    function getMarketDescription(uint160 market) external view returns (bytes memory) {
        return _description[market];
    }

    function getMarketCreator(uint160 market) external view returns (address) {
        return _creator[market];
    }

    function getMarketResolver(uint160 market) external view returns (address) {
        return _resolver[market];
    }

    function getPosition(uint160 market, address trader) external view returns (Position memory) {
        return _getPosition(market, trader);
    }

    function getLimitOrder(uint256 id) external view returns (LimitOrder memory) {
        return _getLimitOrder(id);
    }

    function getTriggerOrder(uint256 id) external view returns (TriggerOrder memory) {
        return _getTriggerOrder(id);
    }
    
    function getOrdersOnTick(uint160 market, int24 tick) external view returns (uint256[] memory) {
        return _tick[market][tick];
    }

    function getBaseTakerFee() external view returns (uint256) {
        return _baseTakerFee;
    }

    function getMakerFee() external view returns (uint256) {
        return _baseTakerFee.mul(_makerFee);
    }

    function getKeeperFee() external view returns (uint256) {
        return _keeperFee;
    }

    function getCreatorTakerFee() external view returns (uint256) {
        return _baseTakerFee.mul(_creatorTakerFee);
    }

    function getBaseSettlementFee() external view returns (uint256) {
        return _baseSettlementFee;
    }

    function getCreatorSettlementFee() external view returns (uint256) {
        return _baseSettlementFee.mul(_creatorSettlementFee);
    }

    function getProposerReward() external view returns (uint256) {
        return _reward;
    }

    function getOpenInterest(uint160 market) external view returns (uint256) {
        return _openInterest[market];
    }

    function getStoredFees(address trader) external view returns (uint256) {
        return _feeStore[trader];
    }

    function isAdmin(address user) external view returns (bool) {
        return hasAllRoles(user, adminRole);
    }

    function isOrderbookPool(address pool) external view returns (bool) {
        return hasAllRoles(pool, orderbookPoolRole);
    }

    function isTriggerOrderValid(uint256 id) external view returns (bool) {
        TriggerOrder memory order = _getTriggerOrder(id);
        return _isTriggerOrderValid({
            market: order.market,
            price: order.price,
            yes: _position[order.market][order.taker].size > 0,
            stopLoss: order.stopLoss
        });
    }

    function isMarketSettled(uint160 market) external view returns (bool) {
        return !hasAllRoles(address(market), marketNotSettledRole);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice executes a trade on the matching engine
    function _trade(
        uint160 market,
        address taker,
        uint256 baseAmount,
        uint256 quoteLimit,
        bool yes,
        address keeper
    ) internal returns (uint256 quoteAmount) {
        bytes memory data = abi.encodeCall(
            IMatchingEngine.takerTrade, (
                market, 
                taker, 
                baseAmount, 
                quoteLimit,
                yes, 
                keeper
            )
        );
        
        return abi.decode(_delegateCall(matchingEngine, data), (uint256));
    }

    /// @notice delegate calls into 'target' contract w/ 'data'
    ///
    /// @dev used to call into sidecar contracts
    /// @dev simplified from OZ's Address.sol
    function _delegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory result) = target.delegatecall(data);

        if (success) {
            return result;
        } else {
            assembly { revert(add(32, result), mload(result)) }
        }
    }

    function _createMarket(
        bytes calldata title,
        bytes calldata description,
        LimitOrder[] calldata orders,
        address resolver,
        uint256 reward
    ) internal returns (uint160 market, uint256[] memory ids) {
        if (title.length == 0) revert EMPTY_METADATA();
        if (description.length == 0) revert EMPTY_METADATA();

        if (resolver == address(0)) resolver = address(oracle);

        market = ++_marketCounter;

        _lastPrice[market] = .5 ether;
        _title[market] = title;
        _description[market] = description;
        _creator[market] = msg.sender;
        _bestPrice[market][true] = minPrice;
        _bestPrice[market][false] = maxPrice;
        _resolver[market] = resolver;

        _grantRoles(address(market), validMarketRole | marketNotSettledRole);

        if (resolver == address(oracle)) {
            _requestOracle({
                market: market,
                title: title,
                description: description,
                reward: reward
            });
        } else _feeStore[owner()] += reward;
        
        ids = _createInitialOrders(market, orders);

        emit MarketCreated({
            market: market,
            creator: msg.sender,
            resolver: resolver,
            title: title,
            description: description
        });
    }
    
    /// @notice requests a price from UMA oracle, see IUMA interface
    ///
    /// @dev called on market creation
    function _requestOracle(
        uint160 market, 
        bytes calldata title, 
        bytes calldata description,
        uint256 reward
    ) internal {
        bytes memory question = abi.encodePacked(
            ".title:",
            title,
            ".description:",
            description,
            ".res_data:",
            "p1: 0, p2: 1, p3: 0.5",
            ". where p1 is YES, p2 is NO, and p3 is UNKNOWN or 50/50.",
            ". updates made at https://allin.trade/",
            LibString.toString(market),
            " should be considered" 
        );

        if (question.length > 8139) revert MARKET_METADATA_TOO_LONG();

        usdb.safeApprove(address(oracle), reward);

        uint time = block.timestamp;

        bytes32 id = keccak256(abi.encodePacked(question));

        // request
        oracle.requestPrice({
            identifier: yesNoIdentifier,
            timestamp : time,
            ancillaryData: question,
            currency: usdb,
            reward: reward
        });

        // configure request
        oracle.setCustomLiveness({
            identifier: yesNoIdentifier,
            timestamp : time,
            ancillaryData: question,
            customLiveness: _liveness
        });

        oracle.setEventBased({
            identifier: yesNoIdentifier,
            timestamp : time,
            ancillaryData: question
        });

        oracle.setCallbacks({
            identifier: yesNoIdentifier,
            timestamp : time,
            ancillaryData: question,
            callbackOnPriceProposed: true,
            callbackOnPriceDisputed: true,
            callbackOnPriceSettled: true
        });

        _umaID[id] = market;
    }

    /// @notice creates initial limit orders for market
    ///
    /// @dev called on market creation
    function _createInitialOrders(uint160 market, LimitOrder[] memory orders) internal returns (uint256[] memory ids) {
        uint length = orders.length;

        if (length == 0) return ids;

        for (uint i; i < length; ++i) {
            orders[i].market = market;
        }

        bytes memory data = abi.encodeCall(
            IOrderCreator.createLimitOrders, (
                msg.sender,
                orders
            )
        );

        return abi.decode(_delegateCall(orderCreator, data), (uint256[]));
    }

    /// @notice checks if trigger order is valid for execution
    function _isTriggerOrderValid(
        uint160 market,
        uint256 price,
        bool yes,
        bool stopLoss
    ) internal view returns (bool valid) {
        uint bestPrice = _bestPrice[market][yes];

        if (yes) {
            return stopLoss ? bestPrice <= price : bestPrice >= price;
        } else {
            return stopLoss ? bestPrice >= price : bestPrice <= price;
        }
    }

    /// @notice asserts trigger order is valid for execution
    function _validateTriggerOrder(
        uint160 market,
        uint256 price,
        bool yes,
        bool stopLoss
    ) internal view {
        _validateMarket(market);
        if (!_isTriggerOrderValid({
            market: market,
            price: price,
            yes: yes,
            stopLoss: stopLoss
        })) revert TRIGGER_ORDER_INVALID();
    }
}
