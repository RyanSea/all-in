// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../AllInTestSetup.sol";

contract Base_PruneIDTest is AllInTestSetup {

    function test_PruneID_PruneFromFront() public view {
        uint256[] memory ids = new uint256[](4);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        ids[3] = 4;

        ids = clearingHouse.pruneID(ids, 1);

        assertEq(ids.length, 3);
        assertEq(ids[0], 2);
        assertEq(ids[1], 3);
        assertEq(ids[2], 4);
    }

    function test_PruneID_PruneFromMiddle() public view {
        uint256[] memory ids = new uint256[](4);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        ids[3] = 4;

        ids = clearingHouse.pruneID(ids, 2);

        assertEq(ids.length, 3);
        assertEq(ids[0], 1);
        assertEq(ids[1], 3);
        assertEq(ids[2], 4);
    }

    function test_PruneID_PruneFromBack() public view {
        uint256[] memory ids = new uint256[](4);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        ids[3] = 4;

        ids = clearingHouse.pruneID(ids, 4);

        assertEq(ids.length, 3);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
        assertEq(ids[2], 3);
    }

    function test_PruneID_PruneFromSingleArray() public view {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        ids = clearingHouse.pruneID(ids, 1);

        assertEq(ids.length, 0);
    }

    function test_PruneID_Noop_Empty() public view {
        uint256[] memory ids = new uint256[](0);

        ids = clearingHouse.pruneID(ids, 2);

        assertEq(ids.length, 0);
    }

    function test_PruneID_Noop_Full() public view {
        uint256[] memory ids = new uint256[](4);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        ids[3] = 4;

        ids = clearingHouse.pruneID(ids, 5);

        assertEq(ids.length, 4);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
        assertEq(ids[2], 3);
        assertEq(ids[3], 4);
    }
}