
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from '@uniswap/v3-core/libraries/TickMath.sol';
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Uniswap} from "../libraries/Uniswap.sol";
import {Conversions} from "../libraries/Conversions.sol";
import {DecimalMath} from "../libraries/DecimalMath.sol";

import {Underlying} from "../libraries/Underlying.sol";
import {Utils} from "../libraries/Utils.sol";

import {
    LiquidityPosition,
    LiquidityType,
    TokenInfo,
    VaultInfo
} from "../Types.sol";

error AlreadyInitialized();
error InvalidCaller();

interface IVault {
    function getPositions() external view returns (LiquidityPosition[3] memory);
    function getAccumulatedFees() external view returns (uint256, uint256);
}

contract ModelHelper {

    bool private initialized;
    address private deployerContract;

    constructor() {}

    function getLiquidityRatio(
        address pool,
        address vault
    ) public view returns (uint256 liquidityRatio) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        uint256 anchorUpperPrice = Conversions.sqrtPriceX96ToPrice(
                Conversions.tickToSqrtPriceX96(positions[1].upperTick),
            18);
            
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);
        liquidityRatio = DecimalMath.divideDecimal(anchorUpperPrice, spotPrice);
    }

    function getPositionCapacity(
        address pool,
        address vault,
        LiquidityPosition memory position
    ) public view returns (uint256 amount0Current) {

        (
            uint128 liquidity,,,,
        ) = IUniswapV3Pool(pool).positions(
            keccak256(
            abi.encodePacked(
                    vault, 
                    position.lowerTick, 
                    position.upperTick
                )
            )            
        );

        if (liquidity > 0) { 
            amount0Current = LiquidityAmounts
            .getAmount0ForLiquidity(
                TickMath.getSqrtRatioAtTick(position.lowerTick),
                TickMath.getSqrtRatioAtTick(position.upperTick),
                liquidity
            );
        }
    } 

    function getUnderlyingBalances(
        address pool,
        address vault,
        LiquidityType liquidityType
    ) public view 
    returns (int24, int24, uint256, uint256) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();
        LiquidityPosition memory position;

        if (liquidityType == LiquidityType.Floor) {
            position = positions[0];
        } else if (liquidityType == LiquidityType.Anchor) {
            position = positions[1];
        } else if (liquidityType == LiquidityType.Discovery) {
            position = positions[2];
        }

        require(position.liquidity > 0, "no liquidity");
        return Underlying.getUnderlyingBalances(address(pool), vault, position);
    }

    function getVaultInfo(
        address pool,
        address vault,
        TokenInfo memory tokenInfo  
    ) public view 
    returns (
        VaultInfo memory vaultInfo
    ) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        
        vaultInfo.liquidityRatio = getLiquidityRatio(pool, vault);
        vaultInfo.circulatingSupply = getCirculatingSupply(pool, vault);
        vaultInfo.spotPriceX96 = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        vaultInfo.anchorCapacity = getPositionCapacity(pool, vault, positions[1]);
        vaultInfo.floorCapacity = getPositionCapacity(pool, vault, positions[0]);
        vaultInfo.token0 = tokenInfo.token0;
        vaultInfo.token1 = tokenInfo.token1;
    }   

    function getCirculatingSupply(
        address pool,
        address vault
    ) public view returns (uint256) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();
        uint256 totalSupply = ERC20(address(IUniswapV3Pool(pool).token0())).totalSupply();

        (,,uint256 amount0CurrentFloor, ) = Underlying.getUnderlyingBalances(pool, vault, positions[0]);
        (,,uint256 amount0CurrentAnchor, ) = Underlying.getUnderlyingBalances(pool, vault, positions[1]);
        (,,uint256 amount0CurrentDiscovery, ) = Underlying.getUnderlyingBalances(pool, vault, positions[2]);

        uint256 protocolUnusedBalanceToken0 = ERC20(address(IUniswapV3Pool(pool).token0())).balanceOf(vault);
    
        return totalSupply - (amount0CurrentFloor + amount0CurrentAnchor + amount0CurrentDiscovery + protocolUnusedBalanceToken0);
    } 

    function getExcessReserveBalance(
        address pool,
        address vault,
        bool isToken0
    ) public view returns (uint256) {
        ERC20 token = ERC20(isToken0 ? IUniswapV3Pool(pool).token0() : IUniswapV3Pool(pool).token1());
        uint256 protocolUnusedBalance = token.balanceOf(vault);
    
        (uint256 accumulatedFeesToken0, uint256 accumulatedFeesToken1) = IVault(vault).getAccumulatedFees();
        uint256 fees = isToken0 ? accumulatedFeesToken0 : accumulatedFeesToken1;

        return protocolUnusedBalance - fees;
    }
}