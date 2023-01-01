// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IVault.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {AmphorToken} from  "../src/token/AmphorToken.sol";
import {ModelHelper} from  "../src/model/Helper.sol";
import {BaseVault} from  "../src/vault/BaseVault.sol";
import {LendingVault} from  "../src/vault/LendingVault.sol";
import {Utils} from "../src/libraries/Utils.sol";
import {Conversions} from "../src/libraries/Conversions.sol";
import {Underlying } from  "../src/libraries/Underlying.sol";
import {DecimalMath} from "../src/libraries/DecimalMath.sol";
import {LiquidityType, LiquidityPosition} from "../src/types/Types.sol";

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

    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address payable idoManager = payable(0x7D6Cb1678d761C100566eC1D25ceC421e4F3A0a7);
    address nomaToken = 0x61F91A57677988def3dfD9c04b4411a023F105b8;
    address sNomaToken = 0x18Bb36A90984B43e8c5c07F461720394bA533134;
    address stakingContract = 0xeB0beC62AA5AB0e1dBEcDd8ae4CE70DAC36C1db3;
    address modelHelperContract = 0x0E90A3D616F9Fe2405325C3a7FB064837817F45F;
    address vaultAddress;

    uint256 MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 SECONDS_IN_DAY = 86400;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    AmphorToken private noma;
    ModelHelper private modelHelper;

    function setUp() public {
        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");

        noma = AmphorToken(nomaToken);
        require(address(noma) != address(0), "Noma token address is zero");
        
        modelHelper = ModelHelper(modelHelperContract);
        vaultAddress = address(managerContract.vault());

        console.log("Vault address is: ", vaultAddress);

        // Initialize the existing vault contract
        vault = IVault(vaultAddress);
        IUniswapV3Pool pool = vault.pool();

        token0 = IERC20(pool.token0());  
        token1 = IERC20(pool.token1());    

        testLargePurchaseTriggerShift();  
    }

    function testBorrow() public {
        uint256 borrowAmount = 1 ether;
        uint256 duration = 30 days;


        vm.prank(deployer);
        token0.approve(vaultAddress, MAX_INT);
        vm.stopPrank();

        uint256 allowance = token0.allowance(deployer, vaultAddress);
        uint256 balanceBeforeToken0 = token0.balanceOf(deployer);
        uint256 balanceBeforeToken1 = token1.balanceOf(deployer);

        vm.prank(deployer);
        vault.borrow(deployer, borrowAmount);

        uint256 fees = calculateLoanFees(borrowAmount, duration);

        assertEq(token1.balanceOf(deployer) - balanceBeforeToken1, borrowAmount - fees);
        assertLt(token0.balanceOf(deployer), balanceBeforeToken0);
    }

    function testPaybackLoan() public {
        testBorrow();

        uint256 borrowAmount = 1 ether;

        // Pay back part of the loan
        vm.prank(deployer);
        token1.approve(vaultAddress, MAX_INT);

        vm.prank(deployer);
        IWETH(WETH).deposit{ value: borrowAmount}();

        uint256 token1Balance = token1.balanceOf(deployer);
        console.log("Token1 balance before payback is: ", token1Balance);
        
        vm.prank(deployer);
        vault.payback(deployer);
 
        assertEq(token1Balance - borrowAmount, token1.balanceOf(deployer));
    }    

    function testRollLoan() public {
        uint256 borrowAmount = 5 ether;

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
        uint256 purchasePrice = spotPrice + (spotPrice * 1 / 100);

        uint16 totalTrades = 50;
        uint256 tradeAmount = 1 ether;

        IWETH(WETH).deposit{ value: (tradeAmount * totalTrades)}();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        uint256 tokenBalanceBefore = noma.balanceOf(address(this));
        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            purchasePrice = spotPrice + (spotPrice * i / 100);
            if (i >= 4) {
                spotPrice =  purchasePrice;
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
            solvency();
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

    function calculateLoanFees(uint256 borrowAmount, uint256 duration) public view returns (uint256 fees) {
        uint256 percentage = 27; // 0.027% 
        uint256 scaledPercentage = percentage * 10**12; 
        fees = (borrowAmount * scaledPercentage * (duration / SECONDS_IN_DAY)) / (100 * 10**18);
    }    
    
    function solvency() public view {
        IDOManager managerContract = IDOManager(idoManager);
        BaseVault vault = managerContract.vault();
        address pool = address(vault.pool());

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupply);

        uint256 intrinsicMinimumValue = modelHelper.getIntrinsicMinimumValue(address(vault));
        
        LiquidityPosition[3] memory positions =  LendingVault(address(vault)).getPositions();

        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, address(vault), positions[1], LiquidityType.Anchor);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, address(vault), positions[0]);
        
        uint256 floorCapacity = DecimalMath.divideDecimal(
            floorBalance, 
            intrinsicMinimumValue
        );

        console.log("IMV is: ", intrinsicMinimumValue);
        console.log("Anchor capacity is: ", anchorCapacity);
        console.log("Floor balance is: ", floorBalance);
        console.log("Floor capacity is: ", floorCapacity);
        console.log("Anchor capacity + floor balance is: ", anchorCapacity + floorBalance);
        console.log("Circulating supply is: ", circulatingSupply);

        // To guarantee solvency, Noma ensures that capacity > circulating supply each liquidity is deployed.
        require(anchorCapacity + floorCapacity > circulatingSupply, "Insolvency invariant failed");
    }
}
