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

import "../interfaces/IVault.sol";

import {
    LiquidityPosition, 
    LiquidityType, 
    DeployLiquidityParameters, 
    AmountsToMint,
    tickSpacing
} from "../types/Types.sol";

library LiquidityDeployer {
    
    // Custom errors
    error InvalidTicks();
    error EmptyFloor();
    error NoLiquidity();

    function deployAnchor(
        address pool,
        address receiver,
        uint256 amount0,
        LiquidityPosition memory floorPosition,
        DeployLiquidityParameters memory deployParams
    )
        internal
        returns (
            LiquidityPosition memory newPosition,
            LiquidityType liquidityType
        )
    {
        uint8 decimals = ERC20(address(IUniswapV3Pool(pool).token0())).decimals();

        (int24 lowerTick, int24 upperTick) = Conversions
        .computeRangeTicks(
            Conversions.sqrtPriceX96ToPrice(
                Conversions.tickToSqrtPriceX96(floorPosition.upperTick),
                decimals
            ),
            Utils.addBips(
                Conversions.sqrtPriceX96ToPrice(
                    Conversions.tickToSqrtPriceX96(floorPosition.upperTick),
                    decimals
                ),
                int256(deployParams.bips)
            ),
            deployParams.tickSpacing,
            decimals
        );

        if (upperTick <= lowerTick) {
            revert InvalidTicks();
        }

        (newPosition) = _deployPosition(
            pool,
            receiver,
            lowerTick,
            upperTick,
            LiquidityType.Anchor,
            AmountsToMint({
                amount0: amount0,
                amount1: 0
            })
        );

        return (newPosition, LiquidityType.Anchor);
    }

    function deployDiscovery(
        address pool,
        address receiver,
        uint256 upperDiscoveryPrice,
        int24 discoveryTickSpacing,
        LiquidityPosition memory anchorPosition
    )
        internal
        returns (
            LiquidityPosition memory newPosition,
            LiquidityType liquidityType
        )
    {
        uint8 decimals = ERC20(address(IUniswapV3Pool(pool).token0())).decimals();

        uint256 lowerDiscoveryPrice = Conversions.sqrtPriceX96ToPrice(
            Conversions.tickToSqrtPriceX96(anchorPosition.upperTick),
            decimals
        );

        lowerDiscoveryPrice = Utils.addBips(lowerDiscoveryPrice, 50);

        (int24 lowerTick, int24 upperTick) = Conversions
        .computeRangeTicks(
            lowerDiscoveryPrice,
            upperDiscoveryPrice,
            discoveryTickSpacing,
            decimals
        );

        if (lowerTick <= anchorPosition.upperTick) {
            revert InvalidTicks();
        }

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
        
        if (newFloorPrice < currentFloorPrice) {
            newFloorPrice = currentFloorPrice;
        }

        (uint160 sqrtRatioX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        uint8 decimals = ERC20(address(IUniswapV3Pool(pool).token0())).decimals();

        if (floorPosition.liquidity > 0) {
            
            (int24 lowerTick, int24 upperTick) = 
            Conversions.computeSingleTick(
                newFloorPrice,
                tickSpacing,
                decimals
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
            revert EmptyFloor();
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
            if (amounts.amount0 == 0) {
                revert(
                    string(
                        abi.encodePacked(
                            "_deployPosition: liquidity is 0 : ", 
                            Utils._uint2str(uint256(amounts.amount0))
                        )
                    )
                );
            }
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

    function reDeployFloor(
        address pool,
        address deployer,
        uint256 amount1ToDeploy,
        LiquidityPosition[3] memory positions
    ) internal returns (LiquidityPosition memory newPosition) {
        // Ensuring valid tick range
        if (positions[0].upperTick <= positions[0].lowerTick) {
            revert InvalidTicks();
        }

        // Deploying the new liquidity position
        newPosition = _deployPosition(
            pool, 
            address(this), 
            positions[0].lowerTick,
            positions[0].upperTick,
            LiquidityType.Floor, 
            AmountsToMint({
                amount0: 0,
                amount1: amount1ToDeploy
            })
        );

        LiquidityPosition[3] memory newPositions = [
            newPosition, 
            positions[1], 
            positions[2]
        ];

        IVault(address(this))
        .updatePositions(
            newPositions
        );            
    }

    function computeNewFloorPrice(
        address pool,
        uint256 toSkim,
        uint256 floorNewToken1Balance,
        uint256 circulatingSupply,
        uint256 anchorCapacity,
        LiquidityPosition[3] memory positions
    ) internal pure returns (uint256) {

        if (
            positions[0].liquidity == 0  || 
            positions[1].liquidity == 0 || 
            positions[2].liquidity == 0
        ) {
            revert NoLiquidity();
        }

        uint256 newFloorPrice = DecimalMath.divideDecimal(
            floorNewToken1Balance + toSkim,
            circulatingSupply
        );

        return newFloorPrice;  
    }
    
}
