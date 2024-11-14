## All-In

**All-In is a fully permissionless orderbook-based prediction market with fully onchain matching.**

All-In consists of:

-   **ClearingHouse.sol**: The single point of entry for the entire market place.
-   **OrderCreator.sol**: A sidecar proxy that handles limit & trigger order creation / updates / deletion
-   **MatchingEngine.sol**: A sidecar proxy that matches & fills incoming market orders with limit orders.

## Documentation

### Market Creation
Market creators can create markets by defining a title, description, and optional initial limit orders. Creators must post a $5 bounty when creating a market, to be paid to resolvers. On creation, a request is made to UMA using an event-based YES_OR_NO_QUERY. Once the market can be resolved (i.e. after a date specified in the title/description) a resolver can propose a result. Once a result is proposed, the proposal has a liveness window in which the proposal can be disputed. 

### Market Resolution
After the resolution is settled on UMA, the market will resolve to 1 for (True), 0 (False), or .5 (Unknown). Trading will pause and traders can settle their position on the settled price.

### Order Types
**Limit Order** — Limit orders are stored on the book, where they await to be filled by incoming market orders. Makers can specify base amount, price, and a bid/ask flag, and a reduce-only flag. A bid must be placed below the best ask, and an ask must be placed above the best bid. A reduce-only order is an order that must result in a decrease or close for a maker. This is asserted on order creation, but if a maker partially closes before the reduce-only is filled, then the reduce-only order will be bounded by the position size before being filled. If the maker fully closes before the reduce-only order is filled, then the reduce-only order will be deleted automatically.
There is a 5 USDB min order requirement for limit orders. Reduce-only orders require no collateral to post, but maker's can only have one posted at a time.
Filled maker orders earn maker fees. 

**Trigger Orders** — Trigger orders are an approval for a market close to be executed by a 3rd party (a keeper) in the future. Takers can define a trigger order with base amount, quote limit, price, and a stop-loss / take-profit flag. The rules for a Yes take-profit is the best bid must be below the trigger price, for a Yes stop-loss the best bid must be above the trigger price, for a No take-profit the best ask must be above the trigger price, for a No stop-loss the best ask must be below the trigger price. 
If a trigger order meets these rules on order creation, it is a market order, and it will revert. 
Takers must pay keeper fees on top of the protocol fee on a successful trigger order fill. 

**Market Orders** — The two market orders are Open (which can also be used for closes) and Close (which asserts that the taker has enough of a position to close).Market orders begin filling at the best bid or ask, and will continue filling until either the order or book liquidity is exhausted. Takers define a base amount, quote limit (optional), and opens contain a yes/no flag which determines the direction of the trade. 
On a Yes directional trade (Yes open or No close), if a defined quote limit is exceeded the trade will revert. On a No directional trade (No open or Yes close), if the quote limit is unmet, the trade will revert. If the quote limit is left as 0, it's ignored. 
With base amount & quote limit, traders can define collateral they wish to trade with.
Market orders pay protocol fees. 

### Collateral Requirements
All-In requires positions to be backed with 100% collateral. The collateral required for a Yes position equivalent to the quote amount opened. The collateral required for a No position is equivalent to the base amount opened - the quote amount opened. Quote amount can be calculated by multiplying base amount by price. 
For example, if a market order is filled across 2 limit orders the quote amount would be baseFilled1 * price1 + baseFilled2 * price2.

### Fees
The two sets of fees are Taker & Settlement fees.

**Taker Fees** are defined in the Base Taker Fee and the Keeper Fee (if it's a trigger order), which are a % of the rpnl-excluded collateral traded. Orderbook makers & the market creator earn Maker Fees and Creator Taker Fees respectively. Both fo these are taken as a % of the Base Taker Fee. The protocol itself earns any remainder. 

**Settlement Fees** are defined in the Base Settlement Fee, which is a % of the profit on position settlement, after a market is resolved. The market creator earns Creator Settlement Fees, which are a % of the Base Settlement Fee. The protocol itself earns any remainder. 


### Matching Engine
Matching Engine is entered through from a takerTrade()
Prices with orders stored are initialized with a UNIV3 tick bitmap, which is used for searching the book. Each price with orderbook liquidity has an array of the ids mapped to it, which are the order ids for that price. 

Matching itself consists of 2 core functions, 
    • _match() — which gets orders on the best price and loops through each to pair with the market order
    • _matchPair() which first bounds the fill amount by ```MIN(market order amount, limit order amount, [maker position if limit order is reduce-only])```
      from there, it uses the fill amount to update the position of the taker & maker, and updates the orderbook
Once the last order on a tick is filled, the next best price is found and the loop starts again in _match(). This continues until either the market order is filled or liquidity is exhausted.

There are filling functions for limit & market orders, which both call into a shared _routeTrade() function, which routes ultimately routes the order to _increasePosition(), _decreasePosition(), or _closePosition(). 

### Order Creator
Order Creator is used to validate and store (or remove) limit & trigger orders. Limit orders are stored on the book described above
