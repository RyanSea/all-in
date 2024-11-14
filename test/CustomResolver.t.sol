// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./AllInTestSetup.sol";

contract CustomResolverTest is AllInTestSetup {
    
    function test_CustomResolver() public {
        LimitOrder[] memory orders;

        bytes memory title = "Custom Market";
        bytes memory description = "A market";

        uint protocolFeeBefore = clearingHouse.getStoredFees(owner);

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit ClearingHouse.MarketCreated({
            market: 3,
            creator: rite,
            resolver: daniel,
            title: title,
            description: description
        });

        vm.prank(rite);
        (uint160 market, ) = clearingHouse.createMarket({
            title: title,
            description: description,
            orders: orders,
            resolver: daniel
        });

        assertEq(clearingHouse.getStoredFees(owner), protocolFeeBefore + 5 ether, "PROTOCOL FEE INCORRECT");

        bytes memory question = _getData(title, description, market);

        vm.startPrank(address(uma));

        vm.expectRevert(ClearingHouse.NOT_RESOLVER.selector);
        clearingHouse.priceProposed(0, 0, question);

        vm.expectRevert(ClearingHouse.NOT_RESOLVER.selector);
        clearingHouse.priceDisputed(0, 0, question, 5 ether);

        vm.expectRevert(ClearingHouse.NOT_RESOLVER.selector);
        clearingHouse.priceSettled(0, 0, question, 1 ether);

        vm.startPrank(daniel);

        vm.expectRevert(ClearingHouse.NOT_UMA.selector);
        clearingHouse.priceProposed(0, 0, question);

        vm.expectRevert(ClearingHouse.NOT_UMA.selector);
        clearingHouse.priceDisputed(0, 0, question, 5 ether);

        vm.expectRevert(ClearingHouse.NOT_UMA.selector);
        clearingHouse.priceSettled(0, 0, question, 1 ether);

        assertFalse(clearingHouse.isMarketSettled(market), "MARKET SHOULD NOT BE RESOLVED");

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit ClearingHouse.MarketSettled({
            market: market,
            result: 1 ether
        });
        clearingHouse.resolveMarket(market, 1 ether);

        assertTrue(clearingHouse.isMarketSettled(market), "MARKET SHOULD BE RESOLVED");

        vm.expectRevert(ClearingHouse.MARKET_INVALID_FOR_SETTLEMENT.selector);

        clearingHouse.resolveMarket(market, 1 ether);
    }

   

}