

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from 'v3-core/libraries/TickMath.sol';
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
    AmountsToMint,
    ShiftParameters,
    ProtocolAddresses,
    PreShiftParameters,
    tickSpacing,
    LiquidityStructureParameters,
    LiquidityInternalPars
} from "../types/Types.sol";

interface IVault {
    function updatePositions(LiquidityPosition[3] memory newPositions) external;
    function setFees(uint256 _feesAccumulatedToken0, uint256 _feesAccumulatedToken1) external;
    function mintTokens(address to, uint256 amount) external;
    function burnTokens(uint256 amount) external;
    function getLiquidityStructureParameters() external view returns (LiquidityStructureParameters memory _params);
    function getTimeSinceLastMint() external view returns (uint256);
    function teamMultiSig() external view returns (address);
}

interface IAdaptiveSupply {
    function calculateMintAmount(
        uint256 deltaSupply,
        uint256 timeElapsed,
        uint256 spotPrice,
        uint256 imv
    ) external pure returns (uint256 mintAmount);
}

error InvalidTick();
error AboveThreshold();
error BelowThreshold();
error PositionsLength();
error NoLiquidity();
error MintAmount();
error BalanceToken0();
error OnlyNotEmptyPositions();

library LiquidityOps {
    
    function shift(
        ProtocolAddresses memory addresses,
        LiquidityPosition[3] memory positions
    ) internal 
    onlyNotEmptyPositions(addresses.pool, positions) 
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
        ) = getVaulData(addresses);

        if (currentLiquidityRatio <= IVault(address(this)).getLiquidityStructureParameters().shiftRatio) {
            
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
                    address(this), 
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
                
                IVault(address(this))
                .updatePositions(
                    newPositions
                ); 

                return (currentLiquidityRatio, newPositions);
            }

        } else {
            revert AboveThreshold();
        }
    }

    function preShiftPositions(
        PreShiftParameters memory params,
        LiquidityPosition[3] memory _positions
    ) internal returns (LiquidityPosition[3] memory newPositions) {

        address deployer = params.addresses.deployer;
        address pool = params.addresses.pool;

        uint256 newFloorPrice = IDeployer(deployer)
                .computeNewFloorPrice(
                    pool,
                    params.toSkim,
                    params.floorToken1Balance,
                    params.circulatingSupply,
                    params.anchorCapacity,
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

    function shiftPositions(
        ProtocolAddresses memory addresses,
        ShiftParameters memory params
    ) internal returns (
        LiquidityPosition[3] memory newPositions
    ) {
        uint8 decimals = IERC20Metadata(address(IUniswapV3Pool(params.pool).token0())).decimals();

        if (params.positions[0].liquidity > 0) {

            (
                uint256 feesPosition0Token0,
                uint256 feesPosition0Token1, 
                uint256 feesPosition1Token0, 
                uint256 feesPosition1Token1
             ) = _calculateFees(params.pool, params.positions);

            IVault(address(this)).setFees(
                feesPosition0Token0, 
                feesPosition0Token1
            );

            IVault(address(this)).setFees(
                feesPosition1Token0, 
                feesPosition1Token1
            );

            // Collect floor liquidity
            Uniswap.collect(
                params.pool, 
                address(this), 
                params.positions[0].lowerTick, 
                params.positions[0].upperTick
            ); 

            // Collect discovery liquidity
            Uniswap.collect(
                params.pool, 
                address(this), 
                params.positions[2].lowerTick, 
                params.positions[2].upperTick
            );

            // Collect anchor liquidity
            Uniswap.collect(
                params.pool, 
                address(this), 
                params.positions[1].lowerTick, 
                params.positions[1].upperTick
            ); 

            if (params.floorToken1Balance + params.toSkim > params.floorToken1Balance) {
                IERC20Metadata(IUniswapV3Pool(params.pool).token1()).transfer(
                    params.deployer, 
                    params.floorToken1Balance + params.toSkim
                );
            }

            newPositions[0] = IDeployer(params.deployer) 
            .shiftFloor(
                params.pool, 
                address(this), 
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

            (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(params.pool).slot0();

            // Deploy new anchor position
            newPositions[1] = reDeploy(
                ProtocolAddresses({
                    pool: params.pool,
                    modelHelper: addresses.modelHelper,
                    vault: addresses.vault,
                    deployer: addresses.deployer,
                    adaptiveSupplyController: addresses.adaptiveSupplyController
                }),
                LiquidityInternalPars({
                    lowerTick: newPositions[0].upperTick,
                    upperTick: Utils.addBipsToTick(
                        TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                        IVault(address(this))
                        .getLiquidityStructureParameters().shiftAnchorUpperBips,
                        decimals
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
                    adaptiveSupplyController: addresses.adaptiveSupplyController
                }),
                LiquidityInternalPars({
                    lowerTick: newPositions[1].upperTick + tickSpacing,
                    upperTick: Utils.addBipsToTick(
                        TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                        IVault(address(this))
                        .getLiquidityStructureParameters().discoveryBips,
                        decimals
                    ),
                    amount1ToDeploy: 0,
                    liquidityType: LiquidityType.Discovery
                }),
                true
            );   
            
            if (
                newPositions[0].liquidity == 0 || 
                newPositions[1].liquidity == 0 || 
                newPositions[2].liquidity == 0
            ) {
                revert NoLiquidity();
            }

        } else {
            revert("shiftPositions: no liquidity in Floor");
        }

    }
    
    function slide(
        ProtocolAddresses memory addresses,
        LiquidityPosition[3] memory positions
    ) internal 
    onlyNotEmptyPositions(addresses.pool, positions) 
    returns (
        LiquidityPosition[3] memory newPositions
    ) {
        if (positions.length != 3) {
            revert PositionsLength();
        }

        uint8 decimals = IERC20Metadata(address(IUniswapV3Pool(addresses.pool).token0())).decimals();
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(addresses.pool).slot0();

        // Ratio of the anchor's price to market price
        uint256 currentLiquidityRatio = IModelHelper(addresses.modelHelper)
        .getLiquidityRatio(addresses.pool, addresses.vault);
                
        (, uint256 anchorToken1Balance,, ) = getVaulData(addresses);

        if (currentLiquidityRatio >= IVault(address(this)).getLiquidityStructureParameters().slideRatio) {
            
            (
                uint256 feesPosition0Token0,
                uint256 feesPosition0Token1, 
                uint256 feesPosition1Token0, 
                uint256 feesPosition1Token1
            ) = _calculateFees(addresses.pool, positions);

            IVault(address(this)).setFees(
                feesPosition0Token0, 
                feesPosition0Token1
            );

            IVault(address(this)).setFees(
                feesPosition1Token0, 
                feesPosition1Token1
            );

            // Collect anchor liquidity
            Uniswap.collect(
                addresses.pool, 
                address(this), 
                positions[1].lowerTick, 
                positions[1].upperTick
            ); 

            Uniswap.collect(
                addresses.pool, 
                address(this), 
                positions[2].lowerTick, 
                positions[2].upperTick
            ); 

            //Slide anchor position
            newPositions[1] = reDeploy(
                addresses,
                LiquidityInternalPars({
                    lowerTick: positions[0].upperTick,
                    upperTick: Utils.addBipsToTick(
                        TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                        IVault(address(this)).getLiquidityStructureParameters()
                        .slideAnchorUpperBips,
                        decimals
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
                    adaptiveSupplyController: addresses.adaptiveSupplyController
                }),
                LiquidityInternalPars({
                    lowerTick: newPositions[1].upperTick + tickSpacing,
                    upperTick: Utils.addBipsToTick(
                        TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                        IVault(address(this)).getLiquidityStructureParameters()
                        .discoveryBips,
                        decimals
                    ),
                    amount1ToDeploy: 0,
                    liquidityType: LiquidityType.Discovery
                }),
                false
            );

            // restore floor
            newPositions[0] = positions[0];

            IVault(address(this))
            .updatePositions(
                newPositions
            );    

        } else {
            revert BelowThreshold();
        }  
        
    }

    function reDeploy(
        ProtocolAddresses memory addresses,
        LiquidityInternalPars memory params,
        bool isShift
    ) internal returns (LiquidityPosition memory newPosition) {
        if (params.upperTick <= params.lowerTick) {
            revert InvalidTick();
        }
        
        uint256 balanceToken0 = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).balanceOf(address(this));
        uint256 token0Allowance = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).allowance(address(this), addresses.deployer);

        if (token0Allowance != type(uint256).max) {
            IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).approve(addresses.deployer, type(uint256).max);
        }

        // TODO check this
        IERC20Metadata(IUniswapV3Pool(addresses.pool).token1()).approve(addresses.deployer, params.amount1ToDeploy > 0 ? params.amount1ToDeploy : 1);

        if (params.liquidityType == LiquidityType.Discovery) {

            uint256 circulatingSupply = IModelHelper(addresses.modelHelper)
            .getCirculatingSupply(
                addresses.pool,
                addresses.vault
            );        

            uint256 totalSupply = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).totalSupply();        
            
            (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(addresses.pool).slot0();

            if (balanceToken0 < circulatingSupply / IVault(address(this)).getLiquidityStructureParameters().lowBalanceThresholdFactor) {
                if (isShift) {
                    // Mint unbacked supply
                    (uint256 mintAmount) = IAdaptiveSupply(
                        addresses.adaptiveSupplyController
                    ).calculateMintAmount(
                        totalSupply,
                        IVault(address(this)).getTimeSinceLastMint() > 0 ? 
                        IVault(address(this)).getTimeSinceLastMint() : 
                        1,
                        Conversions.sqrtPriceX96ToPrice(
                            sqrtRatioX96,
                            18
                        ),
                        IModelHelper(addresses.modelHelper).getIntrinsicMinimumValue(address(this))
                    );

                    if (mintAmount == 0 || mintAmount > totalSupply) {
                        // Fallback to minting a % of circulating supply
                        mintAmount = circulatingSupply / IVault(address(this)).getLiquidityStructureParameters().lowBalanceThresholdFactor;
                    }

                    IVault(address(this))
                    .mintTokens(
                        address(this),
                        mintAmount
                    );

                    address teamMultisig = IVault(address(this)).teamMultiSig();

                    if (teamMultisig != address(0)) {
                        IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).transfer(
                            teamMultisig, 
                            mintAmount - (mintAmount * (IVault(address(this)).getLiquidityStructureParameters().inflationFee / 1e18))
                        );
                    }

                }
            }
        
            // TODO add check balance before minting
            if (balanceToken0 >= circulatingSupply / IVault(address(this)).getLiquidityStructureParameters().highBalanceThresholdFactor) {
                    if (!isShift) {
    
                        IVault(address(this))
                        .burnTokens(
                            balanceToken0
                        );

                        IVault(address(this))
                        .mintTokens(
                            address(this),
                            circulatingSupply / IVault(address(this)).getLiquidityStructureParameters().highBalanceThresholdFactor
                        );   
                }                
            }

            // check balance after minting or burning
            balanceToken0 = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).balanceOf(address(this));
            
            if (balanceToken0 == 0) {
                // Fallback to minting a % of circulating supply
                IVault(address(this))
                .mintTokens(
                    address(this),
                    circulatingSupply / IVault(address(this)).getLiquidityStructureParameters().lowBalanceThresholdFactor
                );

                balanceToken0 = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).balanceOf(address(this));
            }

        }
        
        newPosition = IDeployer(addresses.deployer)
        .deployPosition(
            addresses.pool, 
            address(this), 
            params.lowerTick,
            params.upperTick,
            params.liquidityType, 
            AmountsToMint({
                amount0: balanceToken0,
                amount1: params.liquidityType == LiquidityType.Anchor ? params.amount1ToDeploy : 1
            })
        );     
    }
    
    function getVaulData(ProtocolAddresses memory addresses) internal view returns (uint256, uint256, uint256, uint256) {
        (,,, uint256 anchorToken1Balance) = IModelHelper(addresses.modelHelper)
        .getUnderlyingBalances(
            addresses.pool, 
            address(this), 
            LiquidityType.Anchor
        );

        (,, uint256 discoveryToken0Balance, uint256 discoveryToken1Balance) = IModelHelper(addresses.modelHelper)
        .getUnderlyingBalances(
            addresses.pool, 
            address(this), 
            LiquidityType.Discovery
        );

        uint256 circulatingSupply = IModelHelper(addresses.modelHelper)
        .getCirculatingSupply(
            addresses.pool,
            addresses.vault
        );
        
        return (circulatingSupply, anchorToken1Balance, discoveryToken1Balance, discoveryToken0Balance);
    }

    function _calculateFees(
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
            address(this), 
            pool, 
            true, 
            TickMath.getTickAtSqrtRatio(sqrtRatioX96)
        );

        feesPosition1Token0 = Underlying
        .computeFeesEarned(
            positions[1], 
            address(this), 
            pool, 
            true, 
            TickMath.getTickAtSqrtRatio(sqrtRatioX96)
        );

        feesPosition0Token1 = Underlying
        .computeFeesEarned(
            positions[0], 
            address(this), 
            pool, 
            false, 
            TickMath.getTickAtSqrtRatio(sqrtRatioX96)
        );

        feesPosition1Token1 = Underlying
        .computeFeesEarned(
            positions[1], 
            address(this), 
            pool, 
            false, 
            TickMath.getTickAtSqrtRatio(sqrtRatioX96)
        );

        return (feesPosition0Token0, feesPosition0Token1, feesPosition1Token0, feesPosition1Token1);
    }

    modifier onlyNotEmptyPositions(
        address pool,
        LiquidityPosition[3] memory positions
    ) {

        for (uint256 i = 0; i < positions.length; i++) {
                   
            bytes32 positionId = keccak256(
                abi.encodePacked(
                    address(this), 
                    positions[i].lowerTick, 
                    positions[i].upperTick
                )
            );

            (uint128 liquidity,,,,) = IUniswapV3Pool(pool).positions(positionId);
            if (liquidity == 0) {
                revert OnlyNotEmptyPositions();
            }
        }
        _;
    }

}