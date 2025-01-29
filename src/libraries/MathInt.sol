// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title SafeMathInt
 * @dev Math operations for int256 with overflow safety checks.
 */
library MathInt {

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