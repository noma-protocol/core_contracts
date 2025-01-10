// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IModelHelper } from "./interfaces/IModelHelper.sol";

contract AdaptiveSupply {

    uint256 public kp = 1; // Proportional gain
    uint256 public ki = 1; // Integral gain
    uint256 public kd = 1; // Derivative gain

    int256 public previousVolatility;
    int256 public integral;

    uint256 lastUpdateTime;

    IModelHelper public modelHelper;

    constructor(address _modelHelper) {
        modelHelper = IModelHelper(_modelHelper);
    }

    /**
     * @notice Adjusts the supply based on volatility
     * @param volatility Current volatility (e.g., % in 10**18 precision)
     */
    function adjustSupply(address pool, address vault, int256 volatility) public 
    returns (uint256 mintAmount, uint256 burnAmount) {
        uint256 currentTime = block.timestamp;
        uint256 deltaTime = currentTime - lastUpdateTime;
        require(deltaTime > 0, "Time step must be greater than zero");

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, vault);
        uint256 totalSupply = modelHelper.getTotalSupply(pool, true);

        // Dynamically update PID coefficients based on external factors
        adjustCoefficients(volatility);

        // Proportional term
        int256 proportional = volatility * int256(kp);

        // Integral term
        integral += volatility * int256(deltaTime);
        int256 integralTerm = integral * int256(ki);

        // Derivative term
        int256 derivative = ((volatility - previousVolatility) * int256(kd)) / int256(deltaTime);

        // PID adjustment
        int256 adjustment = proportional + integralTerm + derivative;

        // Update supply based on adjustment
        if (adjustment > 0) {
            // Mint tokens
            mintAmount = uint256(adjustment);
            totalSupply += mintAmount;
            circulatingSupply += mintAmount;
        } else {
            // Burn tokens
            burnAmount = uint256(-adjustment);
            if (burnAmount > circulatingSupply) {
                burnAmount = circulatingSupply; // Prevent underflow
            }
            totalSupply -= burnAmount;
            circulatingSupply -= burnAmount;
        }

        // Update state
        previousVolatility = volatility;
        lastUpdateTime = currentTime;
    }

    /**
     * @notice Update PID coefficients
     */
    function adjustCoefficients(int256 volatility) internal {
        // Example: Increase proportional gain if volatility exceeds a threshold
        if (volatility > 1e17) { // 10% volatility
            kp = kp + 1;
        } else if (volatility < 1e16) { // 1% volatility
            kp = kp > 1 ? kp - 1 : kp; // Avoid dropping below 1
        }

        // Example: Adjust integral gain based on time elapsed
        if (block.timestamp - lastUpdateTime > 1 days) {
            ki = ki + 1;
        }

        // Example: Reduce derivative gain if volatility stabilizes
        if (previousVolatility == volatility) {
            kd = kd > 1 ? kd - 1 : kd;
        }
    }

}