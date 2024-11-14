// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { ClearingHouse } from "src/ClearingHouse.sol";
import { TickBitmap } from "src/utils/TickBitmap.sol";

import "forge-std/console.sol";

contract MockClearingHouse is ClearingHouse {
    using TickBitmap for mapping(int16 => uint256);

    bool constant public IS_SCRIPT = true;

    uint256 internal constant randomSlot = uint256(keccak256("ALLIN.TEST.randomSlot"));

    constructor(address oracle_, address matchingEngine_, address orderCreator_, address usdb_) ClearingHouse(oracle_, matchingEngine_, orderCreator_, usdb_) {}

    function setPrice(uint160 market, uint256 price) external {
        _lastPrice[market] = price;
    }

    function isTickInitialized(
        uint160 market, 
        int24 tick, 
        bool lte
    ) external view returns (bool initialized) {
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

    function getPriceToTick(uint256 price) external pure returns (int24 tick) {
        return _priceToTick(price);
    }

    function getOrderMarginRequired(
        uint256 baseAmount,
        uint256 price,
        bool bid
    ) external pure returns (uint256 margin) {
        return _getOrderMarginRequired({
            bid: bid,
            baseAmount: baseAmount,
            price: price
        });
    }

    function hasSufficientMargin(
        uint256 openNotional,
        int256 size,
        uint256 margin
    ) external pure returns (bool) {
        return _hasSufficientMargin({
            openNotional: openNotional,
            size: size,
            margin: margin
        });
    }

    function getValue(uint length) external view returns (bytes memory value) {
        uint slot = randomSlot;

        bytes32 nextValue;
        for (uint i; i < length; ++i) {
            assembly { nextValue := sload(add(slot, i)) }
            value = bytes.concat(value, nextValue);
        }
    }

    function getLinkedLimitOrders(uint160 market, address trader) external view returns (uint[] memory) {
        return _linkedLimitOrders[trader][market];
    }

    function pruneID(uint[] memory ids, uint id) external pure returns (uint[] memory) {
        return _pruneID(ids, id);
    }
}