
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from '@uniswap/v3-core/libraries/TickMath.sol';
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Uniswap} from "./libraries/Uniswap.sol";
import {Conversions} from "./libraries/Conversions.sol";
import {DecimalMath} from "./libraries/DecimalMath.sol";

import {Underlying} from "./libraries/Underlying.sol";
import {Utils} from "./libraries/Utils.sol";

import {
    LiquidityPosition,
    LiquidityType,
    VaultInfo
} from "./Types.sol";

error AlreadyInitialized();
error InvalidCaller();

contract ModelHelper {

    LiquidityPosition private floorPosition;
    LiquidityPosition private anchorPosition;
    LiquidityPosition private discoveryPosition;

    bool private initialized;
    address private deployerContract;

    constructor() {
        initialized = false;
    }

    function updatePositions(
        address _deployerContract,
        LiquidityPosition[3] memory _positions
    ) public {
        // if (initialized) revert AlreadyInitialized();
        // if (msg.sender != _deployerContract) revert InvalidCaller();

        floorPosition = _positions[0];
        anchorPosition = _positions[1];
        discoveryPosition = _positions[2];

        // initialized = true;
    }

    function getLiquidityRatio(
        address pool
    ) public view returns (uint256 liquidityRatio) {
            
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        uint256 anchorLowerPrice = Conversions.sqrtPriceX96ToPrice(
                Conversions.tickToSqrtPriceX96(anchorPosition.lowerTick),
            18);

        uint256 anchorUpperPrice = Conversions.sqrtPriceX96ToPrice(
                Conversions.tickToSqrtPriceX96(anchorPosition.upperTick),
            18);

        uint256 avgAnchorPrice = (anchorLowerPrice + anchorUpperPrice) / 2;
            
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);
        liquidityRatio = DecimalMath.divideDecimal(avgAnchorPrice, spotPrice);
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
            (amount0Current, ) = LiquidityAmounts
            .getAmountsForLiquidity(
                TickMath.getSqrtRatioAtTick(position.lowerTick),
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

        LiquidityPosition memory position;

        if (liquidityType == LiquidityType.Floor) {
            position = floorPosition;
        } else if (liquidityType == LiquidityType.Anchor) {
            position = anchorPosition;
        } else if (liquidityType == LiquidityType.Discovery) {
            position = discoveryPosition;
        }

        require(position.liquidity > 0, "no liquidity");
        return Underlying.getUnderlyingBalances(address(pool), vault, position);
    }

    function getVaultInfo(
        address pool,
        address vault,
        VaultInfo memory vaultInfo  
    ) public view 
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
            getLiquidityRatio(address(pool)),
            getCirculatingSupply(address(pool), vault),
            Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18),
            getPositionCapacity(address(pool), vault, anchorPosition),
            getPositionCapacity(address(pool), vault, floorPosition),
            vaultInfo.token0,
            vaultInfo.token1            
        );
    }   

    function getCirculatingSupply(
        address pool,
        address vault
    ) public view returns (uint256) {

        uint256 totalSupply = ERC20(address(IUniswapV3Pool(pool).token0())).totalSupply();

        (  
            ,,uint256 amount0CurrentAnchor, 
        ) = Underlying.getUnderlyingBalances(pool, vault, anchorPosition);
        
        (
            ,,uint256 amount0CurrentDiscovery,             
        ) = Underlying.getUnderlyingBalances(pool, vault, discoveryPosition);

        uint256 protocolUnusedBalanceToken0 = ERC20(address(IUniswapV3Pool(pool).token0())).balanceOf(vault);
    
        return totalSupply - (amount0CurrentAnchor + amount0CurrentDiscovery + protocolUnusedBalanceToken0);
    } 

    function estimateNewFloorPrice(
        address pool,
        address vault
    ) internal view returns (uint256) {
     
        uint256 circulatingSupply = getCirculatingSupply(pool, vault);
        uint256 anchorCapacity = getPositionCapacity(pool, vault, anchorPosition);

        (
           ,,, uint256 amount1Current
        ) = Underlying.getUnderlyingBalances(pool, address(this), floorPosition);
     
        return DecimalMath.divideDecimal(amount1Current, circulatingSupply - anchorCapacity);
    }
}