// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "src/utils/AllInStructs.sol";
import "src/utils/AllInMath.sol";
import "solady/utils/FixedPointMathLib.sol";

import { LibString } from "solady/utils/LibString.sol";

import { EnumerableSetLib } from "solady/utils/EnumerableSetLib.sol";

import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

import { ClearingHouse } from "src/ClearingHouse.sol";
import { MatchingEngine } from "src/MatchingEngine.sol";
import { OrderCreator} from "src/OrderCreator.sol";

import { MockClearingHouse } from "./mock/MockClearingHouse.sol";
import { USDB } from "./mock/USDB.sol";
import { UMA } from "./mock/UMA.sol";

contract AllInTestSetup is Test {
    using EnumerableSetLib for EnumerableSetLib.AddressSet;
    using FixedPointMathLib for int256;
    using AllInMath for *;

    ERC1967Factory internal factory;

    MockClearingHouse internal clearingHouse;
    address internal clearingHouse_logic;
    address internal matchingEngine_logic;
    address internal orderCreator_logic;

    address whale = 0x0301079DaBdC9A2c70b856B2C51ACa02bAc10c3a;
    UMA uma;
    USDB usdb;

    uint160 internal trump;
    uint160 internal sport;
    
    address internal owner = makeAddr('owner');

    address internal rite = makeAddr('rite');
    address internal daniel = makeAddr('13');
    address internal aster = makeAddr('aster');
    address internal joe = makeAddr('joe');
    address internal lazlow = makeAddr('lazlow');
    address internal solace = makeAddr('solace');
    address internal jd = makeAddr('jd');

    address[] internal traders;

    uint256 minPrice = .001 ether;
    uint256 maxPrice = 1 ether - minPrice;
    int24 internal constant minTick = -92109;
    int24 internal constant maxTick = -2;

    mapping(uint160 market => bytes question) internal marketsQuestion;
    mapping(uint160 market => uint256 timestamp) internal marketsTimestamp;

    function setUp() public virtual {
        usdb = new USDB();
        uma = new UMA();

        factory = new ERC1967Factory();

        _createCore();

        _mintAndApprove();
        _label();

        trump = _createMarket("Will Trump win the election", "MAGA");
        sport = _createMarket("Will the sports ball team win the bowl", "Sports etc");
    }

    function _createCore() internal {
        // sidecars & proxy
        matchingEngine_logic = address(new MatchingEngine(address(usdb)));
        orderCreator_logic = address(new OrderCreator(address(usdb)));
        clearingHouse_logic = address(new MockClearingHouse({
            oracle_ : address(uma),
            matchingEngine_: matchingEngine_logic,
            orderCreator_: orderCreator_logic,
            usdb_: address(usdb)
        }));

        // core
        clearingHouse = MockClearingHouse(factory.deploy({
            implementation: clearingHouse_logic,
            admin : owner
        }));

        clearingHouse.initialize({
            owner_: owner,
            tickSize: .0001 ether,
            proposalLiveness: 2 hours,
            reward: 5 ether
        });

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
        vm.stopPrank();
    }

    function _createMarket(string memory title, string memory description) internal returns (uint160 id) {
        LimitOrder[] memory orders = new LimitOrder[](0);

        vm.prank(jd);
        (id, ) = clearingHouse.createMarket({
            title: bytes(title),
            description: bytes(description),
            orders: orders,
            resolver: address(0)
        });

        marketsQuestion[id] = _getData(bytes(title), bytes(description), id);
        marketsTimestamp[id] = block.timestamp;
    }

    function _getData(
        bytes memory title,
        bytes memory description,
        uint160 market
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
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
    }

    function _label() internal {
        vm.label(rite, "Rite");
        vm.label(daniel, "Daniel");
        vm.label(aster, "Aster");
        vm.label(joe, "Joe");
        vm.label(lazlow, "Lazlow");
        vm.label(solace, "Solace");
        vm.label(jd, "JD");

        vm.label(address(usdb), "USDB");
        vm.label(address(clearingHouse), "ClearingHouse");
        vm.label(clearingHouse_logic, "ClearingHouse");
        vm.label(matchingEngine_logic, "MatchingEngine");
        vm.label(orderCreator_logic, "OrderCreator");
    }

    function _mintAndApprove() internal {
        usdb.mint(whale, 10_000_000 ether);

        vm.startPrank(whale);
        usdb.transfer(owner, 100_000 ether);
        usdb.transfer(rite, 100_000 ether);
        usdb.transfer(daniel, 100_000 ether);
        usdb.transfer(aster, 100_000 ether);
        usdb.transfer(joe, 100_000 ether);
        usdb.transfer(lazlow, 100_000 ether);
        usdb.transfer(solace, 100_000 ether);
        usdb.transfer(jd, 100_000 ether);
        vm.stopPrank();

        vm.prank(rite);
        usdb.approve(address(clearingHouse), type(uint256).max);
        vm.prank(daniel);
        usdb.approve(address(clearingHouse), type(uint256).max);
        vm.prank(aster);
        usdb.approve(address(clearingHouse), type(uint256).max);
        vm.prank(joe);
        usdb.approve(address(clearingHouse), type(uint256).max);
        vm.prank(lazlow);
        usdb.approve(address(clearingHouse), type(uint256).max);
        vm.prank(solace);
        usdb.approve(address(clearingHouse), type(uint256).max);
        vm.prank(jd);
        usdb.approve(address(clearingHouse), type(uint256).max);

        traders.push(rite);
        traders.push(daniel);
        traders.push(aster);
        traders.push(joe);
        traders.push(lazlow);
        traders.push(solace);
        traders.push(jd);
    }

    function changePrank(address user) internal override {
        vm.stopPrank();
        vm.startPrank(user);
    }

    function _checkTickInitialized(LimitOrder memory order, bool init) internal view {
        assertEq(
            clearingHouse.isTickInitialized({
                market: order.market,
                tick: clearingHouse.getPriceToTick(order.price),
                lte: order.bid
            }), init
        , "INCORRECT TICK INITIALIZATION");
    }

    function _checkOrdersOnTickAmount(uint160 market, uint price, uint length) internal view {
        assertEq(
            clearingHouse.getOrdersOnTick({
                market: market,
                tick: clearingHouse.getPriceToTick(price)
            }).length
        , length, "INCORRECT NUMBER OF ORDERS ON TICK");
    }

    function _createLimitOrder(
        address maker, 
        uint price, 
        uint amount,
        bool bid
    ) internal returns (LimitOrder memory order) {
        LimitOrder[] memory orders = new LimitOrder[](1);

        order = orders[0] = LimitOrder({
            market: trump,
            maker: maker,
            baseAmount: amount,
            price: price,
            bid: bid,
            reduceOnly: false
        });

        changePrank(maker);
        clearingHouse.createLimitOrders(orders);
    }

    function _checkOrdersOnTick(uint160 market, uint price, uint256[] memory idsExpected) internal view {
        _checkOrdersOnTickAmount(market, price, idsExpected.length);

        uint[] memory storedIds = clearingHouse.getOrdersOnTick({
            market: market,
            tick: clearingHouse.getPriceToTick(price)
        });

        for (uint i; i < idsExpected.length; ++i) {
            assertEq(idsExpected[i], storedIds[i], "INCORRECT ORDER ID ON TICK");
        }
    }

    function _checkOrdersInStorage(uint[] memory ids, LimitOrder[] memory orders) internal view {
        assertEq(ids.length, orders.length, "INCORRECT NUMBER OF ORDER IDS");

        LimitOrder memory order;
        LimitOrder memory storedOrder;
        for (uint i; i < ids.length; ++i) {
            order = orders[i];
            storedOrder = clearingHouse.getLimitOrder(ids[i]);

            assertEq(storedOrder.baseAmount, order.baseAmount, "INCORRECT BASE AMOUNT");
            assertEq(storedOrder.price, order.price, "INCORRECT PRICE");
            assertEq(storedOrder.bid, order.bid, "INCORRECT SIDE");
            assertEq(storedOrder.reduceOnly, order.reduceOnly, "INCORRECT REDUCE ONLY");
            assertEq(storedOrder.maker, order.maker, "INCORRECT MAKER");
            assertEq(storedOrder.market, order.market, "INCORRECT MARKET");
        }
    }

    function _getOrderMarginRequired(LimitOrder memory order) internal view returns (uint256) {
        return clearingHouse.getOrderMarginRequired({
            baseAmount: order.baseAmount,
            price: order.price,
            bid: order.bid
        });
    }

    function _getTakerMarginRequired(
        uint256 openNotional,
        int256 size
    ) internal pure returns (uint256) {
        return size > 0 ? openNotional : size.abs() - openNotional;
    }
}