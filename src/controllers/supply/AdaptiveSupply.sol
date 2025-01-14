// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ScalingAlgorithms.sol";

interface IModelHelper {
    function getCirculatingSupply(address pool, address vault) external view returns (uint256);
    function getTotalSupply(address pool, bool flag) external view returns (uint256);
}

contract MockModelHelper is IModelHelper {
    function getCirculatingSupply(address pool, address vault) public view returns (uint256) {
        return _getCirculatingSupply(pool, vault);
    }

    function getTotalSupply(address pool, bool flag) public pure returns (uint256) {
        return _getTotalSupply(pool, flag);
    }

    function _getTotalSupply(address pool, bool flag) internal pure returns (uint256) {
        return 1_000_000e18; // Fixed total supply for testing purposes
    }

    function _getCirculatingSupply(address pool, address vault) internal view returns (uint256) {
        uint256 totalSupply = _getTotalSupply(pool, true);
        uint256 randomFactor = random();

        uint256 circulatingSupply = totalSupply * (100 - randomFactor) / 100;

        return circulatingSupply;
    }

    function random() private view returns (uint256) {
        uint256 randomHash = uint256(keccak256(
            abi.encodePacked(block.prevrandao, block.timestamp)
        ));
        return randomHash % 20; // Random number between 0 and 19
    }
}

contract AdaptiveSupply {
    // Enum representing different marked conditions for volatility
    enum MarketConditions {
        LowVolatility,
        MediumVolatility,
        HighVolatility,
        ExtremeVolatility
    }

    IModelHelper public modelHelper;

    uint256[4] public volatilityThresholds;

    event VolatilityThresholdsUpdated(uint256[4] newThresholds);

    constructor(
        address _modelHelper,
        uint256[4] memory _volatilityThresholds
    ) {
        require(
            _volatilityThresholds[0] < _volatilityThresholds[1] &&
            _volatilityThresholds[1] < _volatilityThresholds[2] &&
            _volatilityThresholds[2] < _volatilityThresholds[3],
            "Invalid volatility thresholds"
        );

        modelHelper = IModelHelper(_modelHelper);
        volatilityThresholds = _volatilityThresholds;
    }

    function setVolatilityThresholds(uint256[4] memory _newThresholds) public {
        require(
            _newThresholds[0] < _newThresholds[1] &&
            _newThresholds[1] < _newThresholds[2] &&
            _newThresholds[2] < _newThresholds[3],
            "Invalid volatility thresholds"
        );

        volatilityThresholds = _newThresholds;
        emit VolatilityThresholdsUpdated(_newThresholds);
    }

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
