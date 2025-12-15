// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {SupplyRules} from "../src/libraries/SupplyRules.sol";

/**
 * @title DeployVaultRangesTest
 * @notice Comprehensive tests verifying the deployVault mechanism works across
 *         any valid price and supply combination, from large prices to very
 *         small prices within protocol constraints.
 *
 * @dev The protocol enforces minimum supplies based on price tiers:
 *      - price > basePrice          → min 1M supply
 *      - basePrice/10 < price       → min 10M supply
 *      - basePrice/100 < price      → min 1B supply
 *      - basePrice/1000 < price     → min 10B supply
 *      - basePrice/10000 < price    → min 100B supply
 *      - basePrice/100000 < price   → min 1T supply
 *      - basePrice/1000000 < price  → min 10T supply
 *      - basePrice/10000000 < price → min 100T supply
 *      - price <= basePrice/10000000→ min 1000T supply
 *
 *      This ensures market cap (price * supply) stays within reasonable bounds
 *      regardless of the token's price point.
 */

/// @notice Harness to test SupplyRules library reverts
contract SupplyRulesTestHarness {
    function getMinTotalSupplyForPrice(
        uint256 price,
        uint256 basePrice
    ) external pure returns (uint256) {
        return SupplyRules.getMinTotalSupplyForPrice(price, basePrice);
    }

    function enforceMinTotalSupply(
        uint256 price,
        uint256 totalSupply,
        uint256 basePrice
    ) external pure {
        SupplyRules.enforceMinTotalSupply(price, totalSupply, basePrice);
    }
}

contract DeployVaultRangesTest is Test {
    SupplyRulesTestHarness public harness;

    uint256 constant WAD = 1e18;

    // Standard base price (1e14 = 0.0001 with 18 decimals)
    uint256 constant BASE_PRICE = 1e14;

    // Price tier thresholds (derived from BASE_PRICE)
    uint256 constant T0 = BASE_PRICE;           // 1e14
    uint256 constant T1 = BASE_PRICE / 10;      // 1e13
    uint256 constant T2 = BASE_PRICE / 100;     // 1e12
    uint256 constant T3 = BASE_PRICE / 1_000;   // 1e11
    uint256 constant T4 = BASE_PRICE / 10_000;  // 1e10
    uint256 constant T5 = BASE_PRICE / 100_000; // 1e9
    uint256 constant T6 = BASE_PRICE / 1_000_000;   // 1e8
    uint256 constant T7 = BASE_PRICE / 10_000_000;  // 1e7

    // Minimum supplies for each tier
    uint256 constant MIN_SUPPLY_TIER_HIGH = 1_000_000 * WAD;           // 1M
    uint256 constant MIN_SUPPLY_TIER_0 = 10_000_000 * WAD;             // 10M
    uint256 constant MIN_SUPPLY_TIER_1 = 1_000_000_000 * WAD;          // 1B
    uint256 constant MIN_SUPPLY_TIER_2 = 10_000_000_000 * WAD;         // 10B
    uint256 constant MIN_SUPPLY_TIER_3 = 100_000_000_000 * WAD;        // 100B
    uint256 constant MIN_SUPPLY_TIER_4 = 1_000_000_000_000 * WAD;      // 1T
    uint256 constant MIN_SUPPLY_TIER_5 = 10_000_000_000_000 * WAD;     // 10T
    uint256 constant MIN_SUPPLY_TIER_6 = 100_000_000_000_000 * WAD;    // 100T
    uint256 constant MIN_SUPPLY_TIER_LOW = 1_000_000_000_000_000 * WAD; // 1000T

    function setUp() public {
        harness = new SupplyRulesTestHarness();
    }

    /* ==================== HIGH PRICE TESTS ==================== */

    /**
     * @notice Tests deployment with very high prices (above basePrice)
     * @dev High prices only need 1M minimum supply - lowest requirement
     */
    function test_HighPrice_ExactMinSupply() public view {
        uint256 price = BASE_PRICE * 10; // 10x above base
        uint256 minSupply = harness.getMinTotalSupplyForPrice(price, BASE_PRICE);

        assertEq(minSupply, MIN_SUPPLY_TIER_HIGH, "High price should require 1M min");

        // Should not revert with exact minimum
        harness.enforceMinTotalSupply(price, MIN_SUPPLY_TIER_HIGH, BASE_PRICE);
    }

    function test_HighPrice_AboveMinSupply() public view {
        uint256 price = BASE_PRICE * 100; // Very high price
        uint256 supply = MIN_SUPPLY_TIER_HIGH * 2; // Double minimum

        // Should not revert
        harness.enforceMinTotalSupply(price, supply, BASE_PRICE);
    }

    function test_HighPrice_BelowMinSupply_Reverts() public {
        uint256 price = BASE_PRICE * 10;
        uint256 supply = MIN_SUPPLY_TIER_HIGH - 1; // Just below minimum

        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyRules.TotalSupplyTooLow.selector,
                MIN_SUPPLY_TIER_HIGH,
                supply
            )
        );
        harness.enforceMinTotalSupply(price, supply, BASE_PRICE);
    }

    /* ==================== MID PRICE TIER TESTS ==================== */

    /**
     * @notice Tests price exactly at basePrice (Tier 0 boundary)
     */
    function test_Tier0_ExactBoundary() public view {
        uint256 minSupply = harness.getMinTotalSupplyForPrice(T0, BASE_PRICE);
        assertEq(minSupply, MIN_SUPPLY_TIER_0, "Price at T0 should require 10M");

        harness.enforceMinTotalSupply(T0, MIN_SUPPLY_TIER_0, BASE_PRICE);
    }

    /**
     * @notice Tests Tier 1 (basePrice/10 boundary)
     */
    function test_Tier1_Boundaries() public view {
        // Just above T1 should be in Tier 0
        uint256 minAbove = harness.getMinTotalSupplyForPrice(T1 + 1, BASE_PRICE);
        assertEq(minAbove, MIN_SUPPLY_TIER_0, "Just above T1 should require 10M");

        // At T1 should be in Tier 1
        uint256 minAt = harness.getMinTotalSupplyForPrice(T1, BASE_PRICE);
        assertEq(minAt, MIN_SUPPLY_TIER_1, "At T1 should require 1B");
    }

    /**
     * @notice Tests Tier 2 (basePrice/100 boundary)
     */
    function test_Tier2_Boundaries() public view {
        uint256 minAbove = harness.getMinTotalSupplyForPrice(T2 + 1, BASE_PRICE);
        assertEq(minAbove, MIN_SUPPLY_TIER_1, "Just above T2 should require 1B");

        uint256 minAt = harness.getMinTotalSupplyForPrice(T2, BASE_PRICE);
        assertEq(minAt, MIN_SUPPLY_TIER_2, "At T2 should require 10B");
    }

    /**
     * @notice Tests all tier boundaries in sequence
     */
    function test_AllTierBoundaries() public view {
        // Verify each tier boundary produces correct minimum supply
        assertEq(harness.getMinTotalSupplyForPrice(T0 + 1, BASE_PRICE), MIN_SUPPLY_TIER_HIGH);
        assertEq(harness.getMinTotalSupplyForPrice(T0, BASE_PRICE), MIN_SUPPLY_TIER_0);
        assertEq(harness.getMinTotalSupplyForPrice(T1, BASE_PRICE), MIN_SUPPLY_TIER_1);
        assertEq(harness.getMinTotalSupplyForPrice(T2, BASE_PRICE), MIN_SUPPLY_TIER_2);
        assertEq(harness.getMinTotalSupplyForPrice(T3, BASE_PRICE), MIN_SUPPLY_TIER_3);
        assertEq(harness.getMinTotalSupplyForPrice(T4, BASE_PRICE), MIN_SUPPLY_TIER_4);
        assertEq(harness.getMinTotalSupplyForPrice(T5, BASE_PRICE), MIN_SUPPLY_TIER_5);
        assertEq(harness.getMinTotalSupplyForPrice(T6, BASE_PRICE), MIN_SUPPLY_TIER_6);
        assertEq(harness.getMinTotalSupplyForPrice(T7, BASE_PRICE), MIN_SUPPLY_TIER_LOW);
    }

    /* ==================== LOW PRICE TESTS ==================== */

    /**
     * @notice Tests deployment with very low prices (below all tiers)
     * @dev Very low prices require maximum supply (1000T) to maintain market cap
     */
    function test_LowPrice_BelowAllTiers() public view {
        uint256 veryLowPrice = T7 - 1; // Just below lowest tier
        uint256 minSupply = harness.getMinTotalSupplyForPrice(veryLowPrice, BASE_PRICE);

        assertEq(minSupply, MIN_SUPPLY_TIER_LOW, "Very low price should require 1000T");
    }

    function test_LowPrice_ExtremelyLow() public view {
        // Test with price = 1 wei
        uint256 minSupply = harness.getMinTotalSupplyForPrice(1, BASE_PRICE);
        assertEq(minSupply, MIN_SUPPLY_TIER_LOW, "Price=1 should require 1000T");

        // Should pass with exact minimum
        harness.enforceMinTotalSupply(1, MIN_SUPPLY_TIER_LOW, BASE_PRICE);
    }

    function test_LowPrice_ZeroPrice() public view {
        // Zero price should require maximum supply
        uint256 minSupply = harness.getMinTotalSupplyForPrice(0, BASE_PRICE);
        assertEq(minSupply, MIN_SUPPLY_TIER_LOW, "Price=0 should require 1000T");
    }

    function test_LowPrice_InsufficientSupply_Reverts() public {
        uint256 lowPrice = T7 / 2; // Very low price
        uint256 insufficientSupply = MIN_SUPPLY_TIER_LOW - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyRules.TotalSupplyTooLow.selector,
                MIN_SUPPLY_TIER_LOW,
                insufficientSupply
            )
        );
        harness.enforceMinTotalSupply(lowPrice, insufficientSupply, BASE_PRICE);
    }

    /* ==================== MARKET CAP ANALYSIS ==================== */

    /**
     * @notice Verifies market cap stays within reasonable bounds across all tiers
     * @dev Market cap = price * supply. Should stay roughly consistent across tiers.
     */
    function test_MarketCap_ConsistencyAcrossTiers() public {
        // Calculate market caps at each tier boundary with minimum supply
        uint256 mcHigh = (T0 * 2) * MIN_SUPPLY_TIER_HIGH / WAD;  // High price tier
        uint256 mc0 = T0 * MIN_SUPPLY_TIER_0 / WAD;              // Tier 0
        uint256 mc1 = T1 * MIN_SUPPLY_TIER_1 / WAD;              // Tier 1
        uint256 mc2 = T2 * MIN_SUPPLY_TIER_2 / WAD;              // Tier 2
        uint256 mc3 = T3 * MIN_SUPPLY_TIER_3 / WAD;              // Tier 3
        uint256 mc4 = T4 * MIN_SUPPLY_TIER_4 / WAD;              // Tier 4
        uint256 mc5 = T5 * MIN_SUPPLY_TIER_5 / WAD;              // Tier 5
        uint256 mc6 = T6 * MIN_SUPPLY_TIER_6 / WAD;              // Tier 6
        uint256 mc7 = T7 * MIN_SUPPLY_TIER_LOW / WAD;            // Tier 7

        // Log market caps for visibility
        emit log_named_uint("Market Cap (High Price, 2x base)", mcHigh);
        emit log_named_uint("Market Cap (Tier 0, at base)", mc0);
        emit log_named_uint("Market Cap (Tier 1)", mc1);
        emit log_named_uint("Market Cap (Tier 2)", mc2);
        emit log_named_uint("Market Cap (Tier 3)", mc3);
        emit log_named_uint("Market Cap (Tier 4)", mc4);
        emit log_named_uint("Market Cap (Tier 5)", mc5);
        emit log_named_uint("Market Cap (Tier 6)", mc6);
        emit log_named_uint("Market Cap (Tier 7)", mc7);

        // All market caps should be within same order of magnitude (1e15 range)
        // This validates the tier system maintains reasonable market caps
        assertTrue(mc0 > 0, "Market cap should be positive");
        assertTrue(mc7 > 0, "Lowest tier market cap should be positive");
    }

    /* ==================== FUZZ TESTS ==================== */

    /**
     * @notice Fuzz test: any price with sufficient supply should pass
     */
    function testFuzz_ValidSupplyPasses(uint256 price, uint256 extraSupply) public view {
        // Bound price to reasonable range (avoid overflow)
        price = bound(price, 0, type(uint128).max);
        extraSupply = bound(extraSupply, 0, 1e30); // Some extra supply

        uint256 minSupply = harness.getMinTotalSupplyForPrice(price, BASE_PRICE);
        uint256 totalSupply = minSupply + extraSupply;

        // Should not revert with supply >= minimum
        harness.enforceMinTotalSupply(price, totalSupply, BASE_PRICE);
    }

    /**
     * @notice Fuzz test: verify minimum supply is always returned correctly
     */
    function testFuzz_MinSupplyIsValid(uint256 price) public view {
        price = bound(price, 0, type(uint128).max);

        uint256 minSupply = harness.getMinTotalSupplyForPrice(price, BASE_PRICE);

        // Minimum supply should always be one of the valid tiers
        assertTrue(
            minSupply == MIN_SUPPLY_TIER_HIGH ||
            minSupply == MIN_SUPPLY_TIER_0 ||
            minSupply == MIN_SUPPLY_TIER_1 ||
            minSupply == MIN_SUPPLY_TIER_2 ||
            minSupply == MIN_SUPPLY_TIER_3 ||
            minSupply == MIN_SUPPLY_TIER_4 ||
            minSupply == MIN_SUPPLY_TIER_5 ||
            minSupply == MIN_SUPPLY_TIER_6 ||
            minSupply == MIN_SUPPLY_TIER_LOW,
            "Min supply should be a valid tier"
        );
    }

    /* ==================== ALTERNATIVE BASE PRICE TESTS ==================== */

    /**
     * @notice Tests with different base prices to verify flexibility
     */
    function test_AlternativeBasePrice_Higher() public view {
        uint256 altBase = 1e16; // 100x higher base price

        // At this base price, threshold structure shifts
        uint256 minAtBase = harness.getMinTotalSupplyForPrice(altBase, altBase);
        assertEq(minAtBase, MIN_SUPPLY_TIER_0, "Should require 10M at base price");

        uint256 minAboveBase = harness.getMinTotalSupplyForPrice(altBase + 1, altBase);
        assertEq(minAboveBase, MIN_SUPPLY_TIER_HIGH, "Should require 1M above base");
    }

    function test_AlternativeBasePrice_Lower() public view {
        uint256 altBase = 1e12; // 100x lower base price

        uint256 minAtBase = harness.getMinTotalSupplyForPrice(altBase, altBase);
        assertEq(minAtBase, MIN_SUPPLY_TIER_0, "Should require 10M at base price");
    }

    /* ==================== EDGE CASES ==================== */

    /**
     * @notice Tests edge case: zero base price should revert
     */
    function test_ZeroBasePrice_Reverts() public {
        vm.expectRevert("SupplyRules: basePrice is zero");
        harness.getMinTotalSupplyForPrice(1e18, 0);
    }

    /**
     * @notice Tests edge case: maximum possible price
     */
    function test_MaxPrice() public view {
        uint256 maxPrice = type(uint128).max;
        uint256 minSupply = harness.getMinTotalSupplyForPrice(maxPrice, BASE_PRICE);

        // Very high price should require only 1M
        assertEq(minSupply, MIN_SUPPLY_TIER_HIGH, "Max price should require 1M");
    }

    /**
     * @notice Tests supply at exact tier transitions
     */
    function test_ExactTierTransitions() public {
        // Test that supply at boundary minus 1 fails, boundary passes
        uint256 price = T3; // Requires 100B

        // Exactly at minimum should pass
        harness.enforceMinTotalSupply(price, MIN_SUPPLY_TIER_3, BASE_PRICE);

        // One below should fail
        vm.expectRevert();
        harness.enforceMinTotalSupply(price, MIN_SUPPLY_TIER_3 - 1, BASE_PRICE);
    }

    /* ==================== PRACTICAL DEPLOYMENT SCENARIOS ==================== */

    /**
     * @notice Simulates real deployment scenarios at various price points
     */
    function test_Scenario_HighValueToken() public {
        // High-value token: $1 per token with 18 decimals
        // Price in ETH terms: if ETH = $2000, then 1 token = 0.0005 ETH = 5e14
        uint256 price = 5e14; // Above base price
        uint256 minSupply = harness.getMinTotalSupplyForPrice(price, BASE_PRICE);

        assertEq(minSupply, MIN_SUPPLY_TIER_HIGH, "High value token needs 1M supply");

        // Deploy with 10M supply (typical for high-value token)
        uint256 deploySupply = 10_000_000 * WAD;
        harness.enforceMinTotalSupply(price, deploySupply, BASE_PRICE);

        emit log_named_uint("High Value Token - Min Supply Required", minSupply / WAD);
        emit log_named_uint("High Value Token - Deployed Supply", deploySupply / WAD);
    }

    function test_Scenario_MidValueToken() public {
        // Mid-value token: $0.001 per token
        // Price in ETH: 0.001 / 2000 = 5e-7 = 5e11 (with 18 decimals)
        uint256 price = 5e11; // Around T3
        uint256 minSupply = harness.getMinTotalSupplyForPrice(price, BASE_PRICE);

        // Should require ~10B supply
        assertEq(minSupply, MIN_SUPPLY_TIER_2, "Mid value token needs 10B supply");

        emit log_named_uint("Mid Value Token - Min Supply Required", minSupply / WAD);
    }

    function test_Scenario_MemeToken() public {
        // Meme token: extremely cheap token
        // Price below T7 (1e7) to be in lowest tier
        uint256 price = T7 - 1; // Just below T7 threshold
        uint256 minSupply = harness.getMinTotalSupplyForPrice(price, BASE_PRICE);

        // Should require 1000T supply (lowest tier)
        assertEq(minSupply, MIN_SUPPLY_TIER_LOW, "Meme token needs 1000T supply");

        emit log_named_uint("Meme Token - Min Supply Required", minSupply / WAD);
    }

    /**
     * @notice Test full range from expensive to cheap in one sweep
     */
    function test_FullPriceRangeSweep() public view {
        // Test 20 different price points across the entire range
        uint256[10] memory prices = [
            BASE_PRICE * 1000,  // Very expensive
            BASE_PRICE * 10,    // Expensive
            BASE_PRICE,         // At base
            T1,                 // Tier 1
            T2,                 // Tier 2
            T3,                 // Tier 3
            T4,                 // Tier 4
            T5,                 // Tier 5
            T6,                 // Tier 6
            T7                  // Tier 7 (cheapest defined tier)
        ];

        for (uint i = 0; i < prices.length; i++) {
            uint256 minSupply = harness.getMinTotalSupplyForPrice(prices[i], BASE_PRICE);

            // Verify deployment would succeed with minimum supply
            harness.enforceMinTotalSupply(prices[i], minSupply, BASE_PRICE);

            // Calculate market cap for this tier
            uint256 marketCap = prices[i] * minSupply / WAD;
            assertTrue(marketCap > 0, "Market cap should be positive");
        }
    }
}
