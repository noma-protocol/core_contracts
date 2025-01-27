// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title SafeMathInt
 * @dev Math operations for int256 with overflow safety checks.
 */
library SafeMathInt {
    int256 private constant MIN_INT256 = int256(1) << 255;
    int256 private constant MAX_INT256 = ~(int256(1) << 255);

    /**
     * @dev Multiplies two int256 variables and fails on overflow.
     */
    function mul(int256 a, int256 b)
        internal
        pure
        returns (int256)
    {
        int256 c = a * b;

        // Detect overflow when multiplying MIN_INT256 with -1
        require(c != MIN_INT256 || (a & MIN_INT256) != (b & MIN_INT256));
        require((b == 0) || (c / b == a));
        return c;
    }

    /**
     * @dev Division of two int256 variables and fails on overflow.
     */
    function div(int256 a, int256 b)
        internal
        pure
        returns (int256)
    {
        // Prevent overflow when dividing MIN_INT256 by -1
        require(b != -1 || a != MIN_INT256);

        // Solidity already throws when dividing by 0.
        return a / b;
    }

    /**
     * @dev Subtracts two int256 variables and fails on overflow.
     */
    function sub(int256 a, int256 b)
        internal
        pure
        returns (int256)
    {
        int256 c = a - b;
        require((b >= 0 && c <= a) || (b < 0 && c > a));
        return c;
    }

    /**
     * @dev Adds two int256 variables and fails on overflow.
     */
    function add(int256 a, int256 b)
        internal
        pure
        returns (int256)
    {
        int256 c = a + b;
        require((b >= 0 && c >= a) || (b < 0 && c < a));
        return c;
    }

    /**
     * @dev Converts to absolute value, and fails on overflow.
     */
    function abs(int256 a)
        internal
        pure
        returns (int256)
    {
        require(a != MIN_INT256);
        return a < 0 ? -a : a;
    }

    /**
     * @dev Computes e^x, where x is a signed 18-decimal fixed-point number.
     */
    function expWad(int256 x) internal pure returns (uint256) {
        unchecked {
            require(x < 135305999368893231589, "expWad: Overflow"); // Overflow for e^x when x >= 135.305999368893231589
            if (x < -42139678854452767551) return 0; // Underflow for e^x when x <= -42.139678854452767551

            // Convert x from 18-decimal fixed-point to a regular integer
            int256 k = ((x << 78) / 5e17 + (1 << 77)) >> 78;
            x -= k * 5e17;

            int256 y = x + 1e18;
            int256 z = (x * x) / 2e18;
            y += z;

            z = (z * x) / 3e18;
            y += z;

            z = (z * x) / 4e18;
            y += z;

            z = (z * x) / 5e18;
            y += z;

            z = (z * x) / 6e18;
            y += z;

            z = (z * x) / 7e18;
            y += z;

            z = (z * x) / 8e18;
            y += z;

            z = (z * x) / 9e18;
            y += z;

            z = (z * x) / 10e18;
            y += z;

            if (k >= 0) return uint256(y) << uint256(k);
            return uint256(y) >> uint256(-k);
        }
    }       
}