// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

struct Position {
    int256 size;
    uint256 openNotional;
    uint256 margin;
    uint256 lastBlock;
}

struct LimitOrder {
    uint160 market;
    address maker;
    uint256 baseAmount;
    uint256 price;
    bool bid;
    bool reduceOnly;
}

struct TriggerOrder{
    uint160 market;
    address taker;
    uint256 baseAmount;
    uint256 quoteLimit;
    uint256 price;
    bool stopLoss;
}

struct TickData {
    uint256[] ids;
    uint256 totalBase;
}