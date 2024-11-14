// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./AllInTestSetup.sol";
import { Ownable } from "solady/auth/Ownable.sol";

/// @dev tests admin functionality
contract AdminTest is AllInTestSetup {
    using AllInMath for *;

    function test_Admin_AdminRole() public {
        
    }
    
    function test_Admin_SetTakerFees() public {
        uint baseFee = .002 ether; // 0.2%
        uint creatorFee = .5 ether ; // 50%
        uint makerFee = .5 ether; // 50%
        uint keeperFee = .0001 ether; // 0.01%

        vm.prank(rite); //
        vm.expectRevert(Ownable.Unauthorized.selector); // note: access controlled 
        clearingHouse.setTakerFees({
            baseFee: baseFee,
            creatorFee: creatorFee,
            makerFee: makerFee,
            keeperFee: keeperFee
        });

        vm.prank(owner);
        clearingHouse.grantAdmin(rite);

        vm.startPrank(rite);
        vm.expectRevert(ClearingHouse.INVALID_FEE.selector); // note: creator & maker must sum to 1 or less
        clearingHouse.setTakerFees({
            baseFee: baseFee,
            creatorFee: .6 ether,
            makerFee: .5 ether,
            keeperFee: keeperFee
        });

        clearingHouse.setTakerFees({
            baseFee: baseFee,
            creatorFee: creatorFee,
            makerFee: makerFee,
            keeperFee: keeperFee
        });

        assertEq(clearingHouse.getBaseTakerFee(), baseFee, "BASE FEE INCORRECT");
        assertEq(clearingHouse.getCreatorTakerFee(), baseFee.mul(creatorFee), "CREATOR FEE INCORRECT"); // note: creator fee is a percentage of the base fee
        assertEq(clearingHouse.getMakerFee(), baseFee.mul(makerFee), "MAKER FEE INCORRECT"); // note: maker fee is a percentage of the base fee
        assertEq(clearingHouse.getKeeperFee(), keeperFee, "KEEPER FEE INCORRECT");
    }

    function test_Admin_SetSettlementFees() public {
        uint baseFee = .02 ether ; // 2%
        uint creatorFee = 1 ether ; // 100%

        vm.prank(rite);
        vm.expectRevert(Ownable.Unauthorized.selector); // note: access controlled
        clearingHouse.setSettlementFees({
            baseFee: baseFee,
            creatorFee: creatorFee
        });

        vm.prank(owner);
        clearingHouse.grantAdmin(rite);

        vm.startPrank(rite);
        vm.expectRevert(ClearingHouse.INVALID_FEE.selector); // note: creator fee must 1 or less
        clearingHouse.setSettlementFees({
            baseFee: baseFee,
            creatorFee: 1 ether + 1
        });

        clearingHouse.setSettlementFees({
            baseFee: baseFee,
            creatorFee: creatorFee
        });

        assertEq(clearingHouse.getBaseSettlementFee(), baseFee, "BASE FEE INCORRECT");
        assertEq(clearingHouse.getCreatorSettlementFee(), baseFee.mul(creatorFee), "CREATOR FEE INCORRECT"); // note: creator fee is a percentage of the base fee
    }
}