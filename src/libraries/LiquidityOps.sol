

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
        LiquidityPosition[3] memory positions
    ) internal returns (
        uint256 currentLiquidityRatio, 
        LiquidityPosition[3] memory newPositions
        // uint256 newFloorPrice
    ) {
        require(positions.length == 3, "invalid positions");

        // Ratio of the anchor's price to market price
        currentLiquidityRatio = IModelHelper(modelHelper).getLiquidityRatio(pool);
        
        (,,, uint256 anchorToken1Balance) = IModelHelper(modelHelper).getUnderlyingBalances(pool, address(this), LiquidityType.Anchor);
        (,,, uint256 discoveryToken1Balance) = IModelHelper(modelHelper).getUnderlyingBalances(pool, address(this), LiquidityType.Discovery);

        // Uniswap.collect(pool, address(this), positions[1].lowerTick, positions[1].upperTick);
        uint256 circulatingSupply = IModelHelper(modelHelper)
        .getCirculatingSupply(
            pool,
            vault
        );

        if (currentLiquidityRatio <= 90e16) {
            
            // Shift --> ETH after skim at floor = 
            // ETH before skim at anchor - (liquidity ratio * ETH before skim at anchor)
            uint256 toSkim = (anchorToken1Balance + discoveryToken1Balance) - (
                DecimalMath
                .multiplyDecimal(
                    currentLiquidityRatio, 
                    (anchorToken1Balance + discoveryToken1Balance)
                )
            );

            if (toSkim >= (anchorToken1Balance * 2 / 1000)) {


                if (circulatingSupply > 0) {
                
                    // Collect anchor liquidity
                    Uniswap.collect(
                        pool, 
                        address(this), 
                        positions[1].lowerTick, 
                        positions[1].upperTick
                    );

                    uint256 newFloorPrice = 
                    computeNewFloorPrice(
                        pool, 
                        vault, 
                        toSkim, 
                        circulatingSupply, 
                        positions, 
                        newPositions, 
                        modelHelper
                    );
                    
                    (newPositions) =
                    shiftPositions(
                        pool, 
                        deployer,
                        toSkim,
                        newFloorPrice,
                        modelHelper,
                        anchorToken1Balance - toSkim,
                        discoveryToken1Balance,
                        positions
                    );

                    IModelHelper(modelHelper)
                    .updatePositions(
                        newPositions
                    );
                }

            } else {

                revert(
                    string(
                        abi.encodePacked(
                            "Nothing to skim : ", 
                            Utils._uint2str(uint256(toSkim))
                        )
                    )
                );
            
            }
        } else {
            revert AboveThreshold();
        }
    }

    function shiftPositions(
        address pool,
        address deployer,
        uint256 toSkim,
        uint256 newFloorPrice,
        address modelHelper,
        uint256 anchorToken1Balance,
        uint256 discoveryToken1Balance,
        LiquidityPosition[3] memory positions
    ) internal returns (
        LiquidityPosition[3] memory newPositions
    ) {

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        uint256 priceLower = Utils
        .addBips(
            Conversions
            .sqrtPriceX96ToPrice(sqrtRatioX96, 18), 
            250
        );

        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);

        (,,, uint256 floorToken1Balance) = IModelHelper(modelHelper)
        .getUnderlyingBalances(
            pool, 
            address(this), 
            LiquidityType.Floor
        );
       
        if (positions[0].liquidity > 0) {
            // Collect floor liquidity
            Uniswap.collect(
                pool, 
                address(this), 
                positions[0].lowerTick, 
                positions[0].upperTick
            );

            // TODO: use transferFrom
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
                newFloorPrice,
                positions[0]
            );

            // Collect discovery liquidity
            Uniswap.collect(
                pool, 
                address(this), 
                positions[2].lowerTick, 
                positions[2].upperTick
            );

            // Deploy new anchor position
            newPositions[1] = reDeploy(
                pool,
                deployer,
                Conversions.priceToTick(
                    int256(
                        Utils.addBips(
                            Conversions.sqrtPriceX96ToPrice(
                                Conversions.tickToSqrtPriceX96(
                                    newPositions[0].upperTick
                                    ),
                                18), 
                            0)
                    ), 
                60),
                Conversions.priceToTick(
                    int256(
                        spotPrice
                    ), 
                60),             
                anchorToken1Balance + discoveryToken1Balance, 
                LiquidityType.Anchor
            );

            newPositions[2] = reDeploy(
                pool,
                deployer, 
                //newPositions[1].upperTick,
                Utils.nearestUsableTick(
                    Utils.addBipsToTick(newPositions[1].upperTick, 500)
                ),
                Conversions.priceToTick(
                    int256(
                        Utils
                        .addBips(
                            Conversions
                            .sqrtPriceX96ToPrice(sqrtRatioX96, 18), 
                            250
                        ) * 3
                    ), 
                60), 
                0,
                LiquidityType.Discovery 
            );   
            
            require(newPositions[2].liquidity > 0, "shiftPositions: no liquidity in Discovery");

        } else {
            revert("shiftPositions: no liquidity in Floor");
        }

    }

    function reDeploy(
        address pool,
        address deployer,
        int24 lowerTick,
        int24 upperTick,
        uint256 amount1ToDeploy,
        LiquidityType liquidityType
    ) internal returns (LiquidityPosition memory newPosition) {
        require(upperTick > lowerTick, "invalid ticks");
        
        uint256 balanceToken0 = ERC20(IUniswapV3Pool(pool).token0()).balanceOf(address(this));
        // uint256 balanceToken1 = ERC20(IUniswapV3Pool(pool).token1()).balanceOf(address(this));

        uint256 amount0ToDeploy = liquidityType == LiquidityType.Discovery ? 
        balanceToken0 - (balanceToken0 * 25 / 100) : balanceToken0;

        ERC20(IUniswapV3Pool(pool).token0()).approve(deployer, balanceToken0);
        ERC20(IUniswapV3Pool(pool).token1()).approve(deployer, amount1ToDeploy > 0 ? amount1ToDeploy : 1);

        newPosition = IDeployer(deployer)
        .doDeployPosition(
            pool, 
            address(this), 
            lowerTick,
            upperTick,
            liquidityType, 
            AmountsToMint({
                amount0: balanceToken0,
                amount1: liquidityType == LiquidityType.Anchor ? amount1ToDeploy : 1
            })
        );     
    }

    function computeNewFloorPrice(
        address pool,
        address vault,
        uint256 toSkim,
        uint256 circulatingSupply,
        LiquidityPosition[3] memory positions,
        LiquidityPosition[3] memory newPositions,
        address modelHelper
    ) internal view returns (uint256 newFloorPrice) {

        (,,, uint256 floorNewToken1Balance) = 
        Underlying.getUnderlyingBalances(pool, address(this), positions[0]);
        
        newFloorPrice = DecimalMath.divideDecimal(
            floorNewToken1Balance + toSkim,
            circulatingSupply - IModelHelper(modelHelper)
            .getPositionCapacity(
                pool, 
                vault, 
                newPositions[0]
            )
        );

        if (newFloorPrice <= 1e18) {
            return 0;
        }
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