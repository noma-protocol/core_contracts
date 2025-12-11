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
import { LiquidityDeployer } from "../libraries/LiquidityDeployer.sol";

import {
    LiquidityPosition, 
    LiquidityType, 
    AmountsToMint,
    ShiftParameters,
    ProtocolAddresses,
    PreShiftParameters,
    ProtocolParameters,
    LiquidityInternalPars,
    DeployLiquidityParams
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

error InvalidBalance();

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
    error ZeroAnchorBalance();
    error InvalidTresholds();

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
                        toSkim: 0, // toSkim
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
     * @param positions Current liquidity positions.
     * @return newPositions The new liquidity positions after pre-shift.
     */
    function preShiftPositions(
        PreShiftParameters memory params,
        LiquidityPosition[3] memory positions
    ) internal returns (LiquidityPosition[3] memory newPositions) {

        address deployer = params.addresses.deployer;
        uint256 skimRatio = IVault(params.addresses.vault).getProtocolParameters().skimRatio;

        uint256 newFloorPrice = Utils
        .computeNewFloorPrice(
            params.floorToken1Balance + (params.anchorToken1Balance / skimRatio) + params.discoveryToken1Balance,
            params.circulatingSupply
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
                positions: positions
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

            newPositions = 
            _shiftPositions(
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
    ) internal returns (LiquidityPosition[3] memory newPositions) {
        if (positions.length != 3) {
            revert PositionsLength();
        }

        uint256 liquidityRatio = IModelHelper(addresses.modelHelper)
            .getLiquidityRatio(addresses.pool, addresses.vault);

        uint256 slideRatio = IVault(addresses.vault)
            .getProtocolParameters()
            .slideRatio;

        if (liquidityRatio < slideRatio) {
            revert BelowThreshold();
        }

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

        // Check balance after collecting fees
        (, uint256 anchorToken1Balance,, ) = getVaultData(addresses);

        if (anchorToken1Balance == 0) {
            anchorToken1Balance = IERC20Metadata(
                address(IUniswapV3Pool(addresses.pool).token1())
            ).balanceOf(address(this));
        }

        if (anchorToken1Balance == 0) {
            revert InvalidBalance();
        }

        newPositions = _slidePositions(
            addresses,
            positions,
            anchorToken1Balance - feesPosition1Token1
        );

        // restore floor
        newPositions[0] = positions[0];

        IVault(addresses.vault).updatePositions(newPositions);
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

        uint256 skimRatio = IVault(addresses.vault).getProtocolParameters().skimRatio;

        newPositions[0] = LiquidityDeployer
        .shiftFloor(
            params.pool, 
            addresses.vault, 
            params.newFloorPrice,
            params.floorToken1Balance + (params.anchorToken1Balance / skimRatio) + params.discoveryToken1Balance,
            params.positions[0]
        );
        
        int24 upperTick = Utils
        .addBipsToTick(
            TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
            IVault(addresses.vault).getProtocolParameters().shiftAnchorUpperBips,
            decimals,
            params.positions[0].tickSpacing
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
                upperTick: upperTick,
                amount1ToDeploy: params.anchorToken1Balance / skimRatio,
                liquidityType: LiquidityType.Anchor
            }),
            true
        );

        upperTick = Utils
        .addBipsToTick(
            TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
            IVault(addresses.vault)
            .getProtocolParameters().discoveryBips,
            decimals,
            params.positions[0].tickSpacing
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
                upperTick: upperTick,
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
     * @param amount1ToDeploy The amount of token1 to deploy in the anchor position.
     * @return newPositions The new liquidity positions after sliding.
     */
    function _slidePositions(
        ProtocolAddresses memory addresses,
        LiquidityPosition[3] memory positions,
        uint256 amount1ToDeploy
    ) internal returns (LiquidityPosition[3] memory newPositions) {

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(addresses.pool).slot0();

        int24 upperTick =  Utils
        .addBipsToTick(
            TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
            IVault(addresses.vault).getProtocolParameters().slideAnchorUpperBips,
            IERC20Metadata(address(IUniswapV3Pool(addresses.pool).token0())).decimals(),
            positions[0].tickSpacing
        );

        //Slide anchor position
        newPositions[1] = reDeploy(
            addresses,
            LiquidityInternalPars({
                lowerTick: positions[0].upperTick,
                upperTick: upperTick,
                amount1ToDeploy: amount1ToDeploy,
                liquidityType: LiquidityType.Anchor
            }),
            false
        );

        upperTick = Utils
        .addBipsToTick(
            TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
            IVault(addresses.vault).getProtocolParameters()
            .discoveryBips,
            IERC20Metadata(address(IUniswapV3Pool(addresses.pool).token0())).decimals(),
            positions[0].tickSpacing
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
                upperTick: upperTick,
                amount1ToDeploy: 0,
                liquidityType: LiquidityType.Discovery
            }),
            false
        );  

        if (newPositions[1].liquidity == 0 || newPositions[2].liquidity == 0) {
            revert NoLiquidity();
        }
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
        uint256 balanceToken0 = 0;

        if (isShift) {
            balanceToken0 = refreshBalance0(addresses);
        } else {
        (,, balanceToken0,) = IModelHelper(addresses.modelHelper)
            .getUnderlyingBalances(
                addresses.pool, 
                address(this), 
                LiquidityType.Discovery
            );
        }

        if (params.liquidityType == LiquidityType.Discovery) {

            uint256 totalSupply = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).totalSupply();        
            
            adjustSupply(
                balanceToken0,
                IModelHelper(addresses.modelHelper)
                .getCirculatingSupply(
                    addresses.pool,
                    addresses.vault,
                    false
                ),
                totalSupply,
                isShift,
                addresses
            );
        }

        if (isShift) {
            balanceToken0 = refreshBalance0(addresses);
        } else {
            (,, balanceToken0,) = IModelHelper(addresses.modelHelper)
            .getUnderlyingBalances(
                addresses.pool,
                address(this),
                LiquidityType.Anchor
            );
        }
        if (balanceToken0 == 0) {
            balanceToken0 = refreshBalance0(addresses);
        }

        uint256 amount0ToDeploy;
        if (
            params.liquidityType == LiquidityType.Anchor
        ) {        
            amount0ToDeploy = LiquidityDeployer
            .computeAmount0ForAmount1(
                LiquidityPosition({
                    lowerTick: params.lowerTick,
                    upperTick: params.upperTick,
                    liquidity: 0,
                    price: 0,
                    tickSpacing: 0,
                    liquidityType: params.liquidityType
                }), 
                params.amount1ToDeploy
            );
        }

        newPosition = LiquidityDeployer
        .deployPosition(
            DeployLiquidityParams({
                pool: addresses.pool, 
                receiver: addresses.vault, 
                bips: 0,
                lowerTick: params.lowerTick,
                upperTick: params.upperTick,
                liquidityType: params.liquidityType, 
                tickSpacing: 60,
                amounts: AmountsToMint({
                    amount0: params.liquidityType == LiquidityType.Anchor ? amount0ToDeploy : balanceToken0,
                    amount1: params.amount1ToDeploy
                })
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
        IVault vault = IVault(addresses.vault);
        ProtocolParameters memory params = vault.getProtocolParameters();

        // Optional safety check
        if (params.lowBalanceThresholdFactor >= 100 && params.highBalanceThresholdFactor >= 100) revert InvalidTresholds();

        // Thresholds as percentages of circulating supply
        uint256 lowBalanceThreshold  = (circulatingSupply * params.lowBalanceThresholdFactor)  / 100;
        uint256 highBalanceThreshold = (circulatingSupply * params.highBalanceThresholdFactor) / 100;

        // Read current price from the pool
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(addresses.pool).slot0();

        uint256 mintAmount = computeMintAmount(addresses, totalSupply, sqrtRatioX96);

        // -------------------------------------------------------------------------
        // MINT PATH (SHIFT)
        // -------------------------------------------------------------------------
        if (balanceToken0 < lowBalanceThreshold && isShift) {
            // Fallback: mint a % of circulating supply if computed amount unusable
            if (mintAmount == 0 || mintAmount > totalSupply) {
                mintAmount = lowBalanceThreshold; // i.e. lowPct% of circulating
            }

            vault.mintTokens(addresses.vault, mintAmount);
        }

        // -------------------------------------------------------------------------
        // BURN PATH (SLIDE)
        // -------------------------------------------------------------------------
        uint256 refreshedBalance0 = refreshBalance0(addresses);

        bool hasExcessBalance =
            balanceToken0 > highBalanceThreshold ||
            refreshedBalance0 > lowBalanceThreshold;

        if (hasExcessBalance && !isShift) {
            uint256 currentBalance0 =
                balanceToken0 > 0 ? balanceToken0 : refreshedBalance0;

            // backedBalance0 = mintAmount * lowPct / 100
            uint256 backedBalance0 =
                (mintAmount * params.lowBalanceThresholdFactor) / 100;

            if (currentBalance0 > backedBalance0) {
                uint256 burnAmount = currentBalance0 - backedBalance0;
                vault.burnTokens(burnAmount);
            }
        }

    }
    
    function refreshBalance0(ProtocolAddresses memory addresses) internal returns (uint256) {
        return IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).balanceOf(addresses.vault);
    }

    function computeMintAmount(
        ProtocolAddresses memory addresses,
        uint256 totalSupply,
        uint160 sqrtRatioX96
    ) internal returns (uint256 mintAmount) {
        // Mint unbacked supply
        mintAmount = IAdaptiveSupply(
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
            addresses.vault,
            false
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