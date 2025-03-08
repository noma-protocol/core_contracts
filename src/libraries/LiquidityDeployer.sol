// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Uniswap} from "./Uniswap.sol";
import {Utils} from "./Utils.sol";
import {Conversions} from "./Conversions.sol";
import {DecimalMath} from "./DecimalMath.sol";

import {IVault} from "../interfaces/IVault.sol";

import {
    LiquidityPosition, 
    LiquidityType, 
    DeployLiquidityParameters, 
    AmountsToMint
} from "../types/Types.sol";

/**
 * @title LiquidityDeployer
 * @notice A library for deploying and managing liquidity positions in a Uniswap V3 pool.
 */
library LiquidityDeployer {
    
    // Custom errors
    error InvalidTicks();
    error EmptyFloor();
    error NoLiquidity();

    /**
     * @notice Deploys an anchor liquidity position.
     * @param pool The address of the Uniswap V3 pool.
     * @param receiver The address that will receive the liquidity position.
     * @param amount0 The amount of token0 to deploy.
     * @param floorPosition The current floor liquidity position.
     * @param deployParams Parameters for deploying the liquidity position.
     * @return newPosition The new liquidity position.
     * @return liquidityType The type of liquidity position (Anchor).
     */
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
        (int24 lowerTick, int24 upperTick) = Conversions
        .computeRangeTicks(
            Conversions.sqrtPriceX96ToPrice(
                Conversions.tickToSqrtPriceX96(floorPosition.upperTick),
                IERC20Metadata(address(IUniswapV3Pool(pool).token0())).decimals()
            ),
            Utils.addBips(
                Conversions.sqrtPriceX96ToPrice(
                    Conversions.tickToSqrtPriceX96(floorPosition.upperTick),
                    IERC20Metadata(address(IUniswapV3Pool(pool).token0())).decimals()
                ),
                int256(deployParams.bips)
            ),
            deployParams.tickSpacing,
            IERC20Metadata(address(IUniswapV3Pool(pool).token0())).decimals()
        );

        if (upperTick <= lowerTick) {
            revert InvalidTicks();
        }

        (newPosition) = _deployPosition(
            pool,
            receiver,
            lowerTick,
            upperTick,
            floorPosition.tickSpacing,
            LiquidityType.Anchor,
            AmountsToMint({
                amount0: amount0,
                amount1: 0
            })
        );

        return (newPosition, LiquidityType.Anchor);
    }

    /**
     * @notice Deploys a discovery liquidity position.
     * @param pool The address of the Uniswap V3 pool.
     * @param receiver The address that will receive the liquidity position.
     * @param upperDiscoveryPrice The upper price bound for the discovery position.
     * @param discoveryTickSpacing The tick spacing for the discovery position.
     * @param anchorPosition The current anchor liquidity position.
     * @return newPosition The new liquidity position.
     * @return liquidityType The type of liquidity position (Discovery).
     */
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
        uint8 decimals = IERC20Metadata(address(IUniswapV3Pool(pool).token0())).decimals();

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

        uint256 balanceToken0 = IERC20Metadata(IUniswapV3Pool(pool).token0()).balanceOf(
            address(this)
        );

        newPosition = _deployPosition(
            pool,
            receiver,
            lowerTick,
            upperTick,
            anchorPosition.tickSpacing,
            LiquidityType.Discovery,
            AmountsToMint({
                amount0: balanceToken0, 
                amount1: 0
            })
        );

        newPosition.price = upperDiscoveryPrice;

        return (newPosition, LiquidityType.Discovery);
    }

    /**
     * @notice Shifts the floor liquidity position to a new price range.
     * @param pool The address of the Uniswap V3 pool.
     * @param receiver The address that will receive the new liquidity position.
     * @param currentFloorPrice The current floor price.
     * @param newFloorPrice The new floor price.
     * @param newFloorBalance The new balance of token1 for the floor position.
     * @param currentFloorBalance The current balance of token1 for the floor position.
     * @param floorPosition The current floor liquidity position.
     * @return newPosition The new liquidity position.
     */
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
        uint8 decimals = IERC20Metadata(address(IUniswapV3Pool(pool).token0())).decimals();

        if (floorPosition.liquidity > 0) {
            
            (int24 lowerTick, int24 upperTick) = 
            Conversions.computeSingleTick(
                newFloorPrice,
                floorPosition.tickSpacing,
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
                newPosition.tickSpacing = floorPosition.tickSpacing;

            } else {
                revert(
                    string(
                        abi.encodePacked(
                            "shiftFloor: liquidity is 0 : ", 
                            Utils._uint2str(uint256(newFloorBalance > currentFloorBalance ? newFloorBalance : currentFloorBalance))
                        )
                    )
                );
            }

        } else {
            revert EmptyFloor();
        }

        return newPosition;
    }

    /**
     * @notice Internal function to deploy a liquidity position.
     * @param pool The address of the Uniswap V3 pool.
     * @param receiver The address that will receive the liquidity position.
     * @param lowerTick The lower tick of the position.
     * @param upperTick The upper tick of the position.
     * @param tickSpacing The tick spacing of the position.
     * @param liquidityType The type of liquidity position (Floor, Anchor, Discovery).
     * @param amounts The amounts of token0 and token1 to deploy.
     * @return newPosition The new liquidity position.
     */
    function _deployPosition(
        address pool,
        address receiver,
        int24 lowerTick, 
        int24 upperTick,
        int24 tickSpacing,
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
                            "_deployPosition(1): liquidity is 0 : ", 
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
                        "_deployPosition(2): liquidity is 0 : ", 
                        Utils._uint2str(uint256(liquidity))
                    )
                )
            );
        }

        newPosition = LiquidityPosition({
            lowerTick: lowerTick, 
            upperTick: upperTick, 
            liquidity: liquidity, 
            price: 0,
            tickSpacing: tickSpacing
        });    
    }

    /**
     * @notice Redeploys the floor liquidity position.
     * @param pool The address of the Uniswap V3 pool.
     * @param amount1ToDeploy The amount of token1 to deploy.
     * @param positions The current liquidity positions.
     * @return newPosition The new floor liquidity position.
     */
    function reDeployFloor(
        address pool,
        address vault,
        uint256 amount0ToDeploy,
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
            vault, 
            positions[0].lowerTick,
            positions[0].upperTick,
            positions[0].tickSpacing,
            LiquidityType.Floor, 
            AmountsToMint({
                amount0: amount0ToDeploy,
                amount1: amount1ToDeploy
            })
        );

        LiquidityPosition[3] memory newPositions = [
            newPosition, 
            positions[1], 
            positions[2]
        ];

        IVault(vault)
        .updatePositions(
            newPositions
        );            
    }

    /**
     * @notice Computes the new floor price based on the provided parameters.
     * @param toSkim The amount of token1 to skim.
     * @param floorNewToken1Balance The new balance of token1 for the floor position.
     * @param circulatingSupply The circulating supply of the vault.
     * @param positions The current liquidity positions.
     * @return newFloorPrice The new floor price.
     */
    function computeNewFloorPrice(
        uint256 toSkim,
        uint256 floorNewToken1Balance,
        uint256 circulatingSupply,
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