// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./AllInTestSetup.sol";

contract FeesTest is AllInTestSetup {
    using AllInMath for *;

    uint limitAmount1;
    uint limitAmount2;
    uint limitPrice1;
    uint limitPrice2;

    uint marginBefore;

    uint makerFee1;
    uint makerFee2;
    uint protocolFee;
    uint creatorFee;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        clearingHouse.setTakerFees({
            baseFee: .003 ether,
            makerFee: .5 ether,
            creatorFee: .25 ether,
            keeperFee: .001 ether
        });

        clearingHouse.setSettlementFees({
            baseFee: .02 ether,
            creatorFee: .5 ether
        });
    }

    /*//////////////////////////////////////////////////////////////
                               OPEN FEES
    //////////////////////////////////////////////////////////////*/
    
    function test_Fees_Taker_Open_Yes(uint random) public {
        uint size = clearingHouse.getTickSize();

        limitAmount1 = bound(random, 300 ether, 5000 ether);
        limitAmount2 = bound(random, 300 ether, 5000 ether);

        limitPrice1 = bound(random, clearingHouse.getLastPrice(trump) + size, .75 ether);
        limitPrice2 = bound(random, clearingHouse.getLastPrice(trump) + size, .75 ether);

        if (limitPrice1 % size != 0) limitPrice1 -= (limitPrice1 % size);
        if (limitPrice2 % size != 0) limitPrice2 -= (limitPrice2 % size);

        _createLimitOrder(daniel, limitPrice1, limitAmount1, false);
        _createLimitOrder(aster, limitPrice2, limitAmount2, false);

        changePrank(rite);
        uint openNotional = clearingHouse.openPosition(trump, limitAmount1 + limitAmount2, 0, true);

        makerFee1 = clearingHouse.getOrderMarginRequired(limitAmount1, limitPrice1, true).mul(clearingHouse.getMakerFee());
        makerFee2 = clearingHouse.getOrderMarginRequired(limitAmount2, limitPrice2, true).mul(clearingHouse.getMakerFee());

        uint takerMargin = _getTakerMarginRequired(openNotional, int(limitAmount1 + limitAmount2));

        protocolFee = takerMargin.mul(clearingHouse.getBaseTakerFee()) - takerMargin.mul(clearingHouse.getMakerFee());
        
        // note: essentially checks actual fees transferred >= fees owed to makers
        assertTrue(protocolFee >= (makerFee1 + makerFee2), "BAD FEE ROUNDING");

        creatorFee = takerMargin.mul(clearingHouse.getCreatorTakerFee());
        protocolFee -= creatorFee;

        assertEq(clearingHouse.getStoredFees(daniel), makerFee1, "MAKER FEE 1 WRONG");
        assertEq(clearingHouse.getStoredFees(aster), makerFee2, "MAKER FEE 2 WRONG");
        assertEq(clearingHouse.getStoredFees(owner), protocolFee, "TAKER FEE WRONG");
        assertEq(clearingHouse.getStoredFees(clearingHouse.getMarketCreator(trump)), creatorFee, "CREATOR FEE WRONG");
    }

    function test_Fees_Taker_Open_No(uint random) public {
        uint size = clearingHouse.getTickSize();

        limitAmount1 = bound(random, 300 ether, 5000 ether);
        limitAmount2 = bound(random, 300 ether, 5000 ether);

        limitPrice1 = bound(random, .25 ether, clearingHouse.getLastPrice(trump) - size);
        limitPrice2 = bound(random, .25 ether, clearingHouse.getLastPrice(trump) - size);

        if (limitPrice1 % size != 0) limitPrice1 -= (limitPrice1 % size);
        if (limitPrice2 % size != 0) limitPrice2 -= (limitPrice2 % size);

        _createLimitOrder(daniel, limitPrice1, limitAmount1, true);
        _createLimitOrder(aster, limitPrice2, limitAmount2, true);

        changePrank(rite);
        uint openNotional = clearingHouse.openPosition(trump, limitAmount1 + limitAmount2, 0, false);

        makerFee1 = clearingHouse.getOrderMarginRequired(limitAmount1, limitPrice1, false).mul(clearingHouse.getMakerFee());
        makerFee2 = clearingHouse.getOrderMarginRequired(limitAmount2, limitPrice2, false).mul(clearingHouse.getMakerFee());

        uint takerMargin = _getTakerMarginRequired(openNotional, -int(limitAmount1 + limitAmount2));

        protocolFee = takerMargin.mul(clearingHouse.getBaseTakerFee()) - takerMargin.mul(clearingHouse.getMakerFee());
        
        // note: essentially checks actual fees transferred >= fees owed to makers
        assertTrue(protocolFee >= (makerFee1 + makerFee2), "BAD FEE ROUNDING");

        creatorFee = takerMargin.mul(clearingHouse.getCreatorTakerFee());
        protocolFee -= creatorFee;

        assertEq(clearingHouse.getStoredFees(daniel), makerFee1, "MAKER FEE 1 WRONG");
        assertEq(clearingHouse.getStoredFees(aster), makerFee2, "MAKER FEE 2 WRONG");
        assertEq(clearingHouse.getStoredFees(owner), protocolFee, "TAKER FEE WRONG");
        assertEq(clearingHouse.getStoredFees(clearingHouse.getMarketCreator(trump)), creatorFee, "CREATOR FEE WRONG");
    }

    /*//////////////////////////////////////////////////////////////
                               CLOSE FEES
    //////////////////////////////////////////////////////////////*/

    function test_Fees_Taker_PartialClose_Yes(uint random) public {
        uint size = clearingHouse.getTickSize();
        uint openAmount = limitAmount1 = bound(random, 550 ether, 5000 ether);

        limitPrice1 = bound(random, clearingHouse.getLastPrice(trump) + size, .75 ether);

        if (limitPrice1 % size != 0) limitPrice1 -= (limitPrice1 % size);

        _createLimitOrder(daniel, limitPrice1, limitAmount1, false);

        changePrank(rite);  
        uint openNotional = clearingHouse.openPosition(trump, limitAmount1, 0, true);

        marginBefore = clearingHouse.getOrderMarginRequired(limitAmount1, limitPrice1, true);

        uint makerFeeBefore = clearingHouse.getStoredFees(daniel);
        uint protocolFeeBefore = clearingHouse.getStoredFees(owner);
        uint creatorFeeBefore = clearingHouse.getStoredFees(clearingHouse.getMarketCreator(trump));

        limitAmount1 = bound(limitAmount1, 250 ether, openAmount - .2 ether);
        limitAmount2 = bound(random, 250 ether , openAmount - limitAmount1 - .1 ether);

        limitPrice1 = bound(random, .25 ether, .76 ether);
        limitPrice2 = bound(random, .25 ether, limitPrice1);

        if (limitPrice1 % size != 0) limitPrice1 -= (limitPrice1 % size);
        if (limitPrice2 % size != 0) limitPrice2 -= (limitPrice2 % size);

        clearingHouse.setPrice(trump, limitPrice1);

        _createLimitOrder(daniel, limitPrice1, limitAmount1, true);
        _createLimitOrder(aster, limitPrice2, limitAmount2, true);

        vm.roll(block.number + 1);

        uint ratio = limitAmount1.div(openAmount);

        uint tradedOpenNotional = openNotional.mul(ratio);

        openNotional -= tradedOpenNotional;
        openAmount -= limitAmount1;

        uint takerMarginTransferred1 = marginBefore - _getTakerMarginRequired(openNotional, int(openAmount));
        marginBefore = _getTakerMarginRequired(openNotional, int(openAmount));

        makerFee1 = takerMarginTransferred1.mul(clearingHouse.getMakerFee());

        ratio = limitAmount2.div(openAmount);

        tradedOpenNotional = openNotional.mul(ratio);

        openNotional -= tradedOpenNotional;
        openAmount -= limitAmount2;

        uint takerMarginTransferred2 = marginBefore - _getTakerMarginRequired(openNotional, int(openAmount));

        makerFee2 = takerMarginTransferred2.mul(clearingHouse.getMakerFee());

        uint takerMargin = takerMarginTransferred1 + takerMarginTransferred2;

        protocolFee = takerMargin.mul(clearingHouse.getBaseTakerFee()) - takerMargin.mul(clearingHouse.getMakerFee());

        vm.roll(block.number + 1);

        uint closeAmount = limitAmount1 + limitAmount2;

        changePrank(rite);
        clearingHouse.closePosition(trump, closeAmount, 0);

        // note: essentially checks actual fees transferred >= fees owed to makers
        assertTrue(protocolFee >= (makerFee1 + makerFee2), "BAD FEE ROUNDING");

        creatorFee = takerMargin.mul(clearingHouse.getCreatorTakerFee());
        protocolFee -= creatorFee;

        assertEq(clearingHouse.getStoredFees(daniel) - makerFeeBefore, makerFee1, "MAKER FEE 1 WRONG");
        assertEq(clearingHouse.getStoredFees(aster), makerFee2, "MAKER FEE 2 WRONG");
        assertEq(clearingHouse.getStoredFees(owner) - protocolFeeBefore, protocolFee, "PROTOCOL FEE WRONG");
        assertEq(clearingHouse.getStoredFees(clearingHouse.getMarketCreator(trump)) - creatorFeeBefore, creatorFee, "CREATOR FEE WRONG");
    }

    function test_Fees_Taker_PartialClose_No(uint random) public {
        uint size = clearingHouse.getTickSize();
        uint openAmount = limitAmount1 = bound(random, 550 ether, 5000 ether);

        limitPrice1 = bound(random, .25 ether, clearingHouse.getLastPrice(trump) - size);

        if (limitPrice1 % size != 0) limitPrice1 -= (limitPrice1 % size);

        _createLimitOrder(daniel, limitPrice1, limitAmount1, true);

        changePrank(rite);  
        uint openNotional = clearingHouse.openPosition(trump, limitAmount1, 0, false);

        marginBefore = clearingHouse.getOrderMarginRequired(limitAmount1, limitPrice1, false);

        uint makerFeeBefore = clearingHouse.getStoredFees(daniel);
        uint protocolFeeBefore = clearingHouse.getStoredFees(owner);
        uint creatorFeeBefore = clearingHouse.getStoredFees(clearingHouse.getMarketCreator(trump));

        limitAmount1 = bound(limitAmount1, 250 ether, openAmount - .2 ether);
        limitAmount2 = bound(random, 250 ether, openAmount - limitAmount1 - .1 ether);

        limitPrice1 = bound(random, .1 ether, .9 ether);
        limitPrice2 = bound(random, limitPrice1, .9 ether);

        if (limitPrice1 % size != 0) limitPrice1 -= (limitPrice1 % size);
        if (limitPrice2 % size != 0) limitPrice2 -= (limitPrice2 % size);

        clearingHouse.setPrice(trump, limitPrice1);

        _createLimitOrder(daniel, limitPrice1, limitAmount1, false);
        _createLimitOrder(aster, limitPrice2, limitAmount2, false);

        vm.roll(block.number + 1);

        uint ratio = limitAmount1.div(openAmount);

        uint tradedOpenNotional = openNotional.mul(ratio);

        openNotional -= tradedOpenNotional;
        openAmount -= limitAmount1;

        uint takerMarginTransferred1 = marginBefore - _getTakerMarginRequired(openNotional, -int(openAmount));
        marginBefore = _getTakerMarginRequired(openNotional, -int(openAmount));

        makerFee1 = takerMarginTransferred1.mul(clearingHouse.getMakerFee());

        ratio = limitAmount2.div(openAmount);

        tradedOpenNotional = openNotional.mul(ratio);

        openNotional -= tradedOpenNotional;
        openAmount -= limitAmount2;

        uint takerMarginTransferred2 = marginBefore - _getTakerMarginRequired(openNotional, -int(openAmount));

        makerFee2 = takerMarginTransferred2.mul(clearingHouse.getMakerFee());

        uint takerMargin = takerMarginTransferred1 + takerMarginTransferred2;

        protocolFee = takerMargin.mul(clearingHouse.getBaseTakerFee()) - takerMargin.mul(clearingHouse.getMakerFee());

        vm.roll(block.number + 1);

        uint closeAmount = limitAmount1 + limitAmount2;

        changePrank(rite);
        clearingHouse.closePosition(trump, closeAmount, 0);

        // note: essentially checks actual fees transferred >= fees owed to makers
        assertTrue(protocolFee >= (makerFee1 + makerFee2), "BAD FEE ROUNDING");

        creatorFee = takerMargin.mul(clearingHouse.getCreatorTakerFee());
        protocolFee -= creatorFee;

        assertEq(clearingHouse.getStoredFees(daniel) - makerFeeBefore, makerFee1, "MAKER FEE 1 WRONG");
        assertEq(clearingHouse.getStoredFees(aster), makerFee2, "MAKER FEE 2 WRONG");
        assertEq(clearingHouse.getStoredFees(owner) - protocolFeeBefore, protocolFee, "PROTOCOL FEE WRONG");
        assertEq(clearingHouse.getStoredFees(clearingHouse.getMarketCreator(trump)) - creatorFeeBefore, creatorFee, "CREATOR FEE WRONG");
    }

    /*//////////////////////////////////////////////////////////////
                              SETTLE FEES
    //////////////////////////////////////////////////////////////*/

    function test_Fees_Settlement_YesWins() public {
        LimitOrder[] memory orders = new LimitOrder[](1);

        uint win = 1 ether;
        uint orderAmount = 100 ether;
        uint margin;

        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: orderAmount,
            price: .5 ether,
            bid: false,
            reduceOnly: false
        });

        changePrank(daniel);
        clearingHouse.createLimitOrders(orders);

        changePrank(rite);
        uint openNotional = margin = clearingHouse.openPosition(trump, orderAmount, 0, true);

        changePrank(address(uma));
        clearingHouse.priceSettled(0, marketsTimestamp[trump], marketsQuestion[trump], int(win));

        uint creatorFeeBefore = clearingHouse.getStoredFees(clearingHouse.getMarketCreator(trump));
        uint protocolFeeBefore = clearingHouse.getStoredFees(owner);
        uint winnerBalBefore = usdb.balanceOf(rite);

        changePrank(daniel);
        vm.expectRevert(ClearingHouse.BET_LOST.selector);
        clearingHouse.settlePosition(trump);

        uint profit = win.mul(orderAmount) - openNotional;

        protocolFee = profit.mul(clearingHouse.getBaseSettlementFee());
        creatorFee = profit.mul(clearingHouse.getCreatorSettlementFee());

        profit -= protocolFee;
        protocolFee -= creatorFee;


        changePrank(rite);
        clearingHouse.settlePosition(trump);

        assertEq(clearingHouse.getStoredFees(clearingHouse.getMarketCreator(trump)) - creatorFeeBefore, creatorFee, "CREATOR FEE WRONG");
        assertEq(clearingHouse.getStoredFees(owner) - protocolFeeBefore, protocolFee, "PROTOCOL FEE WRONG");
        assertEq(usdb.balanceOf(rite) - winnerBalBefore, profit + margin, "WINNER BALANCE WRONG");
        assertEq(clearingHouse.getPosition(trump,rite).size, 0, "POSITION NOT DELETED");
    }

    function test_Fees_Settlement_NoWins() public {
        LimitOrder[] memory orders = new LimitOrder[](1);

        uint win = 0 ether;
        uint orderAmount = 100 ether;
        uint margin;

        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: orderAmount,
            price: .5 ether,
            bid: true,
            reduceOnly: false
        });

        changePrank(daniel);
        clearingHouse.createLimitOrders(orders);

        changePrank(rite);
        uint openNotional = clearingHouse.openPosition(trump, orderAmount, 0, false);
        margin = orderAmount - openNotional;

        changePrank(address(uma));
        clearingHouse.priceSettled(0, marketsTimestamp[trump], marketsQuestion[trump], int(win));

        uint creatorFeeBefore = clearingHouse.getStoredFees(clearingHouse.getMarketCreator(trump));
        uint protocolFeeBefore = clearingHouse.getStoredFees(owner);
        uint winnerBalBefore = usdb.balanceOf(rite);

        changePrank(daniel);
        vm.expectRevert(ClearingHouse.BET_LOST.selector);
        clearingHouse.settlePosition(trump);

        uint profit = openNotional;

        protocolFee = profit.mul(clearingHouse.getBaseSettlementFee());
        creatorFee = profit.mul(clearingHouse.getCreatorSettlementFee());

        profit -= protocolFee;
        protocolFee -= creatorFee;

        changePrank(rite);
        clearingHouse.settlePosition(trump);

        assertEq(clearingHouse.getStoredFees(clearingHouse.getMarketCreator(trump)) - creatorFeeBefore, creatorFee, "CREATOR FEE WRONG");
        assertEq(clearingHouse.getStoredFees(owner) - protocolFeeBefore, protocolFee, "PROTOCOL FEE WRONG");
        assertEq(usdb.balanceOf(rite) - winnerBalBefore, profit + margin, "WINNER BALANCE WRONG");
        assertEq(clearingHouse.getPosition(trump, rite).size, 0, "POSITION NOT DELETED");
    }

    function test_Fees_Settlement_NoOneWins() public {
        LimitOrder[] memory orders = new LimitOrder[](1);

        uint win = .5 ether;
        uint orderAmount = 100 ether;
        uint margin;

        orders[0] = LimitOrder({
            market: trump,
            maker: daniel,
            baseAmount: orderAmount,
            price: .3 ether,
            bid: false,
            reduceOnly: false
        });

        changePrank(daniel);
        clearingHouse.createLimitOrders(orders);

        changePrank(rite);
        uint openNotional = margin = clearingHouse.openPosition(trump, orderAmount, 0, true);
        uint margin2 = orderAmount - openNotional;

        changePrank(address(uma));
        clearingHouse.priceSettled(0, marketsTimestamp[trump], marketsQuestion[trump], int(win));

        uint creatorFeeBefore = clearingHouse.getStoredFees(clearingHouse.getMarketCreator(trump));
        uint protocolFeeBefore = clearingHouse.getStoredFees(owner);
        uint trader1BalBefore = usdb.balanceOf(rite);
        uint trader2BalBefore = usdb.balanceOf(daniel);

        uint profit = win.mul(orderAmount) - openNotional;

        changePrank(daniel);
        clearingHouse.settlePosition(trump);

        assertEq(usdb.balanceOf(daniel) - trader2BalBefore, margin2 - profit, "LOSER BALANCE WRONG");
        assertEq(clearingHouse.getPosition(trump,daniel).size, 0, "POSITION NOT DELETED");

        protocolFee = profit.mul(clearingHouse.getBaseSettlementFee());
        creatorFee = profit.mul(clearingHouse.getCreatorSettlementFee());

        profit -= protocolFee;
        protocolFee -= creatorFee;


        changePrank(rite);
        clearingHouse.settlePosition(trump);

        assertEq(clearingHouse.getStoredFees(clearingHouse.getMarketCreator(trump)) - creatorFeeBefore, creatorFee, "CREATOR FEE WRONG");
        assertEq(clearingHouse.getStoredFees(owner) - protocolFeeBefore, protocolFee, "PROTOCOL FEE WRONG");
        assertEq(usdb.balanceOf(rite) - trader1BalBefore, profit + margin, "WINNER BALANCE WRONG");
        assertEq(clearingHouse.getPosition(trump,rite).size, 0, "POSITION NOT DELETED");
    }

}