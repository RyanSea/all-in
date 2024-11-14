// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";

/// @title AllInMath
/// @dev wrapper library for Solady's FixedPointMathLib
library AllInMath {
    using FixedPointMathLib for *;
    using SafeCastLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                UNSIGNED
    //////////////////////////////////////////////////////////////*/

    function mul(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.fullMulDiv(y, 1e18);
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.fullMulDiv(1e18, y);
    }

    function sqrtF(uint256 x) internal pure returns (uint256) {
        return (x * 1e18).sqrt();
    }

    function dist(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.toInt256().dist(y.toInt256());
    }

    /*///////////////////////////////////////////////////////////////
                                  SIGNED
    //////////////////////////////////////////////////////////////*/

    function mul(int256 x, int256 y) internal pure returns (int256 result) {
        bool x_neg = x < 0;
        bool y_neg = y < 0;
        bool negative = x_neg != y_neg;

        if (x_neg) x = -x;
        if (y_neg) y = -y;

        result = uint256(x).fullMulDiv(uint256(y), 1e18).toInt256();

        if (negative) return -result;
    }

    function div(int256 x, int256 y) internal pure returns (int256 result) {
        bool x_neg = x < 0;
        bool y_neg = y < 0;
        bool negative = x_neg != y_neg;

        if (x_neg) x = -x;
        if (y_neg) y = -y;

        result = uint256(x).fullMulDiv(1e18, uint256(y)).toInt256();

        if (negative) return -result;
    }

    function sqrtF(int256 x) internal pure returns (int256) {
        if (x < 0) x = -x;

        return uint256(x * 1e18).sqrt().toInt256();
    }

    /*///////////////////////////////////////////////////////////////
                                 MIXED
    //////////////////////////////////////////////////////////////*/

    function mul(int256 x, uint256 y) internal pure returns (int256 result) {
        bool negative = x < 0;

        if (negative) x = -x;

        result = uint256(x).fullMulDiv(y, 1e18).toInt256();

        if (negative) return -result;
    }

    function mul(uint256 x, int256 y) internal pure returns (int256 result) {
        bool negative = y < 0;

        if (negative) y = -y;

        result = uint256(x).fullMulDiv(uint256(y), 1e18).toInt256();

        if (negative) return -result;
    }

    function div(int256 x, uint256 y) internal pure returns (int256 result) {
        bool negative = x < 0;

        if (negative) x = -x;

        result = uint256(x).fullMulDiv(1e18, y).toInt256();

        if (negative) return -result;
    }

    function div(uint256 x, int256 y) internal pure returns (int256 result) {
        bool negative = y < 0;

        if (negative) y = -y;

        result = x.fullMulDiv(1e18, uint256(y)).toInt256();

        if (negative) return -result;
    }
}
