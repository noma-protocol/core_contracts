// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v3-core/libraries/TickMath.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Uniswap} from "./Uniswap.sol";
import {Utils} from "./Utils.sol";
import {Conversions} from "./Conversions.sol";
import {DecimalMath} from "./DecimalMath.sol";

import {Underlying} from "./Underlying.sol";
import {ModelHelper} from "../model/Helper.sol";
import {LiquidityOps} from "./LiquidityOps.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";

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
    )
        internal
        returns (
            LiquidityPosition memory newPosition,
            LiquidityType liquidityType
        )
    {
        // require(floorPosition.lowerTick != 0, "deployAnchor: invalid floor position");

        (uint160 sqrtRatioX96,,,,,, ) = IUniswapV3Pool(pool).slot0();

        uint256 lowerAnchorPrice = Conversions.sqrtPriceX96ToPrice(
            Conversions.tickToSqrtPriceX96(floorPosition.upperTick),
            18
        );

        uint256 upperAnchorPrice = Utils.addBips(
            lowerAnchorPrice,
            int256(deployParams.bips)
        );

        int24 lowerAnchorTick = Conversions.priceToTick(
            int256(lowerAnchorPrice),
            deployParams.tickSpacing
        );

        require(floorPosition.upperTick <= lowerAnchorTick, "some msg 1");

        (int24 lowerTick, int24 upperTick) = Conversions.computeRangeTicks(
            lowerAnchorPrice + lowerAnchorPrice * 1 / 100,
            upperAnchorPrice,
            deployParams.tickSpacing
        );

        require(upperTick > lowerTick, "deployAnchor: invalid ticks");

        uint256 balanceToken0 = ERC20(IUniswapV3Pool(pool).token0()).balanceOf(
            address(this)
        );
        uint256 balanceToken1 = ERC20(IUniswapV3Pool(pool).token1()).balanceOf(
            address(this)
        );

        (newPosition) = _deployPosition(
            pool,
            receiver,
            lowerTick,
            upperTick,
            LiquidityType.Anchor,
            AmountsToMint({
                amount0: 5_000_000e18,
                amount1: 0
            })
        );

        return (newPosition, LiquidityType.Anchor);
    }

    function deployDiscovery(
        address pool,
        address receiver,
        LiquidityPosition memory anchorPosition,
        uint256 upperDiscoveryPrice,
        int24 tickSpacing
    )
        internal
        returns (
            LiquidityPosition memory newPosition,
            LiquidityType liquidityType
        )
    {
        uint256 lowerDiscoveryPrice = Conversions.sqrtPriceX96ToPrice(
            Conversions.tickToSqrtPriceX96(anchorPosition.upperTick),
            18 // decimals hardcoded for now
        );

        lowerDiscoveryPrice = Utils.addBips(lowerDiscoveryPrice, 50);

        (int24 lowerTick, int24 upperTick) = Conversions.computeRangeTicks(
            lowerDiscoveryPrice,
            upperDiscoveryPrice,
            tickSpacing
        );

        require(lowerTick >= anchorPosition.upperTick, "some msg 2");

        uint256 balanceToken0 = ERC20(IUniswapV3Pool(pool).token0()).balanceOf(
            address(this)
        );

        newPosition = _deployPosition(
            pool,
            receiver,
            lowerTick,
            upperTick,
            LiquidityType.Discovery,
            AmountsToMint({amount0: balanceToken0, amount1: 0})
        );

        newPosition.price = upperDiscoveryPrice;

        return (newPosition, LiquidityType.Discovery);
    }

    function shiftFloor(
        address pool,
        address receiver,
        uint256 currentFloorPrice,
        uint256 newFloorPrice,
        uint256 newFloorBalance,
        uint256 currentFloorBalance,
        LiquidityPosition memory floorPosition
    ) public returns (LiquidityPosition memory newPosition) {

        (uint160 sqrtRatioX96, , , , , , ) = IUniswapV3Pool(pool).slot0();

        if (floorPosition.liquidity > 0) {
            
            (int24 lowerTick, int24 upperTick) = 
            Conversions.computeSingleTick(
                newFloorPrice > 1 ? newFloorPrice : 
                // Conversions
                // .sqrtPriceX96ToPrice(
                //     Conversions
                //     .tickToSqrtPriceX96(
                //         floorPosition.lowerTick
                //     ), 
                // 18),
                currentFloorPrice,
                60
            );

            uint128 newLiquidity = LiquidityAmounts
            .getLiquidityForAmounts(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(lowerTick),
                TickMath.getSqrtRatioAtTick(upperTick),
                0,
                newFloorBalance > currentFloorBalance ? newFloorBalance : currentFloorBalance
            );

            if (newLiquidity > 0) {

                Uniswap.mint(
                    pool,
                    receiver,
                    lowerTick,
                    upperTick,
                    newLiquidity,
                    LiquidityType.Floor,
                    false
                );

                newPosition.liquidity = newLiquidity;
                newPosition.upperTick = upperTick;
                newPosition.lowerTick = lowerTick;

            } else {
                revert(
                    string(
                        abi.encodePacked(
                            "shiftFloor: liquidity is 0 : ", 
                            Utils._uint2str(uint256(currentFloorBalance))
                        )
                    )
                );
            }

        } else {
            revert("empty floorPosition");
        }

        return newPosition;
    }

    function _deployPosition(
        address pool,
        address receiver,
        int24 lowerTick,
        int24 upperTick,
        LiquidityType liquidityType,
        AmountsToMint memory amounts
    ) internal returns (LiquidityPosition memory newPosition) {
        
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amounts.amount0, 
            amounts.amount1
        );

        if (liquidityType == LiquidityType.Discovery) {
            require(amounts.amount0 >= 1 ether, "_deployPosition: amount0 is too low");
        }

        if (liquidity > 0) {
            Uniswap.mint(
                pool, 
                receiver, 
                lowerTick, 
                upperTick, 
                liquidity, 
                liquidityType, 
                false
            );
        } else {
            revert(
                string(
                    abi.encodePacked(
                        "_deployPosition: liquidity is 0 : ", 
                        Utils._uint2str(uint256(liquidity))
                    )
                )
            );
        }

        newPosition = LiquidityPosition({
            lowerTick: lowerTick, 
            upperTick: upperTick, 
            liquidity: liquidity, 
            price: 0
        });    
    }

    function computeNewFloorPrice(
        address pool,
        uint256 toSkim,
        uint256 floorNewToken1Balance,
        uint256 circulatingSupply,
        uint256 anchorCapacity,
        LiquidityPosition[3] memory positions
    ) internal view returns (uint256) {
        require(
            positions[0].liquidity > 0 &&
            positions[1].liquidity > 0 &&  
            positions[2].liquidity > 0, 
            "computeNewFloorPrice: no liquidity in positions"
        );

        uint256 newFloorPrice = DecimalMath.divideDecimal(
            floorNewToken1Balance + toSkim,
            circulatingSupply - anchorCapacity
        );

        if (newFloorPrice <= 1e18) {
            return 0;
        } else {
            return newFloorPrice;
            
            revert(
                string(
                    abi.encodePacked(
                        "pool: newFloorPrice is : ", 
                        Utils._uint2str(uint256(newFloorPrice))
                    )
                )
            );            
        }
    }
}
