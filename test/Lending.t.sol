// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IVault.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {AmphorToken} from  "../src/token/AmphorToken.sol";
import {ModelHelper} from  "../src/model/Helper.sol";
import {BaseVault} from  "../src/vault/BaseVault.sol";
import {Utils} from "../src/libraries/Utils.sol";
import {Conversions} from "../src/libraries/Conversions.sol";
import {Underlying } from  "../src/libraries/Underlying.sol";
import {DecimalMath} from "../src/libraries/DecimalMath.sol";
import {LiquidityType, LiquidityPosition} from "../src/Types.sol";

interface IWETH {
    function balanceOf(address account) external view returns (uint256);
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
}

interface IDOManager {
    function vault() external view returns (BaseVault);
    function buyTokens(uint256 price, uint256 amount, address receiver) external;
    function sellTokens(uint256 price, uint256 amount, address receiver) external;
    function modelHelper() external view returns (address);
}

contract LendingVaultTest is Test {
    IVault vault;
    IERC20 token0;
    IERC20 token1;

    address WETH = 0xAaE73BfC17EC6CF6417cD7f15cf86F9AEbc33Edc;
    address payable idoManager = payable(0x4ff2d7eAf57E8a87e89436A4DCab3e05686fc501);
    address nomaToken = 0x71928Dd90031aB5Bb11d4765361c30958ecd4143;
    address deployerContract = 0xc11FeB4A3B79a73CA4f4F3C4B6e757eDB8D19830;
    address vaultAddress;

    uint256 MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    AmphorToken private noma;
    ModelHelper private modelHelper;

    function setUp() public {
        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");

        noma = AmphorToken(nomaToken);
        require(address(noma) != address(0), "Noma token address is zero");
        
        address modelHelperContract = managerContract.modelHelper();
        modelHelper = ModelHelper(modelHelperContract);
        vaultAddress = address(managerContract.vault());

        // Initialize the existing vault contract
        vault = IVault(vaultAddress);
        IUniswapV3Pool pool = vault.pool();

        address token0Address = pool.token0();

        token0 = IERC20(token0Address);  
        token1 = IERC20(pool.token1());    

        testLargePurchaseTriggerShift();  
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

    function testRollLoan() public {
        uint256 borrowAmount = 100 ether;

        vm.prank(deployer);
        token0.approve(vaultAddress, MAX_INT);

        // Borrow first
        vm.prank(deployer);
        vault.borrow(deployer, borrowAmount);
        
        uint256 balanceBeforePaybackToken1 = token1.balanceOf(deployer);
        uint256 balanceBeforePaybackToken0 = token0.balanceOf(deployer);

        // trigger shift
        testLargePurchaseTriggerShift();

        // Pay back part of the loan
        vm.prank(deployer);
        token1.approve(vaultAddress, MAX_INT);

        vm.prank(deployer);
        vault.roll(deployer);

        // check if the loan amount is deducted from the user's balance
        // assertEq(balanceBeforePaybackToken1 - token1.balanceOf(deployer), borrowAmount);
        // // check if the borrowed amount is reduced by the payback amount
        assertLt(balanceBeforePaybackToken0, token0.balanceOf(deployer));

    }    

    function testLargePurchaseTriggerShift() public {
        IDOManager managerContract = IDOManager(idoManager);
        BaseVault vault = managerContract.vault();
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint16 totalTrades = 500;
        uint256 tradeAmount = 200 ether;

        IWETH(WETH).deposit{ value: (tradeAmount * totalTrades)}();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        uint256 tokenBalanceBefore = noma.balanceOf(address(this));
        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            if (i >= 4) {
                spotPrice = spotPrice + (spotPrice * i / 100);
            }
            managerContract.buyTokens(spotPrice, tradeAmount, deployer);
        }
        
        uint256 nextFloorPrice = getNextFloorPrice(pool, address(vault));
        console.log("Next floor price is: ", nextFloorPrice);

        uint256 liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));
        console.log("Liquidity ratio is: ", liquidityRatio);

        if (liquidityRatio < 0.98e18) {
            console.log("Attempt to shift positions");
            IVault(address(vault)).shift();
            nextFloorPrice = getNextFloorPrice(pool, address(vault));
            console.log("Next floor price (after shift) is: ", nextFloorPrice);
            // solvencyInvariant();
        } else {
            revert(
                string(
                    abi.encodePacked(
                        "no shift triggered: ", 
                        Utils._uint2str(liquidityRatio)
                    )
                )
            );
        }
    }

    function getNextFloorPrice(address pool, address vault) public view returns (uint256) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, vault);
        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, vault, positions[1], LiquidityType.Anchor);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, vault, positions[0]);

        return DecimalMath.divideDecimal(floorBalance, circulatingSupply > anchorCapacity ? circulatingSupply - anchorCapacity : circulatingSupply);
    }

}
