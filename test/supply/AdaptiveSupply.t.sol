// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/controllers/supply/AdaptiveSupply.sol";
import "../../src/libraries/ScalingAlgorithms.sol";

/**
 * @title MockModelHelper
 * @dev A mock implementation of the IModelHelper interface for testing purposes.
 */
contract MockModelHelper is IModelHelper {
    /**
     * @notice Retrieves the circulating supply for a given pool and vault.
     * @param pool The address of the pool.
     * @param vault The address of the vault.
     * @return The circulating supply as a uint256 value.
     */
    function getCirculatingSupply(address pool, address vault) public view override returns (uint256) {
        return _getCirculatingSupply(pool, vault);
    }

    /**
     * @notice Retrieves the total supply for a given pool.
     * @param pool The address of the pool.
     * @param flag A boolean flag for additional calculation logic.
     * @return The total supply as a uint256 value.
     */
    function getTotalSupply(address pool, bool flag) public view override returns (uint256) {
        return _getTotalSupply(pool, flag);
    }

    /**
     * @dev Internal function to simulate total supply retrieval.
     * @param pool The address of the pool.
     * @param flag A boolean flag for additional calculation logic.
     * @return A fixed total supply of 1,000,000 tokens (for testing purposes).
     */
    function _getTotalSupply(address pool, bool flag) internal view returns (uint256) {
        uint256 baseSupply = 1_000_000e18;
        uint256 randomFactor = _random();
        return baseSupply + (baseSupply * randomFactor / 100); // Slightly vary total supply
    }

    /**
     * @dev Internal function to simulate circulating supply retrieval.
     * @param pool The address of the pool.
     * @param vault The address of the vault.
     * @return A pseudo-random circulating supply based on the total supply.
     */
    function _getCirculatingSupply(address pool, address vault) internal view returns (uint256) {
        uint256 totalSupply = _getTotalSupply(pool, true);
        uint256 randomFactor = _random();

        uint256 circulatingSupply = totalSupply * (100 - randomFactor) / 100;

        return circulatingSupply;
    }

    /**
     * @dev Generates a pseudo-random number between 0 and 19.
     * @return A pseudo-random uint256 value.
     */
    function _random() private view returns (uint256) {
        uint256 randomHash = uint256(keccak256(
            abi.encodePacked(block.prevrandao, block.timestamp)
        ));
        return randomHash % 20; // Random number between 0 and 19
    }
}

contract AdaptiveSupplyTest is Test {
    AdaptiveSupply adaptiveSupply;
    MockModelHelper mockModelHelper;

    uint256[4] thresholds = [
        uint256(6e17), // Low Volatility
        uint256(1e18), // Medium Volatility
        uint256(2e18), // High Volatility
        uint256(3e18)  // Extreme Volatility
    ];

    function setUp() public {
        mockModelHelper = new MockModelHelper();
        adaptiveSupply = new AdaptiveSupply(address(mockModelHelper), thresholds);
    }

    function testGetMarketConditions() public {
        // Test Low Volatility
        assertEq(
            uint256(adaptiveSupply.getMarketConditions(4e17)),
            uint256(AdaptiveSupply.MarketConditions.LowVolatility),
            "Should be Low Volatility"
        );

        // Test Medium Volatility
        assertEq(
            uint256(adaptiveSupply.getMarketConditions(6e17)),
            uint256(AdaptiveSupply.MarketConditions.MediumVolatility),
            "Should be Medium Volatility"
        );

        // Test High Volatility
        assertEq(
            uint256(adaptiveSupply.getMarketConditions(1e18)),
            uint256(AdaptiveSupply.MarketConditions.HighVolatility),
            "Should be High Volatility"
        );

        // Test Extreme Volatility
        assertEq(
            uint256(adaptiveSupply.getMarketConditions(3e18)),
            uint256(AdaptiveSupply.MarketConditions.ExtremeVolatility),
            "Should be Extreme Volatility"
        );
    }

    function testAdjustSupplyLowVolatility() public {
        int256 volatility = int256(4e17); // 40%
        (uint256 mintAmount, uint256 burnAmount) = adaptiveSupply.adjustSupply(
            address(0),
            address(0),
            volatility
        );

        uint256 totalSupply = mockModelHelper.getTotalSupply(address(0), true);
        uint256 circulatingSupply = mockModelHelper.getCirculatingSupply(address(0), address(0));
        uint256 deltaSupply = totalSupply - circulatingSupply;

        // Harmonic update for low volatility
        uint256 expectedMint = ScalingAlgorithms.harmonicUpdate(deltaSupply, volatility, 1, false);
        uint256 expectedBurn = ScalingAlgorithms.harmonicUpdate(deltaSupply, volatility, 1, true);
        
        console.log("Total supply: ", totalSupply);
        console.log("Expected Mint: ", expectedMint);
        console.log("Expected Burn: ", expectedBurn);

        assertEq(mintAmount, expectedMint, "Mint amount mismatch for Low Volatility");
        assertEq(burnAmount, expectedBurn, "Burn amount mismatch for Low Volatility");
    }

    function testAdjustSupplyMediumVolatility() public {
        int256 volatility = int256(6e17); // 60%
        (uint256 mintAmount, uint256 burnAmount) = adaptiveSupply.adjustSupply(
            address(0),
            address(0),
            volatility
        );

        uint256 totalSupply = mockModelHelper.getTotalSupply(address(0), true);
        uint256 circulatingSupply = mockModelHelper.getCirculatingSupply(address(0), address(0));
        uint256 deltaSupply = totalSupply - circulatingSupply;

        // Harmonic update for medium volatility
        uint256 expectedMint = ScalingAlgorithms.harmonicUpdate(deltaSupply, volatility, 10, false);
        uint256 expectedBurn = ScalingAlgorithms.harmonicUpdate(deltaSupply, volatility, 10, true);

        console.log("Total supply: ", totalSupply);
        console.log("Expected Mint: ", expectedMint);
        console.log("Expected Burn: ", expectedBurn);

        assertEq(mintAmount, expectedMint, "Mint amount mismatch for Medium Volatility");
        assertEq(burnAmount, expectedBurn, "Burn amount mismatch for Medium Volatility");
    }

    function testAdjustSupplyHighVolatility() public {
        int256 volatility = int256(1e18); // 100%
        (uint256 mintAmount, uint256 burnAmount) = adaptiveSupply.adjustSupply(
            address(0),
            address(0),
            volatility
        );

        uint256 totalSupply = mockModelHelper.getTotalSupply(address(0), true);
        uint256 circulatingSupply = mockModelHelper.getCirculatingSupply(address(0), address(0));
        uint256 deltaSupply = totalSupply - circulatingSupply;

        // Quadratic update for high volatility
        uint256 expectedMint = ScalingAlgorithms.boundedQuadraticUpdate(deltaSupply, volatility, true);
        uint256 expectedBurn = ScalingAlgorithms.boundedQuadraticUpdate(deltaSupply, volatility, false);

        console.log("Total supply: ", totalSupply);
        console.log("Expected Mint: ", expectedMint);
        console.log("Expected Burn: ", expectedBurn);

        assertEq(mintAmount, expectedMint, "Mint amount mismatch for High Volatility");
        assertEq(burnAmount, expectedBurn, "Burn amount mismatch for High Volatility");
    }

    function testAdjustSupplyExtremeVolatility() public {
        int256 volatility = int256(3e18); // 300%
        (uint256 mintAmount, uint256 burnAmount) = adaptiveSupply.adjustSupply(
            address(0),
            address(0),
            volatility
        );

        uint256 totalSupply = mockModelHelper.getTotalSupply(address(0), true);
        uint256 circulatingSupply = mockModelHelper.getCirculatingSupply(address(0), address(0));
        uint256 deltaSupply = totalSupply - circulatingSupply;

        // Exponential update for extreme volatility
        uint256 expectedMint = ScalingAlgorithms.polynomialUpdate(deltaSupply, 1, true);
        uint256 expectedBurn = ScalingAlgorithms.polynomialUpdate(deltaSupply, 1, false);

        console.log("Total supply: ", totalSupply);
        console.log("Expected Mint: ", expectedMint);
        console.log("Expected Burn: ", expectedMint);

        assertEq(mintAmount, expectedMint, "Mint amount mismatch for Extreme Volatility");
        assertEq(burnAmount, expectedBurn, "Burn amount mismatch for Extreme Volatility");
    }

    function testSetVolatilityThresholds() public {
        uint256[4] memory newThresholds = [
            uint256(6e17), // Updated Low Volatility
            uint256(1e18), // Updated Medium Volatility
            uint256(2e18), // Updated High Volatility
            uint256(3e18)  // Updated Extreme Volatility
        ];

        adaptiveSupply.setVolatilityThresholds(newThresholds);

        for (uint256 i = 0; i < 4; i++) {
            assertEq(adaptiveSupply.volatilityThresholds(i), newThresholds[i], "Threshold mismatch");
        }
    }
}
