

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

import {
    LiquidityPosition, 
    LiquidityType, 
    DeployLiquidityParameters,
    AmountsToMint
} from "../Types.sol";

library LiquidityHelper {

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
        ) : Conversions.sqrtPriceX96ToPrice(Conversions.tickToSqrtPriceX96(deployParams.lowerTick), 18); 
        
        if (!redeploy) {
            require(
                floorPosition.upperTick <= Conversions.priceToTick(int256(lowerAnchorPrice), deployParams.tickSpacing), 
                string(
                    abi.encodePacked(
                        "deployAnchor: invalid anchor, spot price: ", 
                        Utils._uint2str(floorPosition.price)
                    )
                )
            );
        }

        (int24 lowerTick, int24 upperTick) =  
        Conversions
        .computeRangeTicks(
            lowerAnchorPrice, 
            !redeploy ? Utils.addBips(lowerAnchorPrice, int256(deployParams.bips)) :
            Conversions.sqrtPriceX96ToPrice(Conversions.tickToSqrtPriceX96(deployParams.upperTick), 18), 
            deployParams.tickSpacing
        );

        uint256 balanceToken0 = ERC20(IUniswapV3Pool(pool).token0()).balanceOf(address(this));
        uint256 balanceToken1 = ERC20(IUniswapV3Pool(pool).token1()).balanceOf(address(this));

        (newPosition) = doDeployPosition(
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
            string(
                abi.encodePacked(
                    "deployDiscovery: invalid anchor, spot price: ", 
                    Utils._uint2str(sqrtRatioX96)
                )
            )
        );        

        uint256 balanceToken0 = ERC20(IUniswapV3Pool(pool).token0()).balanceOf(address(this));

        newPosition = doDeployPosition(
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

    function shiftFloor(
        address pool,
        address receiver,
        LiquidityPosition memory floorPosition,
        address token1,
        uint256 bips,
        int24 tickSpacing
    ) internal {
        require(bips < 10_000, "invalid bips");

        uint256 newFloorPrice = Utils.addBips(floorPosition.price, int256(bips));
        int24 newFloorLowerTick = Conversions.priceToTick(int256(newFloorPrice), tickSpacing);

        require(newFloorLowerTick > floorPosition.lowerTick, "invalid floor");

        bytes32 floorPositionId = keccak256(
            abi.encodePacked(
                    address(this), 
                    floorPosition.lowerTick, 
                    floorPosition.upperTick
                )
            );

        (uint128 liquidity,,,,) = IUniswapV3Pool(pool).positions(floorPositionId);

        if (liquidity > 0) {
            Uniswap.burn(
                pool,
                receiver,
                floorPosition.lowerTick,
                floorPosition.upperTick,
                liquidity
            );
        } else {
            revert("shiftFloor: liquidity is 0");
        }

        uint256 balanceAfterShiftFloorToken1 = ERC20(token1).balanceOf(address(this));
        
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        (, int24 newFloorUpperTick) = Conversions.computeSingleTick(newFloorPrice, tickSpacing);

        uint256 amount0Max = 0;
        uint256 amount1Max = balanceAfterShiftFloorToken1;

        uint128 newLiquidity = LiquidityAmounts
        .getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(newFloorLowerTick),
            TickMath.getSqrtRatioAtTick(newFloorUpperTick),
            amount0Max,
            amount1Max
        );

        if (newLiquidity > 0) {
            Uniswap.mint(pool, receiver, newFloorLowerTick, newFloorUpperTick, liquidity, LiquidityType.Floor, true);
            // IVault(vault).updatePosition(
            //     LiquidityPosition(
            //         newFloorLowerTick, 
            //         newFloorUpperTick, 
            //         newLiquidity, 
            //         newFloorPrice,
            //         0,
            //         0,
            //         0
            //     ), 
            //     LiquidityType.Floor,
            //     0
            // );
        } else {
            revert(
                string(
                    abi.encodePacked(
                            "shiftFloor: liquidity is 0  ", 
                            Utils._uint2str(uint256(sqrtRatioX96)
                        )
                    )
                )
            ); 
        }
    }

    function shift(
        address pool,
        LiquidityPosition memory floorPosition,
        LiquidityPosition memory anchorPosition,
        LiquidityType liquidityType
    ) internal 
    returns (
        uint256 currentLiquidityRatio, 
        LiquidityPosition memory newPosition
    ) {

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        currentLiquidityRatio = ModelHelper.getLiquidityRatio(pool, anchorPosition);
        
        (,,, uint256 balanceToken1BeforeCollect) = Underlying.getUnderlyingBalances(pool, anchorPosition);

        if (currentLiquidityRatio < 1e18) {
            // Shift
            // ETH after skim at floor = ETH before skim at anchor - (liquidity ratio * ETH before skim at anchor)
            collect(pool, address(this), anchorPosition);

            uint256 toSkim = balanceToken1BeforeCollect - (DecimalMath.multiplyDecimal(currentLiquidityRatio, balanceToken1BeforeCollect));

            // addToFloor(pool, floorPosition, toSkim);

            newPosition = reDeployAnchor(pool, sqrtRatioX96, floorPosition, liquidityType);

        }
    }

    function reDeployAnchor(
        address pool,
        uint160 sqrtRatioX96,
        LiquidityPosition memory floorPosition,
        LiquidityType liquidityType
    ) internal returns (LiquidityPosition memory newPosition) {
            newPosition = doDeployPosition(
                pool, 
                address(this), 
                sqrtRatioX96, 
                Conversions.priceToTick(
                    int256(
                        Utils.addBips(
                            Conversions
                            .sqrtPriceX96ToPrice(
                                Conversions.tickToSqrtPriceX96(floorPosition.lowerTick), 
                            18), 
                            500
                        )
                    ), 
                60), 
                Conversions.priceToTick(
                    int256(
                        Utils.addBips(
                            Conversions
                            .sqrtPriceX96ToPrice(
                                Conversions.tickToSqrtPriceX96(floorPosition.upperTick), 
                            18),
                            500
                        )
                    ), 
                60), 
                liquidityType, 
                AmountsToMint({
                    amount0: ERC20(IUniswapV3Pool(pool).token0()).balanceOf(address(this)),
                    amount1: liquidityType == LiquidityType.Anchor ? ERC20(IUniswapV3Pool(pool).token1()).balanceOf(address(this)) : 0
                })
            );     
    }
        

    function doDeployPosition(
        address pool,
        address receiver,
        uint160 sqrtRatioX96,
        int24 lowerTick,
        int24 upperTick,
        LiquidityType liquidityType,
        AmountsToMint memory amounts
    ) internal returns (LiquidityPosition memory newPosition) {
 
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amounts.amount0, 
            amounts.amount1
        );

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
                            "dodDeployPosition: liquidity is 0, spot price:  ", 
                            Utils._uint2str(uint256(amounts.amount0)
                        )
                    )
                )
            ); 
        }  

        newPosition = LiquidityPosition({
            lowerTick: lowerTick, 
            upperTick: upperTick, 
            liquidity: liquidity, 
            price: 0,
            amount0LowerBound: 0,
            amount1UpperBound: 0,
            amount1UpperBoundVirtual: 0
        });    
    }

    // function addToFloor(
    //     address pool,
    //     LiquidityPosition memory floorPosition,
    //     uint256 amountToken1
    // ) internal {

    //     (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

    //     (
    //         uint128 liquidity,,,,
    //     ) = IUniswapV3Pool(pool).positions(
    //         keccak256(
    //         abi.encodePacked(
    //             address(this), 
    //             floorPosition.lowerTick, 
    //             floorPosition.upperTick
    //             )
    //         )            
    //     );

    //     if (liquidity > 0) {
            
    //         uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
    //             sqrtRatioX96,
    //             TickMath.getSqrtRatioAtTick(floorPosition.lowerTick),
    //             TickMath.getSqrtRatioAtTick(floorPosition.upperTick),
    //             0,
    //             amountToken1
    //         );

    //         if (newLiquidity > 0) {
    //             Uniswap.mint(
    //                 pool, 
    //                 address(this), 
    //                 floorPosition.lowerTick, 
    //                 floorPosition.upperTick, 
    //                 newLiquidity, 
    //                 LiquidityType.Floor, 
    //                 false
    //             );
    //         }

    //     }        
    // }

    function collect(
        address pool,
        address receiver,
        LiquidityPosition memory position
    ) internal {

        bytes32 positionId = keccak256(
            abi.encodePacked(
                address(this), 
                position.lowerTick, 
                position.upperTick
            )
        );

        (uint128 liquidity,,,,) = IUniswapV3Pool(pool).positions(positionId);

        if (liquidity > 0) {
            Uniswap.burn(
                pool,
                receiver,
                position.lowerTick, 
                position.upperTick,
                liquidity
            );
        } else {
            revert(
                string(
                    abi.encodePacked(
                            "collect: liquidity is 0, liquidity: ", 
                            Utils._uint2str(uint256(liquidity)
                        )
                    )
                )                
            );
        }
    }


    
}