// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/interfaces/IVault.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LendingVaultTest is Test {
    IVault vault;
    IERC20 token0;
    IERC20 token1;

    address vaultAddress = 0x7030dF55d8C080C5A0BF0f0ee3e8317e6561EB24;
    address lendingVault = 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496;
    uint256 MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    function setUp() public {

        // Initialize the existing vault contract
        vault = IVault(vaultAddress);
        IUniswapV3Pool pool = vault.pool();

        address token0Address = pool.token0();

        token0 = IERC20(token0Address);  
        token1 = IERC20(pool.token1());      
    }

    function testBorrow() public {
        uint256 borrowAmount = 1 ether;
        int256 duration = 30 days;

        vm.prank(deployer);
        token0.approve(vaultAddress, MAX_INT);
        vm.stopPrank();

        uint256 allowance = token0.allowance(deployer, vaultAddress);
        uint256 balanceBeforeToken0 = token0.balanceOf(deployer);
        uint256 balanceBeforeToken1 = token1.balanceOf(deployer);

        vm.prank(deployer);
        vault.borrow(deployer, borrowAmount);

        assertEq(token1.balanceOf(deployer) - balanceBeforeToken1, borrowAmount);
        assertLt(token0.balanceOf(deployer), balanceBeforeToken0);
    }

    function testPaybackLoan() public {
        uint256 borrowAmount = 1 ether;

        vm.prank(deployer);
        token0.approve(vaultAddress, MAX_INT);


        // Borrow first
        vm.prank(deployer);
        vault.borrow(deployer, borrowAmount);
        
        uint256 balanceBeforePaybackToken1 = token1.balanceOf(deployer);
        uint256 balanceBeforePaybackToken0 = token0.balanceOf(deployer);

        // Pay back part of the loan
        vm.prank(deployer);
        token1.approve(vaultAddress, MAX_INT);

        vm.prank(deployer);
        vault.payback(deployer);

        // check if the loan amount is deducted from the user's balance
        assertEq(balanceBeforePaybackToken1 - token1.balanceOf(deployer), borrowAmount);
        // check if the borrowed amount is reduced by the payback amount
        assertLt(balanceBeforePaybackToken0, token0.balanceOf(deployer));

    }    
}
