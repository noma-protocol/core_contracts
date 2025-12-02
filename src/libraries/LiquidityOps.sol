// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from 'v3-core/libraries/TickMath.sol';
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Uniswap} from "./Uniswap.sol";
import {Utils} from "./Utils.sol";
import {Conversions} from "./Conversions.sol";
import {DecimalMath} from "./DecimalMath.sol";
import {Underlying} from "./Underlying.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {IDeployer} from "../interfaces/IDeployer.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    LiquidityPosition, 
    LiquidityType, 
    AmountsToMint,
    ShiftParameters,
    ProtocolAddresses,
    PreShiftParameters,
    ProtocolParameters,
    LiquidityInternalPars
} from "../types/Types.sol";

/**
 * @title IAdaptiveSupply
 * @notice Interface for the AdaptiveSupply contract.
 */
interface IAdaptiveSupply {
    function computeMintAmount(
        uint256 deltaSupply,
        uint256 timeElapsed,
        uint256 spotPrice,
        uint256 imv
    ) external pure returns (uint256 mintAmount);
}

/**
 * @title LiquidityOps
 * @notice Library for managing liquidity positions in a Uniswap V3 pool.
 */
library LiquidityOps {
    using SafeERC20 for IERC20;

    error InvalidTick();
    error AboveThreshold();
    error BelowThreshold();
    error PositionsLength();
    error NoLiquidity();
    error MintAmount();
    error BalanceToken0();
    error OnlyNotEmptyPositions();

    /**
     * @notice Shifts liquidity positions based on the current liquidity ratio.
     * @param addresses Protocol addresses.
     * @param positions Current liquidity positions.
     * @return currentLiquidityRatio The current liquidity ratio.
     * @return newPositions The new liquidity positions after shifting.
     */
    function shift(
        ProtocolAddresses memory addresses,
        LiquidityPosition[3] memory positions
    ) internal 
    returns (
        uint256 currentLiquidityRatio,
        LiquidityPosition[3] memory newPositions
    ) {
        if (positions.length != 3) {
            revert PositionsLength();
        }

        // Ratio of the anchor's price to market price
        currentLiquidityRatio = IModelHelper(addresses.modelHelper)
        .getLiquidityRatio(addresses.pool, addresses.vault);
        
        (
            uint256 circulatingSupply, 
            uint256 anchorToken1Balance, 
            uint256 discoveryToken1Balance, 
            uint256 discoveryToken0Balance
        ) = getVaultData(addresses);

        if (
            currentLiquidityRatio <= IVault(addresses.vault).getProtocolParameters().shiftRatio
        ) {
            
            // Shift --> ETH after skim at floor = 
            // ETH before skim at anchor - (liquidity ratio * ETH before skim at anchor)
            uint256 toSkim = (anchorToken1Balance + discoveryToken1Balance) - (
                DecimalMath
                .multiplyDecimal(
                    currentLiquidityRatio, 
                    (anchorToken1Balance + discoveryToken1Balance)
                )
            );

            if (circulatingSupply > 0) {
            
                (,,, uint256 floorToken1Balance) = IModelHelper(addresses.modelHelper)
                .getUnderlyingBalances(
                    addresses.pool, 
                    addresses.vault, 
                    LiquidityType.Floor
                );

                uint256 anchorCapacity = IModelHelper(addresses.modelHelper)
                .getPositionCapacity(
                    addresses.pool, 
                    addresses.vault, 
                    positions[1],
                    LiquidityType.Anchor
                );

                newPositions = preShiftPositions(
                    PreShiftParameters({
                        addresses: addresses,
                        toSkim: toSkim,
                        circulatingSupply : circulatingSupply,
                        anchorCapacity: anchorCapacity,
                        floorToken1Balance: floorToken1Balance,
                        anchorToken1Balance: anchorToken1Balance,
                        discoveryToken1Balance: discoveryToken1Balance,
                        discoveryToken0Balance: discoveryToken0Balance
                    }),
                    positions
                );
                
                IVault(addresses.vault)
                .updatePositions(
                    newPositions
                ); 

                return (currentLiquidityRatio, newPositions);
            }

        } else {
            revert AboveThreshold();
        }
    }

    /**
     * @notice Prepares the positions for shifting.
     * @param params Pre-shift parameters.
     * @param _positions Current liquidity positions.
     * @return newPositions The new liquidity positions after pre-shift.
     */
    function preShiftPositions(
        PreShiftParameters memory params,
        LiquidityPosition[3] memory _positions
    ) internal returns (LiquidityPosition[3] memory newPositions) {

        address deployer = params.addresses.deployer;

        uint256 newFloorPrice = IDeployer(deployer)
                .computeNewFloorPrice(
                    params.toSkim,
                    params.floorToken1Balance,
                    params.circulatingSupply,
                    _positions
                );

        (newPositions) =
        shiftPositions(
            params.addresses,
            ShiftParameters({
                pool: params.addresses.pool,
                deployer: params.addresses.deployer,
                toSkim: params.toSkim,
                newFloorPrice: newFloorPrice,
                modelHelper: params.addresses.modelHelper,
                adaptiveSupplyController: params.addresses.adaptiveSupplyController,
                floorToken1Balance: params.floorToken1Balance,
                anchorToken1Balance: params.anchorToken1Balance,
                discoveryToken1Balance: params.discoveryToken1Balance,
                discoveryToken0Balance: params.discoveryToken0Balance,
                positions: _positions
            })
        );
    }

    /**
     * @notice Shifts the liquidity positions.
     * @param addresses Protocol addresses.
     * @param params Shift parameters.
     * @return newPositions The new liquidity positions after shifting.
     */
    function shiftPositions(
        ProtocolAddresses memory addresses,
        ShiftParameters memory params
    ) internal returns (
        LiquidityPosition[3] memory newPositions
    ) {
        if (params.positions[0].liquidity > 0) {

            (
                uint256 feesPosition0Token0,
                uint256 feesPosition0Token1, 
                uint256 feesPosition1Token0, 
                uint256 feesPosition1Token1
             ) = _calculateFees(addresses.vault, params.pool, params.positions);

            IVault(addresses.vault).setFees(
                feesPosition0Token0, 
                feesPosition0Token1
            );

            IVault(addresses.vault).setFees(
                feesPosition1Token0, 
                feesPosition1Token1
            );
            
            // Collect floor liquidity
            _collectFees(params.positions, addresses, 0);

            // Collect discovery liquidity
            _collectFees(params.positions, addresses, 2);

            // Collect anchor liquidity
            _collectFees(params.positions, addresses, 1);


            if (params.floorToken1Balance + params.toSkim > params.floorToken1Balance) {
                IERC20(
                    IUniswapV3Pool(params.pool).token1()
                ).safeTransfer(
                    params.deployer, 
                    params.floorToken1Balance + params.toSkim
                );
            }

            newPositions = _shiftPositions(
                addresses,
                params
            );
 
        } else {
            revert("shiftPositions: no liquidity in Floor");
        }
    }
    
    /**
     * @notice Slides liquidity positions based on the current liquidity ratio.
     * @param addresses Protocol addresses.
     * @param positions Current liquidity positions.
     * @return newPositions The new liquidity positions after sliding.
     */
    function slide(
        ProtocolAddresses memory addresses,
        LiquidityPosition[3] memory positions
    ) internal 
    returns (
        LiquidityPosition[3] memory newPositions
    ) {
        if (positions.length != 3) {
            revert PositionsLength();
        }
        (, uint256 anchorToken1Balance,, ) = getVaultData(addresses);

        if (
            IModelHelper(addresses.modelHelper).getLiquidityRatio(addresses.pool, addresses.vault) >= 
            IVault(addresses.vault).getProtocolParameters().slideRatio 
        ) {
            
            (
                uint256 feesPosition0Token0,
                uint256 feesPosition0Token1, 
                uint256 feesPosition1Token0, 
                uint256 feesPosition1Token1
            ) = _calculateFees(
                addresses.vault, 
                addresses.pool, 
                positions
            );

            IVault(addresses.vault).setFees(
                feesPosition0Token0, 
                feesPosition0Token1
            );

            IVault(addresses.vault).setFees(
                feesPosition1Token0, 
                feesPosition1Token1
            );

            // Collect liquidity
            _collectFees(positions, addresses, 1);
            _collectFees(positions, addresses, 2);


            newPositions = _slidePositions(
                addresses,
                positions,
                anchorToken1Balance
            );

            // restore floor
            newPositions[0] = positions[0];

            IVault(addresses.vault)
            .updatePositions(
                newPositions
            );    

        } else {
            revert BelowThreshold();
        }  
    }

    /**
     * @notice Internal function to shift liquidity positions.
     * @param addresses Protocol addresses.
     * @param params Shift parameters.
     * @return newPositions The new liquidity positions after shifting.
     */
    function _shiftPositions(
        ProtocolAddresses memory addresses,
        ShiftParameters memory params
    ) internal returns (LiquidityPosition[3] memory newPositions) {

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(params.pool).slot0();
        uint8 decimals = IERC20Metadata(address(IUniswapV3Pool(params.pool).token0())).decimals();

        newPositions[0] = IDeployer(params.deployer) 
        .shiftFloor(
            params.pool, 
            addresses.vault, 
            Conversions
            .sqrtPriceX96ToPrice(
                Conversions
                .tickToSqrtPriceX96(
                    params.positions[0].upperTick
                ), 
            decimals), 
            params.newFloorPrice,
            params.floorToken1Balance + params.toSkim,
            params.floorToken1Balance,
            params.positions[0]
        );

        // Deploy new anchor position
        newPositions[1] = reDeploy(
            ProtocolAddresses({
                pool: params.pool,
                modelHelper: addresses.modelHelper,
                vault: addresses.vault,
                deployer: addresses.deployer,
                presaleContract: addresses.presaleContract,
                adaptiveSupplyController: addresses.adaptiveSupplyController
            }),
            LiquidityInternalPars({
                lowerTick: newPositions[0].upperTick,
                upperTick: Utils.addBipsToTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                    IVault(addresses.vault)
                    .getProtocolParameters().shiftAnchorUpperBips,
                    decimals,
                    params.positions[0].tickSpacing
                ),
                amount1ToDeploy: (params.anchorToken1Balance + params.discoveryToken1Balance) - params.toSkim,
                liquidityType: LiquidityType.Anchor
            }),
            true
        );

        newPositions[2] = reDeploy(
            ProtocolAddresses({
                pool: params.pool,
                modelHelper: addresses.modelHelper,
                vault: addresses.vault,
                deployer: addresses.deployer,
                presaleContract: addresses.presaleContract,
                adaptiveSupplyController: addresses.adaptiveSupplyController
            }),
            LiquidityInternalPars({
                lowerTick: newPositions[1].upperTick + params.positions[0].tickSpacing,
                upperTick: Utils.addBipsToTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                    IVault(addresses.vault)
                    .getProtocolParameters().discoveryBips,
                    decimals,
                    params.positions[0].tickSpacing
                ),
                amount1ToDeploy: 0,
                liquidityType: LiquidityType.Discovery
            }),
            true
        );       
    }

    /**
     * @notice Internal function to slide liquidity positions.
     * @param addresses Protocol addresses.
     * @param positions Current liquidity positions.
     * @param anchorToken1Balance The balance of token1 in the anchor position.
     * @return newPositions The new liquidity positions after sliding.
     */
    function _slidePositions(
        ProtocolAddresses memory addresses,
        LiquidityPosition[3] memory positions,
        uint256 anchorToken1Balance
    ) internal returns (LiquidityPosition[3] memory newPositions) {

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(addresses.pool).slot0();

        //Slide anchor position
        newPositions[1] = reDeploy(
            addresses,
            LiquidityInternalPars({
                lowerTick: positions[0].upperTick,
                upperTick: Utils.addBipsToTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                    IVault(addresses.vault).getProtocolParameters()
                    .slideAnchorUpperBips,
                    IERC20Metadata(address(IUniswapV3Pool(addresses.pool).token0())).decimals(),
                    positions[0].tickSpacing
                ),
                amount1ToDeploy: anchorToken1Balance,
                liquidityType: LiquidityType.Anchor
            }),
            false
        );

        newPositions[2] = reDeploy(
            ProtocolAddresses({
                pool: addresses.pool,
                modelHelper: addresses.modelHelper,
                vault: addresses.vault,
                deployer: addresses.deployer,
                presaleContract: addresses.presaleContract,
                adaptiveSupplyController: addresses.adaptiveSupplyController
            }),
            LiquidityInternalPars({
                lowerTick: newPositions[1].upperTick + positions[0].tickSpacing,
                upperTick: Utils.addBipsToTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                    IVault(addresses.vault).getProtocolParameters()
                    .discoveryBips,
                    IERC20Metadata(address(IUniswapV3Pool(addresses.pool).token0())).decimals(),
                    positions[0].tickSpacing
                ),
                amount1ToDeploy: 0,
                liquidityType: LiquidityType.Discovery
            }),
            false
        );    
    }

    /**
     * @notice Redeploys a liquidity position.
     * @param addresses Protocol addresses.
     * @param params Liquidity internal parameters.
     * @param isShift Whether the operation is a shift.
     * @return newPosition The new liquidity position after redeployment.
     */
    function reDeploy(
        ProtocolAddresses memory addresses,
        LiquidityInternalPars memory params,
        bool isShift
    ) internal returns (LiquidityPosition memory newPosition) {
        if (params.upperTick <= params.lowerTick) {
            revert InvalidTick();
        }
        
        uint256 balanceToken0 = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).balanceOf(addresses.vault);
        uint256 token0Allowance = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).allowance(addresses.vault, addresses.deployer);
        uint256 token1Allowance = IERC20Metadata(IUniswapV3Pool(addresses.pool).token1()).allowance(addresses.vault, addresses.deployer);

        if (token0Allowance != type(uint256).max) {
            IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).approve(addresses.deployer, type(uint256).max);
        }

        if (token1Allowance != type(uint256).max) {
            IERC20Metadata(IUniswapV3Pool(addresses.pool).token1()).approve(addresses.deployer, type(uint256).max);
        }

        if (params.liquidityType == LiquidityType.Discovery) {

            uint256 circulatingSupply = IModelHelper(addresses.modelHelper)
            .getCirculatingSupply(
                addresses.pool,
                addresses.vault
            );        

            uint256 totalSupply = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).totalSupply();        
            
            adjustSupply(
                balanceToken0,
                circulatingSupply,
                totalSupply,
                isShift,
                addresses
            );
        }
        
        newPosition = IDeployer(addresses.deployer)
        .deployPosition(
            addresses.pool, 
            addresses.vault, 
            params.lowerTick,
            params.upperTick,
            params.liquidityType, 
            AmountsToMint({
                amount0: balanceToken0,
                amount1: params.liquidityType == LiquidityType.Anchor ? params.amount1ToDeploy : 1
            })
        );     
    }
    
    function adjustSupply(
        uint256 balanceToken0,
        uint256 circulatingSupply,
        uint256 totalSupply,
        bool isShift,
        ProtocolAddresses memory addresses
    ) internal {
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(addresses.pool).slot0();

        if (balanceToken0 < circulatingSupply / IVault(addresses.vault).getProtocolParameters().lowBalanceThresholdFactor) {
            if (isShift) {
                
                // Mint unbacked supply
                (uint256 mintAmount) = IAdaptiveSupply(
                    addresses.adaptiveSupplyController
                ).computeMintAmount(
                    totalSupply,
                    IVault(addresses.vault).getTimeSinceLastMint() > 0 ? 
                    IVault(addresses.vault).getTimeSinceLastMint() : 
                    1,
                    Conversions.sqrtPriceX96ToPrice(
                        sqrtRatioX96,
                        18
                    ),
                    IModelHelper(addresses.modelHelper).getIntrinsicMinimumValue(addresses.vault)
                );

                if (mintAmount == 0 || mintAmount > totalSupply) {
                    // Fallback to minting a % of circulating supply
                    mintAmount = circulatingSupply / IVault(addresses.vault).getProtocolParameters().lowBalanceThresholdFactor;
                }

                IVault(addresses.vault)
                .mintTokens(
                    addresses.vault,
                    mintAmount
                );
            }
        }
    
        if (balanceToken0 >= circulatingSupply / IVault(addresses.vault).getProtocolParameters().highBalanceThresholdFactor) {
            if (!isShift) {

                IVault(addresses.vault)
                .burnTokens(
                    balanceToken0
                );

                IVault(addresses.vault)
                .mintTokens(
                    addresses.vault,
                    circulatingSupply / IVault(addresses.vault).getProtocolParameters().highBalanceThresholdFactor
                );   
            }                
        }

        // check balance after minting or burning
        balanceToken0 = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).balanceOf(addresses.vault);
        
        if (balanceToken0 == 0) {
            // Fallback to minting a % of circulating supply
            IVault(addresses.vault)
            .mintTokens(
                addresses.vault,
                circulatingSupply / IVault(addresses.vault).getProtocolParameters().lowBalanceThresholdFactor
            );

            balanceToken0 = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).balanceOf(addresses.vault);
        }
    }
    
    /**
     * @notice Retrieves vault data including circulating supply and token balances.
     * @param addresses Protocol addresses.
     * @return circulatingSupply The circulating supply of the vault.
     * @return anchorToken1Balance The balance of token1 in the anchor position.
     * @return discoveryToken1Balance The balance of token1 in the discovery position.
     * @return discoveryToken0Balance The balance of token0 in the discovery position.
     */
    function getVaultData(ProtocolAddresses memory addresses) internal view returns (uint256, uint256, uint256, uint256) {
        (,,, uint256 anchorToken1Balance) = IModelHelper(addresses.modelHelper)
        .getUnderlyingBalances(
            addresses.pool, 
            addresses.vault, 
            LiquidityType.Anchor
        );

        (,, uint256 discoveryToken0Balance, uint256 discoveryToken1Balance) = IModelHelper(addresses.modelHelper)
        .getUnderlyingBalances(
            addresses.pool, 
            addresses.vault, 
            LiquidityType.Discovery
        );

        uint256 circulatingSupply = IModelHelper(addresses.modelHelper)
        .getCirculatingSupply(
            addresses.pool,
            addresses.vault
        );
        
        return (circulatingSupply, anchorToken1Balance, discoveryToken1Balance, discoveryToken0Balance);
    }

    /**
     * @notice Collect fees from underlying liquidity position
     * @param positions Current liquidity positions.
     * @param addresses Protocol addresses.
    */
    function _collectFees(
        LiquidityPosition[3] memory positions, 
        ProtocolAddresses memory addresses, 
        uint8 idx
    ) internal {
            Uniswap.collect(
                addresses.pool, 
                addresses.vault, 
                positions[idx].lowerTick, 
                positions[idx].upperTick
            ); 
    }

    /**
     * @notice Calculates the fees earned by the liquidity positions.
     * @param pool The Uniswap V3 pool address.
     * @param positions The liquidity positions.
     * @return feesPosition0Token0 The fees earned by position 0 in token0.
     * @return feesPosition0Token1 The fees earned by position 0 in token1.
     * @return feesPosition1Token0 The fees earned by position 1 in token0.
     * @return feesPosition1Token1 The fees earned by position 1 in token1.
     */
    function _calculateFees(
        address vault,
        address pool, 
        LiquidityPosition[3] memory positions
    ) internal view returns (
        uint256 feesPosition0Token0, 
        uint256 feesPosition0Token1, 
        uint256 feesPosition1Token0, 
        uint256 feesPosition1Token1
    ) {

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        feesPosition0Token0 = Underlying
        .computeFeesEarned(
            positions[0], 
            vault, 
            pool, 
            true, 
            TickMath.getTickAtSqrtRatio(sqrtRatioX96)
        );

        feesPosition1Token0 = Underlying
        .computeFeesEarned(
            positions[1], 
            vault, 
            pool, 
            true, 
            TickMath.getTickAtSqrtRatio(sqrtRatioX96)
        );

        feesPosition0Token1 = Underlying
        .computeFeesEarned(
            positions[0], 
            vault, 
            pool, 
            false, 
            TickMath.getTickAtSqrtRatio(sqrtRatioX96)
        );

        feesPosition1Token1 = Underlying
        .computeFeesEarned(
            positions[1], 
            vault, 
            pool, 
            false, 
            TickMath.getTickAtSqrtRatio(sqrtRatioX96)
        );

        return (feesPosition0Token0, feesPosition0Token1, feesPosition1Token0, feesPosition1Token1);
    }

}