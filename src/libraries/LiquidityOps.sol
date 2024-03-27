

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
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {IDeployer} from "../interfaces/IDeployer.sol";

// import {ModelHelper} from "./ModelHelper.sol";

import {
    LiquidityPosition, 
    LiquidityType, 
    DeployLiquidityParameters,
    AmountsToMint,
    VaultInfo
} from "../Types.sol";



error InvalidTick();
error AboveThreshold();

library LiquidityOps {
   
    function shift(
        address pool,
        address vault,
        address deployer,
        address modelHelper,
        LiquidityPosition[] memory positions
    ) internal returns (
        uint256 currentLiquidityRatio, 
        LiquidityPosition[3] memory newPositions
        // uint256 newFloorPrice
    ) {
        require(positions.length == 3, "invalid positions");
        // Ratio of the anchor's price to market price
        currentLiquidityRatio = IModelHelper(modelHelper).getLiquidityRatio(pool);
        (,,, uint256 anchorToken1Balance) = IModelHelper(modelHelper).getUnderlyingBalances(pool, address(this), LiquidityType.Anchor);
        (,,, uint256 floorToken1Balance) = IModelHelper(modelHelper).getUnderlyingBalances(pool, address(this), LiquidityType.Floor);

        // Uniswap.collect(pool, address(this), positions[1].lowerTick, positions[1].upperTick);

        if (currentLiquidityRatio < 99e16) {
            
            // Shift --> ETH after skim at floor = 
            // ETH before skim at anchor - (liquidity ratio * ETH before skim at anchor)
            uint256 toSkim = anchorToken1Balance - (
                DecimalMath
                .multiplyDecimal(
                    currentLiquidityRatio, 
                    anchorToken1Balance
                )
            );

            if (toSkim > 0) {

                // {
                    uint256 circulatingSupply = IModelHelper(modelHelper)
                    .getCirculatingSupply(
                        pool,
                        vault
                    );

                    if (circulatingSupply > 0) {

                        (,,, uint256 floorNewToken1Balance) = 
                        Underlying.getUnderlyingBalances(pool, address(this), positions[0]);
                        
                        // newFloorPrice = DecimalMath.divideDecimal(
                        //     floorNewToken1Balance,
                        //     circulatingSupply - IModelHelper(modelHelper).getPositionCapacity(pool, vault, newPositions[0])
                        // );
                    

                        // Collect floor liquidity
                        Uniswap.collect(
                            pool, 
                            address(this), 
                            positions[0].lowerTick, 
                            positions[0].upperTick
                        );

                        // Collect anchor liquidity
                        Uniswap.collect(
                            pool, 
                            address(this), 
                            positions[1].lowerTick, 
                            positions[1].upperTick
                        );

                        ERC20(IUniswapV3Pool(pool).token1()).transfer(
                            deployer, 
                            floorToken1Balance + toSkim
                        );
                        
                        newPositions[0] = IDeployer(deployer) 
                        .shiftFloor(
                            pool, 
                            address(this), 
                            Conversions
                            .sqrtPriceX96ToPrice(
                                Conversions
                                .tickToSqrtPriceX96(
                                    positions[0].upperTick
                                ), 
                            18), 
                            positions[0]
                        );

                        positions[0] = newPositions[0];

                        (
                            LiquidityPosition memory anchor, 
                            LiquidityPosition memory discovery
                        ) =
                        shiftPositions(
                            pool, 
                            deployer,
                            positions
                        );

                        newPositions[1] = anchor;
                        newPositions[2] = discovery;

                        IModelHelper(modelHelper)
                        .updatePositions(
                            deployer,
                            newPositions
                        );
                    }
                // }
            } 

        } else {
            revert AboveThreshold();
        }
    }

    function shiftPositions(
        address pool,
        address deployer,
        LiquidityPosition[] memory positions
    ) internal returns (
        LiquidityPosition memory anchor, 
        LiquidityPosition memory discovery
    ) {

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 priceLower = Utils.addBips(Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18), 250);

        // Deploy new anchor position
        anchor = reDeploy(
            pool,
            deployer,
            positions[0].upperTick, 
            Conversions.priceToTick(int256(priceLower), 60), 
            LiquidityType.Anchor
        );

        // Collect discovery liquidity
        Uniswap.collect(
            pool, 
            address(this), 
            positions[2].lowerTick, 
            positions[2].upperTick
        );

        discovery = reDeploy(
            pool,
            deployer, 
            anchor.upperTick, 
            Conversions.priceToTick(int256(priceLower * 5), 60), 
            LiquidityType.Discovery
        );        
    }

    function reDeploy(
        address pool,
        address deployer,
        int24 lowerTick,
        int24 upperTick,
        LiquidityType liquidityType
    ) internal returns (LiquidityPosition memory newPosition) {
        require(upperTick > lowerTick, "invalid ticks");
        
        uint256 balanceToken0 = ERC20(IUniswapV3Pool(pool).token0()).balanceOf(address(this));
        uint256 balanceToken1 = ERC20(IUniswapV3Pool(pool).token1()).balanceOf(address(this));

        uint256 amount0ToDeploy = liquidityType == LiquidityType.Discovery ? 
        balanceToken0 - (balanceToken0 * 25 / 100) :
        balanceToken0;

        uint256 amount1ToDeploy = liquidityType == LiquidityType.Discovery ? 
        0 :
        balanceToken1;

        // ERC20(IUniswapV3Pool(pool).token0()).approve(deployer, amount0ToDeploy);
        // ERC20(IUniswapV3Pool(pool).token1()).approve(deployer, amount1ToDeploy);

        ERC20(IUniswapV3Pool(pool).token0()).transfer(deployer, amount0ToDeploy);
        ERC20(IUniswapV3Pool(pool).token1()).transfer(deployer, amount1ToDeploy);

        newPosition = IDeployer(deployer)
        .doDeployPosition(
            pool, 
            address(this), 
            lowerTick,
            upperTick,
            liquidityType, 
            AmountsToMint({
                amount0: amount0ToDeploy,
                amount1: amount1ToDeploy
            })
        );     
    }

    function getVaultInfo(
        address pool,
        address vault,
        address modelHelper,
        VaultInfo memory vaultInfo,
        LiquidityPosition[] memory positions
    ) internal view 
    returns (
        uint256, 
        uint256, 
        uint256, 
        uint256, 
        uint256, 
        address, 
        address
    ) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        return (
            IModelHelper(modelHelper).getLiquidityRatio(address(pool)),
            IModelHelper(modelHelper).getCirculatingSupply(address(pool), vault),
            Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18),
            IModelHelper(modelHelper).getPositionCapacity(address(pool), vault, positions[1]),
            IModelHelper(modelHelper).getPositionCapacity(address(pool), vault, positions[0]),
            vaultInfo.token0,
            vaultInfo.token1            
        );
    }    
}