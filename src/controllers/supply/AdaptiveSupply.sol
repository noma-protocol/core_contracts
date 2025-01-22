// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ScalingAlgorithms.sol";

/// @title Adaptive Supply Contract
/// @notice This contract manages the dynamic supply adjustment of tokens based on market volatility.
/// @dev Integrates with external scaling algorithms to calculate supply adjustments.
interface IModelHelper {
    /// @notice Retrieves the circulating supply for a given pool and vault.
    /// @param pool The address of the Uniswap pool.
    /// @param vault The address of the vault.
    /// @return The circulating supply as a uint256 value.
    function getCirculatingSupply(address pool, address vault) external view returns (uint256);

    /// @notice Retrieves the total supply for a given pool.
    /// @param pool The address of the Uniswap pool.
    /// @param flag A boolean flag for additional calculation logic.
    /// @return The total supply as a uint256 value.
    function getTotalSupply(address pool, bool flag) external view returns (uint256);
}

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
    function getTotalSupply(address pool, bool flag) public pure override returns (uint256) {
        return _getTotalSupply(pool, flag);
    }

    /**
     * @dev Internal function to simulate total supply retrieval.
     * @param pool The address of the pool.
     * @param flag A boolean flag for additional calculation logic.
     * @return A fixed total supply of 1,000,000 tokens (for testing purposes).
     */
    function _getTotalSupply(address pool, bool flag) internal pure returns (uint256) {
        return 1_000_000e18; // Fixed total supply for testing purposes
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

/// @title Adaptive Supply Manager
/// @notice Dynamically adjusts token supply based on market volatility conditions.
/// @dev This contract determines mint and burn amounts using external scaling algorithms.
contract AdaptiveSupply {
    /// @notice Enum representing different market conditions based on volatility.
    enum MarketConditions {
        LowVolatility,
        MediumVolatility,
        HighVolatility,
        ExtremeVolatility
    }

    /// @notice Instance of the model helper contract.
    IModelHelper public modelHelper;

    /// @notice Array of thresholds used to classify market volatility.
    uint256[4] public volatilityThresholds;

    /// @notice Event emitted when the volatility thresholds are updated.
    /// @param newThresholds The updated array of volatility thresholds.
    event VolatilityThresholdsUpdated(uint256[4] newThresholds);

    /// @notice Error thrown when invalid volatility thresholds are provided.
    error InvalidVolatilityThresholds();

    /// @notice Constructor to initialize the AdaptiveSupply contract.
    /// @param _modelHelper The address of the model helper contract.
    /// @param _volatilityThresholds The initial array of volatility thresholds.
    /// @dev Volatility thresholds must be in ascending order.
    constructor(
        address _modelHelper,
        uint256[4] memory _volatilityThresholds
    ) {
        if (!(_volatilityThresholds[0] < _volatilityThresholds[1] &&
            _volatilityThresholds[1] < _volatilityThresholds[2] &&
            _volatilityThresholds[2] < _volatilityThresholds[3])) {
            revert InvalidVolatilityThresholds();
        }

        modelHelper = IModelHelper(_modelHelper);
        volatilityThresholds = _volatilityThresholds;
    }

    /// @notice Updates the volatility thresholds used to classify market conditions.
    /// @param _newThresholds The new array of volatility thresholds.
    /// @dev Volatility thresholds must be in ascending order.
    function setVolatilityThresholds(uint256[4] memory _newThresholds) public {
        if (!(_newThresholds[0] < _newThresholds[1] &&
            _newThresholds[1] < _newThresholds[2] &&
            _newThresholds[2] < _newThresholds[3])) {
            revert InvalidVolatilityThresholds();
        }

        volatilityThresholds = _newThresholds;
        emit VolatilityThresholdsUpdated(_newThresholds);
    }

    /// @notice Adjusts the token supply based on market conditions and volatility.
    /// @param pool The address of the Uniswap pool.
    /// @param vault The address of the vault managing liquidity.
    /// @param volatility The current market volatility as an integer.
    /// @return mintAmount The calculated amount of tokens to mint.
    /// @return burnAmount The calculated amount of tokens to burn.
    /// @dev Uses external scaling algorithms for calculation based on volatility.
    function adjustSupply(
        address pool,
        address vault,
        int256 volatility
    ) public view returns (uint256 mintAmount, uint256 burnAmount) {
        uint256 totalSupply = modelHelper.getTotalSupply(pool, true);
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, vault);
        uint256 deltaSupply = totalSupply - circulatingSupply;

        MarketConditions markedCondition = getMarketConditions(uint256(volatility));

        if (markedCondition == MarketConditions.LowVolatility) {
            mintAmount = ScalingAlgorithms.harmonicUpdate(
                totalSupply,
                volatility,
                1,
                false
            );
            burnAmount = ScalingAlgorithms.harmonicUpdate(
                totalSupply,
                volatility,
                1,
                true
            );
        } else if (markedCondition == MarketConditions.MediumVolatility) {
            mintAmount = ScalingAlgorithms.harmonicUpdate(
                totalSupply,
                volatility,
                10,
                false
            );
            burnAmount = ScalingAlgorithms.harmonicUpdate(
                totalSupply,
                volatility,
                10,
                true
            );
        } else if (markedCondition == MarketConditions.HighVolatility) {
            mintAmount = ScalingAlgorithms.boundedQuadraticUpdate(
                totalSupply,
                volatility,
                true
            );
            burnAmount = ScalingAlgorithms.boundedQuadraticUpdate(
                totalSupply,
                volatility,
                false
            );
        } else if (markedCondition == MarketConditions.ExtremeVolatility) {
            mintAmount = ScalingAlgorithms.exponentialUpdate(
                totalSupply,
                volatility,
                1
            );
            burnAmount = mintAmount;
        }

        return (mintAmount, burnAmount);
    }

    /// @notice Determines the current market condition based on volatility.
    /// @param volatility The current market volatility.
    /// @return The market condition classified as one of the `MarketConditions` enum values.
    function getMarketConditions(uint256 volatility) public view returns (MarketConditions) {
        if (volatility < volatilityThresholds[0]) {
            return MarketConditions.LowVolatility;
        } else if (volatility < volatilityThresholds[1]) {
            return MarketConditions.MediumVolatility;
        } else if (volatility < volatilityThresholds[2]) {
            return MarketConditions.HighVolatility;
        } else {
            return MarketConditions.ExtremeVolatility;
        }
    }
}
