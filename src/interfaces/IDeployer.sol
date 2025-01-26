// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    LiquidityPosition,
    AmountsToMint,
    LiquidityType
} from "../types/Types.sol";

/**
 * @title IDeployer
 * @notice Interface for deploying and managing various liquidity positions within a DeFi protocol.
 */
interface IDeployer {
    /**
     * @notice Deploys the initial floor liquidity position at the specified floor price.
     * @param _floorPrice The initial price for the floor liquidity position.
     */
    function deployFloor(uint256 _floorPrice) external;

    /**
     * @notice Adjusts the existing floor liquidity position to a new price and balance.
     * @param pool The address of the Uniswap V3 pool.
     * @param receiver The address that will receive the adjusted liquidity position.
     * @param currentFloorPrice The current floor price.
     * @param newFloorPrice The desired new floor price.
     * @param newFloorBalance The desired new balance for the floor position.
     * @param currentFloorBalance The current balance of the floor position.
     * @param floorPosition The current liquidity position details.
     * @return newPosition The updated liquidity position after the shift.
     */
    function shiftFloor(
        address pool,
        address receiver,
        uint256 currentFloorPrice,
        uint256 newFloorPrice,
        uint256 newFloorBalance,
        uint256 currentFloorBalance,
        LiquidityPosition memory floorPosition
    ) external returns (LiquidityPosition memory newPosition);

    /**
     * @notice Deploys a new liquidity position within specified tick ranges and amounts.
     * @param pool The address of the Uniswap V3 pool.
     * @param receiver The address that will receive the new liquidity position.
     * @param lowerTick The lower tick boundary for the liquidity position.
     * @param upperTick The upper tick boundary for the liquidity position.
     * @param liquidityType The type of liquidity being deployed.
     * @param amounts The amounts of tokens to mint for the position.
     * @return newPosition The details of the newly created liquidity position.
     */
    function deployPosition(
        address pool,
        address receiver,
        int24 lowerTick,
        int24 upperTick,
        LiquidityType liquidityType,
        AmountsToMint memory amounts
    ) external returns (LiquidityPosition memory newPosition);

    /**
     * @notice Redeploys an existing liquidity position with new tick ranges and liquidity type.
     * @param pool The address of the Uniswap V3 pool.
     * @param lowerTick The new lower tick boundary for the liquidity position.
     * @param upperTick The new upper tick boundary for the liquidity position.
     * @param liquidityType The new type of liquidity for the position.
     * @return newPosition The details of the redeployed liquidity position.
     */
    function reDeploy(
        address pool,
        int24 lowerTick,
        int24 upperTick,
        LiquidityType liquidityType
    ) external returns (LiquidityPosition memory newPosition);

    /**
     * @notice Computes the new floor price based on various parameters and current positions.
     * @param pool The address of the Uniswap V3 pool.
     * @param toSkim The amount to be skimmed from the pool.
     * @param floorNewTokenBalance The new token balance for the floor position.
     * @param circulatingSupply The current circulating supply of the token.
     * @param anchorCapacity The capacity of the anchor position.
     * @param positions An array containing current liquidity positions.
     * @return newFloorPrice The calculated new floor price.
     */
    function computeNewFloorPrice(
        address pool,
        uint256 toSkim,
        uint256 floorNewTokenBalance,
        uint256 circulatingSupply,
        uint256 anchorCapacity,
        LiquidityPosition[3] memory positions
    ) external view returns (uint256 newFloorPrice);
}
