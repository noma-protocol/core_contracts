


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from '@uniswap/v3-core/libraries/TickMath.sol';
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Uniswap} from "./Uniswap.sol";
import {Utils} from "./Utils.sol";
import {Conversions} from "./Conversions.sol";
import {DecimalMath} from "./DecimalMath.sol";

import {Underlying} from "./Underlying.sol";
import {ModelHelper} from "./ModelHelper.sol";
import {LiquidityHelper} from "./LiquidityHelper.sol";

import {
    LiquidityPosition, 
    LiquidityType, 
    DeployLiquidityParameters,
    AmountsToMint
} from "../Types.sol";

library LiquidityDeployer {

    function deployAnchor(
        address pool,
        address receiver,
        LiquidityPosition memory floorPosition,
        DeployLiquidityParameters memory deployParams,
        bool redeploy
    ) internal returns (
        LiquidityPosition memory newPosition,
        LiquidityType liquidityType
    ) {       
        require(floorPosition.lowerTick != 0, "deployAnchor: invalid floor position");

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        uint256 lowerAnchorPrice = 
        !redeploy ? Utils.addBips(
            Conversions.sqrtPriceX96ToPrice(
                sqrtRatioX96, 
                18
            ), 
            (int256(deployParams.bipsBelowSpot) * -1)
        ) : deployParams.lowerTick != 0 ? Conversions.sqrtPriceX96ToPrice(Conversions.tickToSqrtPriceX96(deployParams.lowerTick), 18) :
        Utils.addBips(
            Conversions.sqrtPriceX96ToPrice(Conversions.tickToSqrtPriceX96(floorPosition.upperTick), 18), 
            (int256(deployParams.bipsBelowSpot) * -1)
        ); 

        uint256 upperAnchorPrice = Utils.addBips(lowerAnchorPrice, int256(deployParams.bips));
        int24 lowerAnchorTick = Conversions.priceToTick(int256(lowerAnchorPrice), deployParams.tickSpacing);

        require(
            floorPosition.upperTick < lowerAnchorTick, 
            "some msg"
        );

        (int24 lowerTick, int24 upperTick) =  
        Conversions
        .computeRangeTicks(
            lowerAnchorPrice, 
            upperAnchorPrice, 
            deployParams.tickSpacing
        );

        require(upperTick > lowerTick, "deployAnchor: invalid ticks");

        uint256 balanceToken0 = ERC20(IUniswapV3Pool(pool).token0()).balanceOf(address(this));
        uint256 balanceToken1 = ERC20(IUniswapV3Pool(pool).token1()).balanceOf(address(this));

        (newPosition) = LiquidityHelper
        .doDeployPosition(
            pool, 
            receiver, 
            sqrtRatioX96, 
            lowerTick, 
            upperTick, 
            LiquidityType.Anchor, 
            AmountsToMint({
                amount0: balanceToken0 * 20 / 100,
                amount1: balanceToken1
            })
        );

        return (
            newPosition, 
            LiquidityType.Anchor
        );
    }
    
    function deployDiscovery(
        address pool,
        address receiver,
        LiquidityPosition memory anchorPosition,
        uint256 bips,
        int24 tickSpacing
    ) internal returns (
        LiquidityPosition memory newPosition,
        LiquidityType liquidityType
    ) {    

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 lowerDiscoveryPrice = Conversions.sqrtPriceX96ToPrice(
            Conversions.tickToSqrtPriceX96(anchorPosition.upperTick), 
            18 // decimals hardcoded for now
        );
        
        lowerDiscoveryPrice = Utils.addBips(lowerDiscoveryPrice, 50);
        uint256 upperDiscoveryPrice = Utils.addBips(lowerDiscoveryPrice, int256(bips));

        (int24 lowerTick, int24 upperTick) = Conversions
        .computeRangeTicks(
            lowerDiscoveryPrice, 
            upperDiscoveryPrice, 
            tickSpacing
        );

        require(
            lowerTick >= anchorPosition.upperTick, 
            "some msg"
        );        

        uint256 balanceToken0 = ERC20(IUniswapV3Pool(pool).token0()).balanceOf(address(this));

        newPosition = LiquidityHelper
        .doDeployPosition(
            pool, 
            receiver, 
            sqrtRatioX96, 
            lowerTick, 
            upperTick,
            LiquidityType.Discovery,
            AmountsToMint({
                amount0: balanceToken0,
                amount1: 0
            })
        );

        newPosition.price = upperDiscoveryPrice;

        return (
            newPosition, 
            LiquidityType.Discovery
        );
    }   
}