// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library ScalingAlgorithms {
    /**
     * @notice Exponential Growth or Decay
     * Exponential growth or decay can be modeled using the formula:
     *
     * New Value = Current Value × (1 + r)^n
     * 
     * Where:
     * r: Scaling factor (growth rate, typically a small percentage like 0.05 for 5%).
     * n: Number of iterations or steps (optional, set to 1 for simple scaling).
     * 
     * For Decrease: Use a negative r:
     * New Value = Current Value × (1 - r)^n
     */
    function exponentialUpdate(uint256 value, int256 rate, uint256 iterations) public pure returns (uint256) {
        int256 scaleFactor = int256(1e18) + rate; // Scale factor with 18 decimals
        for (uint256 i = 0; i < iterations; i++) {
            value = uint256((int256(value) * scaleFactor) / 1e18); // Update value exponentially
        }
        return value;
    }

    /**
     * @notice Quadratic Growth or Decay
     * Adjusts the value quadratically based on the square of the scaling factor:
     *
     * New Value = Current Value × (1 + r^2) for growth
     * New Value = Current Value × (1 - r^2) for decay
     */
    function boundedQuadraticUpdate(
        uint256 value,
        int256 rate,
        bool increase
    ) public pure returns (uint256) {
        // Calculate r^2 with 18 decimals precision
        int256 rateSquared = (rate * rate) / int256(1e18);

        // Set bounds for the scale factor
        int256 minScale = int256(0.9e18); // 0.9 (90%)
        int256 maxScale = int256(1.1e18); // 1.1 (110%)

        // Calculate scale factor
        int256 scaleFactor = increase
            ? int256(1e18) + rateSquared // Mint: Scale up
            : int256(1e18) - rateSquared; // Burn: Scale down

        // Ensure scaleFactor remains within bounds
        scaleFactor = scaleFactor < minScale ? minScale : scaleFactor;
        scaleFactor = scaleFactor > maxScale ? maxScale : scaleFactor;

        // Apply scaling to value
        return uint256((int256(value) * scaleFactor) / int256(1e18));
    }


    /**
     * @notice Sigmoid Scaling
     * Provides a smooth adjustment based on a sigmoid function, useful for bounded growth or decay.
     * Formula:
     * New Value = Max Value × 1 / (1 + e^(-k × (Input - x0)))
     * 
     * Where:
     * k: Controls the steepness of the curve.
     * x0: Midpoint of the curve.
     */
    function sigmoidUpdate(uint256 value, int256 input, int256 k, int256 midpoint) public pure returns (uint256) {
        int256 exponent = -k * (input - midpoint); // Compute exponent
        uint256 expResult = exp(exponent); // Compute exponential as uint256
        int256 scaledExpResult = int256(expResult); // Convert exp result to int256 for consistency
        int256 sigmoid = int256(1e18) * int256(1e18) / (int256(1e18) + scaledExpResult); // Compute sigmoid factor
        return uint256((int256(value) * sigmoid) / int256(1e18)); // Apply sigmoid scaling and return
    }

    /**
     * @notice Multiplicative Scaling with Damping
     * Gradually increases or decreases a value by multiplying it with a damping factor.
     * Formula:
     * New Value = Current Value × (1 ± r^n)
     * 
     * Where:
     * n: Exponential term to adjust the strength.
     */
    function multiplicativeUpdate(uint256 value, int256 rate, uint256 iterations, bool increase) public pure returns (uint256) {
        for (uint256 i = 0; i < iterations; i++) {
            int256 factor = int256(1e18) + (increase ? rate : -rate); // Add or subtract rate
            value = uint256((int256(value) * factor) / 1e18); // Update value multiplicatively
        }
        return value;
    }

    /**
     * @notice Harmonic Mean Scaling
     * Gradually adjusts the value with diminishing updates over time.
     * Formula:
     * New Value = Current Value ± r / (1 + n)
     */
    function harmonicUpdate(uint256 value, int256 rate, uint256 iterations, bool increase) public pure returns (uint256) {
        for (uint256 i = 0; i < iterations; i++) {
            int256 adjustment = rate / int256(1 + i); // Diminishing adjustment
            value = uint256(int256(value) + (increase ? adjustment : -adjustment)); // Update value
        }
        return value;
    }

    /**
     * @notice Polynomial Scaling
     * Adjusts the value using a polynomial function of the scaling factor (e.g., cubic growth or decay).
     * Formula:
     * New Value = Current Value × (1 + r^3) for growth
     * New Value = Current Value × (1 - r^3) for decay
     */
    function polynomialUpdate(uint256 value, int256 rate, bool increase) public pure returns (uint256) {
        int256 rateCubed = (rate * rate * rate) / int256(1e36); // Compute r^3 with 18 decimals
        int256 scaleFactor = int256(1e18) + (increase ? rateCubed : -rateCubed); // Add or subtract r^3
        return uint256((int256(value) * scaleFactor) / 1e18);   // Apply polynomial adjustment
    }

    /**
     * @notice Helper function to compute the exponential value (e^x) with fixed-point arithmetic
     */
    function exp(int256 x) internal pure returns (uint256) {
        // Use a Taylor series approximation for e^x
        if (x > 2454971259878909886679) return type(uint256).max; // Prevent overflow
        if (x < -818323753292969962227) return 0; // Values too small to matter

        uint256 result = 1e18; // e^0 = 1 scaled to 18 decimals
        uint256 term = 1e18;
        uint256 absX = uint256(x < 0 ? -x : x); // Absolute value of x
        for (uint256 i = 1; i < 50; ++i) { // Limit series to 50 iterations for gas efficiency
            term = (term * absX) / (i * 1e18);
            if (x < 0) result -= term; // Handle negative exponents
            else result += term;
            if (term < 1) break; // Stop when terms are too small to matter
        }
        return result;
    }

}
