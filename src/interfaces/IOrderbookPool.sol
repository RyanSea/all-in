// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

interface IOrderbookPool {
    function orderUpdated(uint160 market, uint256 id, uint256 margin) external;
}