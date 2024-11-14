// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./AllInTestSetup.sol";
import { AllInBase } from "src/AllInBase.sol";

contract TriggerOrderTradeTest is AllInTestSetup {
    using AllInMath for uint;

    function test_TriggerOrderTrade_StopLoss_Yes() public {
        LimitOrder[] memory orders = new LimitOrder[](3);

        orders[0] = LimitOrder({
            maker: daniel,
            market: trump,
            price: .4 ether,
            baseAmount: 50 ether,
            bid: true,
            reduceOnly: false
        });
        orders[1] = LimitOrder({
            maker: daniel,
            market: trump,
            price: .5 ether,
            baseAmount: 50 ether,
            bid: false,
            reduceOnly: false
        });
        orders[2] = LimitOrder({
            maker: daniel,
            market: trump,
            price: .3 ether,
            baseAmount: 70 ether,
            bid: true,
            reduceOnly: false
        });

        vm.prank(daniel);
        uint[] memory ids = clearingHouse.createLimitOrders(orders);

        vm.prank(rite);
        clearingHouse.openPosition(trump, 50 ether, 0, true);

        uint margin = clearingHouse.getPosition(trump, rite).margin;

        vm.roll(block.number + 1);

        TriggerOrder[] memory triggerOrders = new TriggerOrder[](1);

        triggerOrders[0] = TriggerOrder({
            taker: rite,
            market: trump,
            price: .35 ether,
            baseAmount: 50 ether,
            quoteLimit: 0,
            stopLoss: true
        });

        vm.prank(rite);
        uint triggerID = clearingHouse.createTriggerOrders(triggerOrders)[0];

        assertFalse(clearingHouse.isTriggerOrderValid(triggerID), "TRIGGER ORDER ACTIVE");

        assembly { mstore(ids, 1) } // pop last 2 from ids

        vm.prank(daniel);
        clearingHouse.deleteLimitOrders(ids);

        assertTrue(clearingHouse.isTriggerOrderValid(triggerID), "TRIGGER ORDER INACTIVE");

        vm.expectEmit(true, true, true, true, address(clearingHouse));

        emit AllInBase.TriggerOrderRemoved({
            id: triggerID,
            keeper: joe
        });

        vm.prank(joe);
        clearingHouse.closePositionTrigger(triggerID);

        assertEq(clearingHouse.getPosition(trump, rite).size, 0, "POSITION NOT CLOSED");
        assertEq(clearingHouse.getTriggerOrder(triggerID).taker, address(0), "TRIGGER ORDER NOT DELETED");
        assertEq(clearingHouse.getStoredFees(joe), margin.mul(clearingHouse.getKeeperFee()), "FEE WRONG");
    }
}