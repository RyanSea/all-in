// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import { LimitOrder, TriggerOrder } from "../utils/AllInStructs.sol";

interface IOrderCreator {
    function createLimitOrders(address maker, LimitOrder[] calldata orders) external returns (uint256[] memory ids);
    function updateLimitOrders(address maker, uint256[] calldata ids, LimitOrder[] calldata orders) external;
    function deleteLimitOrders(address maker, uint256[] calldata ids) external;
    function adminDeleteLimitOrders(uint256[] calldata ids) external;
    function createTriggerOrders(address taker, TriggerOrder[] calldata orders) external returns (uint256[] memory ids);
    function updateTriggerOrders(address taker, uint256[] calldata ids, TriggerOrder[] calldata orders) external;
    function deleteTriggerOrders(address taker, uint256[] calldata ids) external;
}
