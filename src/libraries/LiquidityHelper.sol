

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

import {
    LiquidityPosition, 
    LiquidityType, 
    DeployLiquidityParameters
} from "../Types.sol";

library LiquidityHelper {

    function deployFloor(
        IUniswapV3Pool pool,
        address receiver, 
        uint256 _floorPrice, 
        int24 tickSpacing
        ) internal returns (
            LiquidityPosition memory newPosition,
            LiquidityType liquidityType
        ) {
    
        uint256 balanceToken1 = ERC20(pool.token1()).balanceOf(address(this));
        
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        (int24 lowerTick, int24 upperTick) = Conversions.computeSingleTick(_floorPrice, tickSpacing);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            0,
            (balanceToken1 * 80) / 100 // 80% of WETH
        );

        if (liquidity > 0) {
            Uniswap.mint(
                pool, 
                receiver,
                lowerTick, 
                upperTick, 
                liquidity, 
                LiquidityType.Floor, 
                false
            );
        } else {
            // revert(
            //     string(
            //         abi.encodePacked(
            //                 "deployFloor: liquidity is 0, spot price: ", 
            //                 Utils._uint2str(uint256(sqrtRatioX96)
            //             )
            //         )
            //     )
            // );             
        }

        newPosition = LiquidityPosition({
            lowerTick: lowerTick, 
            upperTick: upperTick, 
            liquidity: liquidity, 
            price: _floorPrice,
            amount0LowerBound: 0,
            amount1UpperBound: 0,
            amount1UpperBoundVirtual: 0
        });

        return (
            newPosition, 
            LiquidityType.Floor
        );
    }

    function deployAnchor(
        IUniswapV3Pool pool,
        address receiver,
        LiquidityPosition memory floorPosition,
        DeployLiquidityParameters memory deployParams
    ) internal returns (
        LiquidityPosition memory newPosition,
        LiquidityType liquidityType
    ) {       
        require(floorPosition.lowerTick != 0, "deployAnchor: invalid floor position");

        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();

        uint256 lowerAnchorPrice = 
        Utils.addBips(
            Conversions.sqrtPriceX96ToPrice(
                sqrtRatioX96, 
                18
            ), 
            (int256(deployParams.bipsBelowSpot) * -1)
        ); 

        uint256 upperAnchorPrice = Utils.addBips(lowerAnchorPrice, int256(deployParams.bips));
        int24 lowerAnchorTick = Conversions.priceToTick(int256(lowerAnchorPrice), deployParams.tickSpacing);

        require(
            lowerAnchorTick >= floorPosition.upperTick, 
            string(
                abi.encodePacked(
                    "deployAnchor: invalid anchor, spot price: ", 
                    Utils._uint2str(floorPosition.price)
                )
            )
        );

        (int24 lowerTick, int24 upperTick) =  
        Conversions
        .computeRangeTicks(
            lowerAnchorPrice, 
            upperAnchorPrice, 
            deployParams.tickSpacing
        );

        uint256 amount0Max = (ERC20(pool.token0()).balanceOf(address(this)) * 15) / 100;
        uint256 amount1Max = ERC20(pool.token1()).balanceOf(address(this));

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount0Max,
            amount1Max
        );

        if (liquidity > 0) {
            Uniswap.mint(pool, receiver, lowerTick, upperTick, liquidity, LiquidityType.Anchor, false);
        } else {
            // revert(
            //     string(
            //         abi.encodePacked(
            //                 "deployAnchor: liquidity is 0, spot price:  ", 
            //                 Utils._uint2str(uint256(sqrtRatioX96)
            //             )
            //         )
            //     )
            // ); 
        }

        newPosition = LiquidityPosition({
            lowerTick: lowerTick, 
            upperTick: upperTick, 
            liquidity: liquidity, 
            price: upperAnchorPrice,
            amount0LowerBound: 0,
            amount1UpperBound: 0,
            amount1UpperBoundVirtual: 0
        });

        return (
            newPosition, 
            LiquidityType.Anchor
        );
    }

    
    function deployDiscovery(
        IUniswapV3Pool pool,
        address receiver,
        LiquidityPosition memory anchorPosition,
        uint256 bips,
        int24 tickSpacing
    ) internal returns (
        LiquidityPosition memory newPosition,
        LiquidityType liquidityType
    ) {    

        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();

        uint256 lowerDiscoveryPrice = Conversions.sqrtPriceX96ToPrice(
            Conversions.tickToSqrtPriceX96(anchorPosition.upperTick), 
            18 // decimals hardcoded for now
        );
        
        lowerDiscoveryPrice = Utils.addBips(lowerDiscoveryPrice, 100);
        uint256 upperDiscoveryPrice = Utils.addBips(lowerDiscoveryPrice, int256(bips));

        (int24 lowerTick, int24 upperTick) = Conversions
        .computeRangeTicks(
            lowerDiscoveryPrice, 
            upperDiscoveryPrice, 
            tickSpacing
        );

        uint256 balanceToken0 = ERC20(pool.token0()).balanceOf(address(this));
        uint256 balanceToken1 = ERC20(pool.token1()).balanceOf(address(this));

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            (balanceToken0 * 30) / 100, // 30% of token0 in Discovery
            balanceToken1
        );

        if (liquidity > 0) {
            Uniswap.mint(pool, receiver, lowerTick, upperTick, liquidity, LiquidityType.Discovery, false);
        } else {
            // revert(
            //     string(
            //         abi.encodePacked(
            //                 "deployDiscovery: liquidity is 0, spot price:  ", 
            //                 Utils._uint2str(uint256(sqrtRatioX96)
            //             )
            //         )
            //     )
            // ); 
        }  

        newPosition = LiquidityPosition({
            lowerTick: lowerTick, 
            upperTick: upperTick, 
            liquidity: liquidity, 
            price: upperDiscoveryPrice,
            amount0LowerBound: 0,
            amount1UpperBound: 0,
            amount1UpperBoundVirtual: 0
        });

        return (
            newPosition, 
            LiquidityType.Discovery
        );
    }

    function shiftFloor(
        IUniswapV3Pool pool,
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

        (uint128 liquidity,,,,) = pool.positions(floorPositionId);

        if (liquidity > 0) {
            Uniswap.burn(
                pool,
                floorPosition.lowerTick,
                floorPosition.upperTick,
                liquidity
            );
        } else {
            revert("shiftFloor: liquidity is 0");
        }

        uint256 balanceAfterShiftFloorToken1 = ERC20(token1).balanceOf(address(this));
        
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        (, int24 newFloorUpperTick) = Conversions.computeSingleTick(newFloorPrice, tickSpacing);

        uint256 amount0Max = 0;
        uint256 amount1Max = balanceAfterShiftFloorToken1;

        uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
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
            // revert(
            //     string(
            //         abi.encodePacked(
            //                 "shiftFloor: liquidity is 0  ", 
            //                 Utils._uint2str(uint256(sqrtRatioX96)
            //             )
            //         )
            //     )
            // ); 
        }
    }

    function shift(
        IUniswapV3Pool pool,
        LiquidityPosition memory anchorPosition,
        uint256 lastLiquidityRatio
    ) internal returns (uint256 currentLiquidityRatio) {

        uint256 THRESHOLD = 200000000 gwei; // 0.2 
        
        currentLiquidityRatio = getLiquidityRatio(pool, anchorPosition);

        int256 deltaLiquidityRatio = int256(currentLiquidityRatio) - int256(lastLiquidityRatio);

        if (deltaLiquidityRatio > 0) {
            // shift
            if (deltaLiquidityRatio >= int256(THRESHOLD)) {
                // do something
            }
        } else if (deltaLiquidityRatio < 0) {
            // slide
            if (deltaLiquidityRatio <= -int256(THRESHOLD)) {
                // do something
            }
        }
    }

    function collect(
        IUniswapV3Pool pool,
        LiquidityPosition memory position
    ) internal {

        bytes32 anchorPositionId = keccak256(
            abi.encodePacked(
                address(this), 
                position.lowerTick, 
                position.upperTick
            )
        );

        (uint128 liquidity,,,,) = pool.positions(anchorPositionId);

        if (liquidity > 0) {
            Uniswap.burn(
                pool,
                position.lowerTick, 
                position.upperTick,
                liquidity
            );
        } else {
        //     revert(
        //         string(
        //             abi.encodePacked(
        //                     "collect: liquidity is 0, liquidity: ", 
        //                     Utils._uint2str(uint256(liquidity)
        //                 )
        //             )
        //         )                
        //     );
        }
    }


    function getAmount1ForLiquidityInFloor(LiquidityPosition memory floorPosition) internal view returns (uint256) {
        
        bytes32 floorPositionId = keccak256(
            abi.encodePacked(
                address(this), 
                floorPosition.lowerTick, 
                floorPosition.upperTick
                )
            );

        uint256 amount1 = LiquidityAmounts
        .getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(floorPosition.lowerTick),
            TickMath.getSqrtRatioAtTick(floorPosition.upperTick),
            floorPosition.liquidity
        );

        return amount1;
    }

    function getAmount1ForLiquidityInPosition(
        IUniswapV3Pool pool,
        LiquidityPosition memory position
        ) internal view returns (uint256) {
        
        // (uint160 sqrtRatioX96,,,,,,) = pool.slot0();

        bytes32 positionId = keccak256(
            abi.encodePacked(
                address(this), 
                position.lowerTick, 
                position.upperTick
                )
            );

        (uint128 liquidity,,,,) = pool.positions(positionId);

        uint256 amount1 = LiquidityAmounts
        .getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(position.lowerTick),
            TickMath.getSqrtRatioAtTick(position.upperTick),
            liquidity
        );
        // (, uint256 amount1) = LiquidityAmounts
        // .getAmountsForLiquidity(
        //     TickMath.getSqrtRatioAtTick(position.upperTick), 
        //     TickMath.getSqrtRatioAtTick(position.lowerTick), 
        //     TickMath.getSqrtRatioAtTick(position.upperTick), 
        //     liquidity
        // );

        return amount1;
    }

    function getLiquidityRatio(
        IUniswapV3Pool pool,
        LiquidityPosition memory anchorPosition
    ) internal view returns (uint256 liquidityRatio) {
            
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();

        uint256 anchorUpperPrice = Conversions.sqrtPriceX96ToPrice(
                Conversions.tickToSqrtPriceX96(anchorPosition.upperTick),
            18);

        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);
        liquidityRatio = DecimalMath.divideDecimal(anchorUpperPrice, spotPrice);
    }

    function getFloorCapacity(LiquidityPosition memory floorPosition) internal view returns (uint256) {
    
        uint256 token1InFloor = getAmount1ForLiquidityInFloor(floorPosition);
        uint256 capacity = token1InFloor / floorPosition.price;
        
        return capacity;
    }    
}