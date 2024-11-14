// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

interface IMatchingEngine {
    function takerTrade(
        uint160 market,
        address taker,
        uint256 baseAmount,
        uint256 quoteLimit,
        bool buy,
        address keeper
    ) external returns (uint256 quoteAmount);
}