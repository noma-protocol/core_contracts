// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title TickMathExtra
/// @notice Utilities for snapping ticks to spacing with correct negative division semantics.
library TickMathExtra {
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK =  887272;

    error InvalidTickSpacing();

    /// @notice Floor to multiple of spacing (<= tick)
    function floorToSpacing(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        if (tickSpacing <= 0) revert InvalidTickSpacing();
        int24 r = tick % tickSpacing; // remainder keeps sign of tick in Solidity
        return r >= 0 ? tick - r : tick - (r + tickSpacing);
    }

    /// @notice Ceil to multiple of spacing (>= tick)
    function ceilToSpacing(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        if (tickSpacing <= 0) revert InvalidTickSpacing();
        int24 r = tick % tickSpacing;
        if (r == 0) return tick;
        return r > 0 ? tick + (tickSpacing - r) : (tick - r);
    }

    /// @notice Bounds for a given spacing (inclusive)
    function boundsForSpacing(int24 tickSpacing) internal pure returns (int24 minTick, int24 maxTick) {
        if (tickSpacing <= 0) revert InvalidTickSpacing();
        // For MIN_TICK (negative), do a true floor:
        int24 rMin = MIN_TICK % tickSpacing;
        minTick = rMin == 0 ? MIN_TICK : MIN_TICK - (rMin + tickSpacing);
        // For MAX_TICK (positive), truncation is already floor:
        maxTick = MAX_TICK - (MAX_TICK % tickSpacing);
    }

    /// @notice Snap to the closest usable tick for `tickSpacing`, clamped to bounds.
    /// @dev Ties (exactly halfway) round toward the lower tick.
    function nearestUsableTick(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        (int24 minTick, int24 maxTick) = boundsForSpacing(tickSpacing);

        // First get the two neighbors
        int24 lower = floorToSpacing(tick, tickSpacing);
        int24 upper = lower + tickSpacing;

        // Choose nearest (ties -> lower)
        int256 dLower = int256(tick) - int256(lower);
        int256 dUpper = int256(upper) - int256(tick);
        int24 snapped = dLower <= dUpper ? lower : upper;

        // Clamp to bounds
        if (snapped < minTick) return minTick;
        if (snapped > maxTick) return maxTick;
        return snapped;
    }
}
