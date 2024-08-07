

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
    AmountsToMint,
    ShiftParameters,
    ProtocolAddresses,
    PreShiftParameters
} from "../Types.sol";

interface IVault {
    function updatePositions(LiquidityPosition[3] memory newPositions) external;
    function setFees(uint256 _feesAccumulatedToken0, uint256 _feesAccumulatedToken1) external;
}

error InvalidTick();
error AboveThreshold();
error BelowThreshold();

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
        require(positions.length == 3, "invalid positions");

        // Ratio of the anchor's price to market price
        currentLiquidityRatio = IModelHelper(addresses.modelHelper)
        .getLiquidityRatio(addresses.pool, addresses.vault);
        
        (uint256 circulatingSupply, uint256 anchorToken1Balance, uint256 discoveryToken1Balance, uint256 discoveryToken0Balance) = getVaulData(addresses);

        if (currentLiquidityRatio <= 98e16) {
            
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
                    
                    return (currentLiquidityRatio, newPositions);
                }

            } 

        } else {
            revert AboveThreshold();
        }
    }

    function preShiftPositions(
        PreShiftParameters memory params,
        LiquidityPosition[3] memory _positions
    ) internal returns (LiquidityPosition[3] memory newPositions) {

        address modelHelper = params.addresses.modelHelper;
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
            ShiftParameters({
                pool: params.addresses.pool,
                deployer: params.addresses.deployer,
                toSkim: params.toSkim,
                newFloorPrice: newFloorPrice,
                modelHelper: params.addresses.modelHelper,
                floorToken1Balance: params.floorToken1Balance,
                anchorToken1Balance: params.anchorToken1Balance,
                discoveryToken1Balance: params.discoveryToken1Balance,
                discoveryToken0Balance: params.discoveryToken0Balance,
                positions: _positions
            })
        );

        IVault(address(this))
        .updatePositions(
            newPositions
        );

        IModelHelper(modelHelper)
        .enforceSolvencyInvariant(address(this));        
    }

    function shiftPositions(
        ShiftParameters memory params
    ) internal returns (
        LiquidityPosition[3] memory newPositions
    ) {
        require(params.discoveryToken0Balance > 0, "invalid params");
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(params.pool).slot0();
       
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
                ERC20(IUniswapV3Pool(params.pool).token1()).transfer(
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
                18), 
                params.newFloorPrice,
                params.floorToken1Balance + params.toSkim,
                params.floorToken1Balance,
                params.positions[0]
            );


            // Deploy new anchor position
            newPositions[1] = reDeploy(
                params.pool,
                params.deployer,
                newPositions[0].upperTick,                
                Utils.addBipsToTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                    1
                ),
                (params.anchorToken1Balance + params.discoveryToken1Balance) - params.toSkim, 
                LiquidityType.Anchor
            );

            newPositions[2] = reDeploy(
                params.pool,
                params.deployer, 
                newPositions[1].upperTick,
                Utils.addBipsToTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                    25000
                ),           
                0,
                LiquidityType.Discovery 
            );   
            
            require(
                newPositions[0].liquidity > 0 &&
                newPositions[1].liquidity > 0 &&  
                newPositions[2].liquidity > 0, 
                "shiftPositions: no liquidity in positions"
            );

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
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(addresses.pool).slot0();

        // Ratio of the anchor's price to market price
        uint256 currentLiquidityRatio = IModelHelper(addresses.modelHelper)
        .getLiquidityRatio(addresses.pool, addresses.vault);
                
        (, uint256 anchorToken1Balance,, ) = getVaulData(addresses);

        if (currentLiquidityRatio >= 115e16) {
            
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

            //Shift anchor position
            newPositions[1] = reDeploy(
                addresses.pool,
                addresses.deployer,
                positions[0].upperTick,                
                Utils.addBipsToTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                    30
                ),
                anchorToken1Balance, 
                LiquidityType.Anchor
            );

            newPositions[2] = reDeploy(
                addresses.pool,
                addresses.deployer,
                newPositions[1].upperTick,
                Utils.addBipsToTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                    10000
                ),              
                0,
                LiquidityType.Discovery
            );

            // restore floor
            newPositions[0] = positions[0];

            IVault(address(this))
            .updatePositions(
                newPositions
            );    

            IModelHelper(addresses.modelHelper)
            .enforceSolvencyInvariant(address(this));   

        } else {
            revert BelowThreshold();
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
        .deployPosition(
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
            require(liquidity > 0, "onlyNotEmptyPositions");
        }
        _;
    }

}