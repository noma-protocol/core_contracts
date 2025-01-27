
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from 'v3-core/libraries/TickMath.sol';
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Uniswap} from "../libraries/Uniswap.sol";
import {Conversions} from "../libraries/Conversions.sol";
import {DecimalMath} from "../libraries/DecimalMath.sol";

import {Underlying} from "../libraries/Underlying.sol";
import {Utils} from "../libraries/Utils.sol";
import { IVault } from "../interfaces/IVault.sol";

import {
    LiquidityPosition,
    LiquidityType,
    TokenInfo,
    VaultInfo
} from "../types/Types.sol";


error NoLiquidity();
error InsolvencyInvariant();

contract ModelHelper {

    function getLiquidityRatio(
        address pool,
        address vault
    ) public view returns (uint256 liquidityRatio) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint8 decimals = ERC20(address(IUniswapV3Pool(pool).token0())).decimals();

        uint256 anchorUpperPrice = Conversions.sqrtPriceX96ToPrice(
                Conversions.tickToSqrtPriceX96(positions[1].upperTick),
            decimals);
            
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, decimals);
        liquidityRatio = DecimalMath.divideDecimal(anchorUpperPrice, spotPrice);
    }

    function getPositionCapacity(
        address pool,
        address vault,
        LiquidityPosition memory position,
        LiquidityType liquidityType
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

        if (liquidityType == LiquidityType.Floor) {
            uint256 vaultCollateral = IVault(vault).getCollateralAmount();
            amount0Current = amount0Current + vaultCollateral;

        }

        return amount0Current;
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

        if (position.liquidity == 0) {
            revert NoLiquidity();
        }
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
        return _getVaultInfo(pool, vault, tokenInfo);
    }   

    function _getVaultInfo(
        address pool,
        address vault,
        TokenInfo memory tokenInfo
    ) internal view
    returns (
        VaultInfo memory vaultInfo
    ) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        
        vaultInfo.liquidityRatio = getLiquidityRatio(pool, vault);
        vaultInfo.circulatingSupply = getCirculatingSupply(pool, vault);
        vaultInfo.spotPriceX96 = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        vaultInfo.anchorCapacity = getPositionCapacity(pool, vault, positions[1], LiquidityType.Anchor);
        vaultInfo.floorCapacity = getPositionCapacity(pool, vault, positions[0], LiquidityType.Floor);
        vaultInfo.token0 = tokenInfo.token0;
        vaultInfo.token1 = tokenInfo.token1;

        return vaultInfo;
    }

    function getCirculatingSupply(
        address pool,
        address vault
    ) public view returns (uint256) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();
        uint256 totalSupply = ERC20(address(IUniswapV3Pool(pool).token0())).totalSupply();

        (,, uint256 amount0CurrentFloor, ) = Underlying.getUnderlyingBalances(pool, vault, positions[0]);
        (,, uint256 amount0CurrentAnchor, ) = Underlying.getUnderlyingBalances(pool, vault, positions[1]);
        (,, uint256 amount0CurrentDiscovery, ) = Underlying.getUnderlyingBalances(pool, vault, positions[2]);

        uint256 protocolUnusedBalanceToken0 = ERC20(address(IUniswapV3Pool(pool).token0())).balanceOf(vault);
        
        address stakingContract = IVault(vault).getStakingContract();

        uint256 staked = stakingContract != address(0) ? 
                ERC20(address(IUniswapV3Pool(pool).token0())).balanceOf(stakingContract) :
                0;

        return (
            (totalSupply) - 
            (
                amount0CurrentFloor + 
                amount0CurrentAnchor + 
                amount0CurrentDiscovery + 
                protocolUnusedBalanceToken0 + 
                staked
            )
        );
    } 

    function getTotalSupply(
        address pool,
        bool isToken0
    ) public view returns (uint256 totalSupply) {

        totalSupply =  ERC20(
        address(
            isToken0 ? 
            IUniswapV3Pool(pool).token0() :
            IUniswapV3Pool(pool).token1()
        )).totalSupply();

      return totalSupply;
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

    function getIntrinsicMinimumValue(address _vault) public view returns (uint256) {
        LiquidityPosition[3] memory positions = IVault(_vault).getPositions();

        int24 lowerTick = positions[0].lowerTick;
        uint160 sqrtPriceX96 = Conversions.tickToSqrtPriceX96(lowerTick);

        return Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
    }

    function enforceSolvencyInvariant(address _vault) public view {
 
        VaultInfo memory vaultInfo = IVault(_vault).getVaultInfo();
 
        uint256 circulatingSupply = vaultInfo.circulatingSupply;
        uint256 anchorCapacity = vaultInfo.anchorCapacity;
        uint256 floorCapacity = vaultInfo.floorCapacity;
        
        // To guarantee solvency, Noma ensures that capacity > circulating supply each liquidity is deployed.
        if (anchorCapacity + floorCapacity <= circulatingSupply) {
            revert InsolvencyInvariant();
        }
    }
}