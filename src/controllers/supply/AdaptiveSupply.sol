// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/ScalingAlgorithms.sol";

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
                deltaSupply,
                volatility,
                1,
                false
            );
            burnAmount = ScalingAlgorithms.harmonicUpdate(
                deltaSupply,
                volatility,
                1,
                true
            );
        } else if (markedCondition == MarketConditions.MediumVolatility) {
            mintAmount = ScalingAlgorithms.harmonicUpdate(
                deltaSupply,
                volatility,
                10,
                false
            );
            burnAmount = ScalingAlgorithms.harmonicUpdate(
                deltaSupply,
                volatility,
                10,
                true
            );
        } else if (markedCondition == MarketConditions.HighVolatility) {
            mintAmount = ScalingAlgorithms.boundedQuadraticUpdate(
                deltaSupply,
                volatility,
                true
            );
            burnAmount = ScalingAlgorithms.boundedQuadraticUpdate(
                deltaSupply,
                volatility,
                false
            );
        } else if (markedCondition == MarketConditions.ExtremeVolatility) {
            mintAmount = ScalingAlgorithms.polynomialUpdate(
                deltaSupply,
                volatility / 1e18, 
                true
            );
            burnAmount = ScalingAlgorithms.polynomialUpdate(
                deltaSupply,
                volatility / 1e18,
                false
            );
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
