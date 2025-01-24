// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "solmate/utils/FixedPointMathLib.sol";

contract AdaptiveSupply {
    using FixedPointMathLib for uint256;

    /**
     * @notice Calculates the mint amount based on delta supply, volatility, and time.
     * @param deltaSupply The difference between total supply cap and circulating supply.
     * @param volatility The current volatility of the token price (scaled to 18 decimals).
     * @param timeElapsed The time elapsed (in seconds) since the last mint event.
     * @return mintAmount The calculated mint amount.
     */
    function calculateMintAmount(
        uint256 deltaSupply,
        uint256 volatility,
        uint256 timeElapsed
    ) public pure returns (uint256 mintAmount) {
        require(timeElapsed > 0, "Time elapsed must be greater than zero");
        require(deltaSupply > 0, "Delta supply must be greater than zero");

        // Calculate the square root of time elapsed
        uint256 sqrtTime = timeElapsed.sqrt();

        // Apply the mint formula: (deltaSupply / sqrtTime) * (1 / (1 + volatility))
        // volatility is scaled to 18 decimals, so adjust the divisor
        uint256 volatilityFactor = uint256(1e18).divWadDown(1e18 + volatility); // 1 / (1 + volatility)
        mintAmount = deltaSupply.mulWadDown(volatilityFactor).divWadDown(sqrtTime);
        mintAmount = mintAmount / 1e18; // Scale down to 18 decimals
    }
}