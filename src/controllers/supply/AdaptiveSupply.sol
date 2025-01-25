// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "solmate/utils/FixedPointMathLib.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

interface IERC20 { 
    function decimals() external view returns (uint8);
}

interface IVault{
    function pool() external view returns (IUniswapV3Pool);
}

contract AdaptiveSupply {
    using FixedPointMathLib for uint256;

    /**
     * @notice Calculates the mint amount based on delta supply, volatility, and time.
     * @param deltaSupply The difference between total supply cap and circulating supply.
     * @param volatility The current volatility of the token price (scaled to `tokenDecimals`).
     * @param timeElapsed The time elapsed (in seconds) since the last mint event.
     * @return mintAmount The calculated mint amount.
     */
    function calculateMintAmount(
        uint256 deltaSupply,
        uint256 volatility,
        uint256 timeElapsed
    ) public view returns (uint256 mintAmount) {
        require(timeElapsed > 0, "Time elapsed must be greater than zero");
        require(deltaSupply > 0, "Delta supply must be greater than zero");

        uint256 tokenDecimals = IERC20(
            IUniswapV3Pool(
                IVault(msg.sender).pool()
            ).token1()
        ).decimals(); 

        // Scale factor to adjust for token decimals
        uint256 scaleFactor = 10**(18 - tokenDecimals);

        // Calculate the square root of time elapsed
        uint256 sqrtTime = timeElapsed.sqrt();

        // Apply the mint formula: (deltaSupply / sqrtTime) * (1 / (1 + volatility))
        // volatility is scaled to tokenDecimals, so adjust the divisor
        uint256 volatilityFactor = scaleFactor.divWadDown(scaleFactor + volatility); // 1 / (1 + volatility)
        mintAmount = deltaSupply.mulWadDown(volatilityFactor).divWadDown(sqrtTime);

        // Scale down to token decimals
        mintAmount = mintAmount / scaleFactor;
    }
}