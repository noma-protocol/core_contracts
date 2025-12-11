// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library SupplyRules {
    uint256 internal constant WAD = 1e18; // 18 decimals

    // Custom error for clearer debugging
    error TotalSupplyTooLow(uint256 minRequired, uint256 provided);

    /// @notice Returns the minimum total supply required for a given price.
    /// @param price Token price with 18 decimals.
    /// @param basePrice The largest price threshold from which all tiers are derived.
    ///                  Example: 1e14 now, maybe 1e9 later, etc.
    function getMinTotalSupplyForPrice(
        uint256 price,
        uint256 basePrice
    ) internal pure returns (uint256) {
        // Defensive: don't allow basePrice == 0 (would break divisions).
        if (basePrice == 0) {
            // You can choose to revert or just return 0.
            // I prefer reverting to avoid silently disabling the rule.
            revert("SupplyRules: basePrice is zero");
        }

        // Derive the thresholds by dividing by 10 each time.
        // NOTE: if basePrice is very small, some divisions may become 0.
        // You can add extra guards if needed.
        uint256 t0 = basePrice;          // was 1e14
        uint256 t1 = basePrice / 10;     // was 1e13
        uint256 t2 = basePrice / 100;    // was 1e12
        uint256 t3 = basePrice / 1_000;  // was 1e11
        uint256 t4 = basePrice / 10_000; // was 1e10
        uint256 t5 = basePrice / 100_000;       // was 1e9
        uint256 t6 = basePrice / 1_000_000;     // was 1e8
        uint256 t7 = basePrice / 10_000_000;    // was 1e7

        // Same logic as your original, but using derived thresholds.
        if (price > t0) {
            // price > top threshold  -> 1M
            return 1_000_000 * WAD;
        }
        // t1 < price <= t0 -> 10M
        else if (price > t1) {
            return 10_000_000 * WAD;
        }
        // t2 < price <= t1 -> 1B
        else if (price > t2) {
            return 1_000_000_000 * WAD;
        }
        // t3 < price <= t2 -> 10B
        else if (price > t3) {
            return 10_000_000_000 * WAD;
        }
        // t4 < price <= t3 -> 100B
        else if (price > t4) {
            return 100_000_000_000 * WAD;
        }
        // t5 < price <= t4 -> 1T
        else if (price > t5) {
            return 1_000_000_000_000 * WAD;
        }
        // t6 < price <= t5 -> 10T
        else if (price > t6) {
            return 10_000_000_000_000 * WAD;
        }
        // t7 < price <= t6 -> 100T
        else if (price > t7) {
            return 100_000_000_000_000 * WAD;
        }
        // price <= t7 -> 1000T
        else {
            return 1_000_000_000_000_000 * WAD;
        }
    }

    /// @notice Enforces that totalSupply is at least the minimum for the given price,
    ///         using a configurable basePrice ladder.
    function enforceMinTotalSupply(
        uint256 price,
        uint256 totalSupply,
        uint256 basePrice // e.g. 1e14
    ) internal pure {
        uint256 minSupply = getMinTotalSupplyForPrice(price, basePrice);
        if (totalSupply < minSupply) {
            revert TotalSupplyTooLow(minSupply, totalSupply);
        }
    }
}
