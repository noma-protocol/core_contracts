// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";

import {Deployer} from "../src/Deployer.sol";
import {BaseVault} from  "../src/vault/BaseVault.sol";
import {ExtVault} from  "../src/vault/ExtVault.sol";
import {IVault} from  "../src/interfaces/IVault.sol";
import {NomaToken} from  "../src/token/NomaToken.sol";
import {ModelHelper} from  "../src/model/Helper.sol";
import {Underlying } from  "../src/libraries/Underlying.sol";
import {LiquidityType, LiquidityPosition} from "../src/types/Types.sol";
import {DecimalMath} from "../src/libraries/DecimalMath.sol";
import {Conversions} from "../src/libraries/Conversions.sol";
import {Utils} from "../src/libraries/Utils.sol";
import {IQuoterV2} from "./Quoter/IQuoterV2.sol";

import "../src/token/Gons.sol";
import "../src/staking/Staking.sol";

interface IWETH {
    function balanceOf(address account) external view returns (uint256);
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
}

interface IDOManager {
    function vault() external view returns (BaseVault);
    function buyTokens(uint256 price, uint256 amount, uint256 minAmount, address receiver) external;
    function sellTokens(uint256 price, uint256 amount, address receiver) external;
    function modelHelper() external view returns (address);
}

struct ContractAddressesJson {
    address Factory;
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}
 
contract Invariants is Test {
    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    address WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address private uniswapFactory = 0x204FAca1764B154221e35c0d20aBb3c525710498;
    // address quoterV2 = 0x74b06eFA24F39C60AA7F61BD516a3eaf39613D57; // PancakeSwap QuoterV2
    address quoterV2 = 0x661E93cca42AfacB172121EF892830cA3b70F08d; // Uniswap V3 QuoterV2

    address payable idoManager;
    address nomaToken;
    address modelHelperContract;
    address vaultAddress;

    NomaToken private NOMA;
    GonsToken sNOMA;

    ModelHelper private modelHelper;
    Staking staking;

    function setUp() public {
        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");

        // Read the JSON file
        string memory json = vm.readFile(path);
        string memory networkId = "1337";

        // Parse individual fields to avoid struct ordering issues
        idoManager = payable(vm.parseJsonAddress(json, string.concat(".", networkId, ".IDOHelper")));
        nomaToken = vm.parseJsonAddress(json, string.concat(".", networkId, ".Proxy"));
        modelHelperContract = vm.parseJsonAddress(json, string.concat(".", networkId, ".ModelHelper"));

        // Log parsed addresses for verification
        console2.log("Model Helper Address:", modelHelperContract);

        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");

        NOMA = NomaToken(nomaToken);
        require(address(NOMA) != address(0), "Noma token address is zero");
        
        modelHelper = ModelHelper(modelHelperContract);
    }

    function testCirculatingSupply() public {     
        IDOManager managerContract = IDOManager(idoManager);
        IVault vault = IVault(address(managerContract.vault()));

        address pool = address(vault.pool());

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault), false);

        console.log("Circulating supply is: ", circulatingSupply);
    }

    function testTotalSupply() public {
        IDOManager managerContract = IDOManager(idoManager);

        vm.recordLogs();
        vm.startBroadcast(privateKey);

        uint256 totalSupply = NOMA.totalSupply();
        console.log("Total supply is %s", totalSupply);

        require(totalSupply >= 1e20, "Total supply is less than expected");
        vm.stopBroadcast();
    }

    function testCirculatingSupplyMatchesBalances() public {
        IDOManager managerContract = IDOManager(idoManager);
        IVault vault = IVault(address(managerContract.vault()));
        address pool = address(vault.pool());
        IUniswapV3Pool poolContract = IUniswapV3Pool(IVault(address(vault)).pool());  

        bytes memory swapPath = _encodePath(
            poolContract.token1(),
            poolContract.token0(),
            3000
        );
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 2;
        uint256 tradeAmount = 0.005 ether;

        IWETH(WMON).deposit{ value: 10 ether }();
        IWETH(WMON).transfer(idoManager, tradeAmount * totalTrades);

        uint256 tokenBalanceBefore = NOMA.balanceOf(address(this));
        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault), false);
        console.log("Circulating supply is: ", circulatingSupplyBefore);
        uint256 purchasePrice = spotPrice + (spotPrice * 25 / 100);

        for (uint i = 0; i < totalTrades; i++) {
            (uint256 quote,,,) = IQuoterV2(quoterV2).quoteExactInput(swapPath, 1e18);

            managerContract.buyTokens(purchasePrice, tradeAmount, quote, address(this));
        }
        
        uint256 tokenBalanceAfter = NOMA.balanceOf(address(this));
        console.log("Token balance after buying is %s", tokenBalanceAfter);

        uint256 circulatingSupplyAfter = modelHelper.getCirculatingSupply(pool, address(vault), false);
        console.log("Circulating supply is: ", circulatingSupplyAfter);

        // adapt for 1 wei discrepance
        assertApproxEqAbs(tokenBalanceAfter + circulatingSupplyBefore, circulatingSupplyAfter, 2 wei , "Circulating supply does not match bought tokens");
    }


    function testBuyTokens() public {
        vm.recordLogs();
        vm.startBroadcast(privateKey);
        
        IDOManager managerContract = IDOManager(idoManager);
        IVault vault = IVault(address(managerContract.vault()));
        IUniswapV3Pool poolContract = IUniswapV3Pool(IVault(address(vault)).pool());  
        
        bytes memory swapPath = _encodePath(
            poolContract.token1(),
            poolContract.token0(),
            3000
        );

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(vault.pool()).slot0();
        uint16 numTrades = 1000;
        uint256 tradeAmount = 0.00003785 ether;
        
        IWETH(WMON).deposit{ value:  tradeAmount * numTrades}();
        IWETH(WMON).transfer(idoManager, tradeAmount * numTrades);

        uint256 tokenBalanceBefore = NOMA.balanceOf(address(deployer));
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 25 / 100);

        for (uint i = 0; i < numTrades; i++) {
            (sqrtRatioX96,,,,,,) = IUniswapV3Pool(vault.pool()).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);
            purchasePrice = spotPrice + (spotPrice * 25 / 100);

            (uint256 quote,,,) = IQuoterV2(quoterV2).quoteExactInput(swapPath, 1e18);

            console.log("Quote for 1 token0 to token1: ", quote);

            managerContract.buyTokens(purchasePrice, tradeAmount, quote, address(deployer));
            uint256 tokenBalanceAfter = NOMA.balanceOf(address(deployer));
            
            uint256 receivedAmount = tokenBalanceAfter > tokenBalanceBefore 
                ? tokenBalanceAfter - tokenBalanceBefore
                : 0;

            console.log("Traded %s Ethereum, received %s tokens", (i + 1) * tradeAmount, receivedAmount);

        }
        vm.stopBroadcast();
    }

    function testSellTokens() public {
        vm.recordLogs();
        vm.startBroadcast(privateKey);

        IDOManager managerContract = IDOManager(idoManager);

        IVault vault = IVault(address(managerContract.vault()));
        address pool = address(vault.pool());
        IUniswapV3Pool poolContract = IUniswapV3Pool(IVault(address(vault)).pool());  

        address token0 = poolContract.token0();
        address token1 = poolContract.token1();

        bytes memory swapPath = _encodePath(
            token1,
            token0,
            3000
        );
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 1 / 100);

        console.log("Spot price is: ", spotPrice);

        uint8 totalTradesBuy = 1;
        uint256 tradeAmountWETH = 50 ether;

        IWETH(WMON).deposit{ value:  tradeAmountWETH * totalTradesBuy}();
        IWETH(WMON).transfer(idoManager, tradeAmountWETH * totalTradesBuy);

        uint256 tokenBalanceBefore = NOMA.balanceOf(address(deployer));
        console.log("Token balance before buying is %s", tokenBalanceBefore);

        for (uint i = 0; i < totalTradesBuy; i++) {
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            purchasePrice = spotPrice + (spotPrice * 25 / 100);

            // if (i >= 4) {
                spotPrice = purchasePrice;
            // }

            (uint256 quote,,,) = IQuoterV2(quoterV2).quoteExactInput(swapPath, 1e18);

            managerContract.buyTokens(spotPrice, tradeAmountWETH, quote, address(deployer));

        }

        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        console.log("Spot price is: ", spotPrice);

        uint256 tokenBalanceBeforeSelling = NOMA.balanceOf(address(deployer));
        console.log("Token balance before selling is %s", tokenBalanceBeforeSelling);

        NOMA.transfer(idoManager, tokenBalanceBeforeSelling);

        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        purchasePrice = spotPrice - (spotPrice * 25 / 100);

    // if (i >= 4) {
        spotPrice = purchasePrice;
        managerContract.sellTokens(spotPrice ,tokenBalanceBeforeSelling, address(deployer));

        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        console.log("Spot price is: ", spotPrice);

        vm.stopBroadcast();
    }

    function _testLargePurchaseTriggerShift() public {
        IDOManager managerContract = IDOManager(idoManager);
        IVault vault = IVault(address(managerContract.vault()));
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 5 / 100);

        uint16 totalTrades = 1;
        uint256 tradeAmount = 1 ether;

        IWETH(WMON).deposit{ value: (tradeAmount * totalTrades)}();
        IWETH(WMON).transfer(idoManager, tradeAmount * totalTrades);

        uint256 tokenBalanceBefore = NOMA.balanceOf(address(this));
        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault), false);
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            purchasePrice = spotPrice + (spotPrice * 5 / 100);
            if (i >= 4) {
                spotPrice = purchasePrice;
            }
            managerContract.buyTokens(spotPrice, tradeAmount, 0, address(this));
        }
        
        uint256 nextFloorPrice = getNextFloorPrice(pool, address(vault));
        console.log("Next floor price is: ", nextFloorPrice);

        uint256 liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));
        console.log("Liquidity ratio is: ", liquidityRatio);

        if (liquidityRatio < 0.90e18) {
            console.log("Attempt to shift positions");
            IVault(address(vault)).shift();
            nextFloorPrice = getNextFloorPrice(pool, address(vault));
            console.log("Next floor price (after shift) is: ", nextFloorPrice);
            solvencyInvariant();
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

    function _testShiftAboveThreshold() public {
        IDOManager managerContract = IDOManager(idoManager);
        IVault vault = IVault(address(managerContract.vault()));

        address pool = address(vault.pool());        
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 2;
        uint256 tradeAmount = 0.005 ether;

        IWETH(WMON).deposit{ value: 10 ether }();
        IWETH(WMON).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            managerContract.buyTokens(spotPrice, tradeAmount, 0, address(deployer));
        }

        uint256 nextFloorPrice = getNextFloorPrice(pool, address(vault));
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));
        console.log("Liquidity ratio is: ", liquidityRatio);

        if (liquidityRatio > 0.98e18) {

            console.log("Attempt to shift positions");
            // custom error AboveThreshold()"
            vm.expectRevert(bytes4(0xe40aeaf5));
            IVault(address(vault)).shift();
            solvencyInvariant();
        }  
        
    }
    
    function _testShiftBelowThreshold() public {
        IDOManager managerContract = IDOManager(idoManager);
        IVault vault = IVault(address(managerContract.vault()));

        address pool = address(vault.pool());        
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 5;
        uint256 tradeAmount = 0.05 ether;

        IWETH(WMON).deposit{ value: 10 ether }();
        IWETH(WMON).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            managerContract.buyTokens(spotPrice, tradeAmount, 0, address(deployer));
        }

        LiquidityPosition[3] memory positions = IVault(address(vault)).getPositions();

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault), false);
        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, address(vault), positions[1], LiquidityType.Anchor);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, address(vault), positions[0]);

        uint256 nextFloorPrice = DecimalMath.divideDecimal(floorBalance, circulatingSupply > anchorCapacity ? circulatingSupply - anchorCapacity : circulatingSupply);
        console.log("Next floor price is: ", nextFloorPrice);

        uint256 liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));
        console.log("Liquidity ratio is: ", liquidityRatio);

        if (liquidityRatio < 0.98e18) {
            console.log("Attempt to shift positions");
            IVault(address(vault)).shift();
            nextFloorPrice = getNextFloorPrice(pool, address(vault));
            console.log("Next floor price (after shift) is: ", nextFloorPrice);     
            require(nextFloorPrice > 0.98e18, "Next floor price is below threshold");  
        }  
    }
    
    function _testSlide() public {
        IDOManager managerContract = IDOManager(idoManager);
        IVault vault = IVault(address(managerContract.vault()));
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 1 / 100);

        uint16 totalTrades = 100;
        uint256 tradeAmount = 0.1 ether;

        IWETH(WMON).deposit{ value: tradeAmount * totalTrades }();
        IWETH(WMON).transfer(idoManager, tradeAmount * totalTrades);

        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault), false);
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            purchasePrice = spotPrice + (spotPrice * i / 100);
            if (i >= 4) {
                spotPrice = purchasePrice;
            }
            managerContract.buyTokens(spotPrice, tradeAmount, 0, address(this));
        }

        uint256 liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));

        if (liquidityRatio < 0.98e18) {
            console.log("Attempt to shift positions");
            IVault(address(vault)).shift();
        }
        
        uint256 tokenBalanceBeforeSelling = NOMA.balanceOf(address(this));
        console.log("Token balance before selling is %s", tokenBalanceBeforeSelling);

        NOMA.transfer(idoManager, tokenBalanceBeforeSelling);

        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);

        managerContract.sellTokens(
            spotPrice - (spotPrice * 15/100), 
            tokenBalanceBeforeSelling, 
            address(deployer)
        );

        uint256 tokenBalanceAfterSelling = NOMA.balanceOf(address(this));
        console.log("Token balance after selling is %s", tokenBalanceAfterSelling);

        liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));
        console.log("Liquidity ratio is: ", liquidityRatio);

        if (liquidityRatio > 1.2e18) {
            console.log("Attempt to slide positions");
            IVault(address(vault)).slide();
            solvencyInvariant();
        } else {
            revert("No slide triggered");
        
        }

    }

    // function testBumpFloor() public {
    //     IDOManager managerContract = IDOManager(idoManager);
    //     IVault vault = IVault(address(managerContract.vault()));
    //     address pool = address(vault.pool());

    //     uint256 imvBeforeShift = modelHelper.getIntrinsicMinimumValue(address(vault));

    //     testLargePurchaseTriggerShift();
    //     testLargePurchaseTriggerShift();
    //     testLargePurchaseTriggerShift();
    //     testLargePurchaseTriggerShift();

    //     uint256 imvAfterShift = modelHelper.getIntrinsicMinimumValue(address(vault));

    //     assertGe(imvAfterShift, imvBeforeShift, "IMV should not decrease after shift");

    //     (,,, uint256 anchorToken1Balance) = modelHelper
    //     .getUnderlyingBalances(
    //         address(pool), 
    //         address(vault), 
    //         LiquidityType.Anchor
    //     );

    //     vm.prank(deployer);
    //     IVault(address(vault)).bumpFloor(
    //         anchorToken1Balance / 2
    //     );

    //     uint256 imvAfterBump = modelHelper.getIntrinsicMinimumValue(address(vault));

    //     assertGe(imvAfterBump, imvAfterShift, "IMV should not decrease after bump");

        
    //     // test should fail 
    //     vm.prank(address(modelHelper));
    //     vm.expectRevert("NotAuthorized()");
    //     IVault(address(vault)).bumpFloor(
    //         anchorToken1Balance / 2
    //     );

    //     console.log("IMV after bump is: ", imvAfterBump);
    //     console.log("IMV before bump is: ", imvBeforeShift);
    //     console.log("IMV after shift is: ", imvAfterShift);
    //     console.log("Anchor token1 balance is: ", anchorToken1Balance);
    // }

    function getNextFloorPrice(address pool, address vault) public view returns (uint256) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, vault, false);
        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, vault, positions[1], LiquidityType.Anchor);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, vault, positions[0]);

        return DecimalMath.divideDecimal(floorBalance, circulatingSupply > anchorCapacity ? circulatingSupply - anchorCapacity : circulatingSupply);
    }

    function solvencyInvariant() public view {
        IDOManager managerContract = IDOManager(idoManager);
        IVault vault = IVault(address(managerContract.vault()));
        address pool = address(vault.pool());


        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault), false);
        console.log("Circulating supply is: ", circulatingSupply);

        uint256 intrinsicMinimumValue = modelHelper.getIntrinsicMinimumValue(address(vault));
        
        LiquidityPosition[3] memory positions =  IVault(address(vault)).getPositions();
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

    // function testQuoteExactOutput() public {
    //     address token0 = pool.token0();
    //     address token1 = pool.token1();

    //     bytes memory swapPath = _encodePath(
    //         token0,
    //         token1,
    //         2500
    //     );

    //    (uint256 quote,,,) = IQuoterV2(quoterV2).quoteExactOutput(swapPath, 1e18);

    //     console.log("Quote for 1 token0 to token1: ", quote);
    // }

    // function testQuoteExactInput() public {
    //     address token0 = pool.token0();
    //     address token1 = pool.token1();

    //     bytes memory swapPath = _encodePath(
    //         token1,
    //         token0,
    //         2500
    //     );

    //    (uint256 quote,,,) = IQuoterV2(quoterV2).quoteExactInput(swapPath, 1e18);

    //     console.log("Quote for 1 token0 to token1: ", quote);
    // }

    /// @notice Encode a single‐hop Uniswap V3 swap path
    /// @param tokenIn  address of the input token
    /// @param tokenOut address of the output token
    /// @param fee      pool fee, in hundredths of a bip (e.g. 500 = 0.05%, 3000 = 0.3%)
    /// @return path     the abi-packed path bytes ready for exactInput calls
    function _encodePath(
        address tokenIn,
        address tokenOut,
        uint24  fee
    ) internal pure returns (bytes memory path) {
        return abi.encodePacked(tokenIn, fee, tokenOut);
    }

    // function getPositions(address vault) public view returns (LiquidityPosition[3] memory) {
    //     return IVault(vault).getPositions();
    // }
    
}
