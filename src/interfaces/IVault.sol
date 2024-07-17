// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityPosition} from "../Types.sol";

interface IVault  {
    function borrow(address who, uint256 borrowAmount) external;
    function pool() external returns (IUniswapV3Pool);
    function payback(address who) external;
    function roll(address who) external;
    function updatePositions(LiquidityPosition[3] memory newPositions) external;
}
