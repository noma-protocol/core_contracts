// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";



contract Positions {

    IUniswapV3Pool public pool;

    function initialize() {
    if (lock.nftId() == 0) {
      return;
    } else if (address(pool) == address(0)) {
      IUniswapV3Factory factory = IUniswapV3Factory(factoryAddress);
      pool = IUniswapV3Pool(factory.getPool(weth, address(circle), poolFee));
      ERC20(circle).approve(address(pool), type(uint256).max);
      WETH(payable(weth)).approve(address(pool), type(uint256).max);
      require(address(pool) != address(0));
      token0 = pool.token0();
    }
    }


}