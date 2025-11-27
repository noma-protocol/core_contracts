// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library SupplyRules {
    uint256 internal constant WAD = 1e18; // 18 decimals

    // Custom error for clearer debugging
    error TotalSupplyTooLow(uint256 minRequired, uint256 provided);

    /// @notice Returns the minimum total supply required for a given price.
    /// @param price Token price with 18 decimals (e.g. 0.0001 * 1e18 = 1e14).
    function getMinTotalSupplyForPrice(uint256 price) internal pure returns (uint256) {
        // price > 0.0001           -> no minimum
        if (price > 1e14) {
            return 1_000_000 * WAD;
        }
        // 0.00001 < price <= 0.0001 -> 10M
        else if (price > 1e13) {
            return 10_000_000 * WAD;
        }
        // 0.000001 < price <= 0.00001 -> 1B
        else if (price > 1e12) {
            return 1_000_000_000 * WAD;
        }
        // 0.0000001 < price <= 0.000001 -> 10B
        else if (price > 1e11) {
            return 10_000_000_000 * WAD;
        }
        // 0.00000001 < price <= 0.0000001 -> 100B
        else if (price > 1e10) {
            return 100_000_000_000 * WAD;
        }
        // 0.000000001 < price <= 0.00000001 -> 1T
        else if (price > 1e9) {
            return 1_000_000_000_000 * WAD;
        }
        // 0.0000000001 < price <= 0.000000001 -> 10T
        else if (price > 1e8) {
            return 10_000_000_000_000 * WAD;
        }
        // 0.00000000001 < price <= 0.0000000001 -> 100T
        else if (price > 1e7) {
            return 100_000_000_000_000 * WAD;
        }
        // price <= 0.00000000001 -> 1000T
        else {
            return 1_000_000_000_000_000 * WAD;
        }
    }

    /// @notice Enforces that totalSupply is at least the minimum for the given price.
    /// @dev Reverts if totalSupply is too low.
    function enforceMinTotalSupply(uint256 price, uint256 totalSupply) internal pure {
        uint256 minSupply = getMinTotalSupplyForPrice(price);
        if (totalSupply < minSupply) {
            revert TotalSupplyTooLow(minSupply, totalSupply);
        }
    }
    
}
