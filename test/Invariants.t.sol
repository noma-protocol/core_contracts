// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";

import {Deployer} from "../src/Deployer.sol";
import {BaseVault} from  "../src/vault/BaseVault.sol";
import {ExtVault} from  "../src/vault/ExtVault.sol";
import {LendingVault} from  "../src/vault/LendingVault.sol";
import {NomaToken} from  "../src/token/NomaToken.sol";
import {ModelHelper} from  "../src/model/Helper.sol";
import {Underlying } from  "../src/libraries/Underlying.sol";
import {LiquidityType, LiquidityPosition} from "../src/types/Types.sol";
import {DecimalMath} from "../src/libraries/DecimalMath.sol";
import {Conversions} from "../src/libraries/Conversions.sol";
import {Utils} from "../src/libraries/Utils.sol";
import "../src/token/Gons.sol";
import "../src/staking/Staking.sol";

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

    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
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
        // Parse the data for network ID `1337`
        bytes memory data = vm.parseJson(json, string.concat(string("."), networkId));

        // Decode the data into the ContractAddresses struct
        ContractAddressesJson memory addresses = abi.decode(data, (ContractAddressesJson));
        
        // Log parsed addresses for verification
        console2.log("Model Helper Address:", addresses.ModelHelper);

        // Extract addresses from JSON
        idoManager = payable(addresses.IDOHelper);
        nomaToken = addresses.Proxy;
        modelHelperContract = addresses.ModelHelper;

        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");

        NOMA = NomaToken(nomaToken);
        require(address(NOMA) != address(0), "Noma token address is zero");

        // sNOMA = GonsToken(sNomaToken);
        // require(address(sNOMA) != address(0), "sNoma token address is zero");

        // staking = Staking(stakingContract);
        // require(address(staking) != address(0), "Staking contract address is zero");
        
        modelHelper = ModelHelper(modelHelperContract);
    }

    function testCirculatingSupply() public {     
        IDOManager managerContract = IDOManager(idoManager);
        LendingVault vault = LendingVault(address(managerContract.vault()));

        address pool = address(vault.pool());

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault));

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
        LendingVault vault = LendingVault(address(managerContract.vault()));
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 2;
        uint256 tradeAmount = 0.005 ether;

        IWETH(WETH).deposit{ value: 10 ether }();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        uint256 tokenBalanceBefore = NOMA.balanceOf(address(this));
        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            managerContract.buyTokens(spotPrice, tradeAmount, address(this));
        }
        
        uint256 tokenBalanceAfter = NOMA.balanceOf(address(this));
        console.log("Token balance after buying is %s", tokenBalanceAfter);

        uint256 circulatingSupplyAfter = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyAfter);

        // adapt for 1 wei discrepance
        assertApproxEqAbs(tokenBalanceAfter + circulatingSupplyBefore, circulatingSupplyAfter, 2 wei , "Circulating supply does not match bought tokens");
    }

    // function testInvariantWithStakeUnstakeAndRebases() public {
    //     vm.startBroadcast(privateKey);

    //     staking.stake(deployer, 1_000e18);
        
    //     vm.prank(vault);
    //     staking.notifyRewardAmount(0);

    //     // Simulate multiple rebases
    //     uint256 rewardAmount = 1000e18;
    //     for (uint i = 0; i < 10; i++) {
    //         NOMA.mint(address(staking), rewardAmount);
    //         vm.prank(vault);
    //         staking.notifyRewardAmount(rewardAmount);
    //     }

    //     // All users unstake
    //     for (uint i = 0; i < NUM_USERS; i++) {
    //         uint256 sNOMABalanceBefore = sNOMA.balanceOf(users[i]);
    //         uint256 NOMABalanceBefore = NOMA.balanceOf(users[i]);

    //         vm.prank(users[i]);
    //         sNOMA.approve(address(staking), type(uint256).max);
    //         staking.unstake(users[i]);

    //         assertEq(sNOMA.balanceOf(users[i]), 0, "sNOMA balance should be 0 after unstake");
    //         assertEq(NOMA.balanceOf(users[i]), NOMABalanceBefore + sNOMABalanceBefore, "NOMA balance incorrect after unstake");
    //     }

    //     // Check if staking contract has enough NOMA to cover all unstakes
    //     uint256 circulatingSupply = sNOMA.totalSupply() - sNOMA.balanceOf(address(staking));
    //     uint256 stakingNOMABalance = NOMA.balanceOf(address(staking));
    //     uint256 initialStakingBalance = sNOMA.balanceForGons(INITIAL_FRAGMENTS_SUPPLY);
    //     uint256 availableNOMA = stakingNOMABalance > initialStakingBalance ? stakingNOMABalance - initialStakingBalance : 0;

    //     // console.log("Circulating sNOMA supply:", circulatingSupply);
    //     // console.log("Staking contract NOMA balance:", stakingNOMABalance);
    //     // console.log("Initial staking balance (in current sNOMA terms):", initialStakingBalance);
    //     // console.log("Available NOMA for unstaking:", availableNOMA);

    //     assertGe(availableNOMA, circulatingSupply, "Staking contract should have enough NOMA to cover all circulating sNOMA");
    // }

    function testBuyTokens() public {
        vm.recordLogs();
        vm.startBroadcast(privateKey);
        
        IDOManager managerContract = IDOManager(idoManager);
        LendingVault vault = LendingVault(address(managerContract.vault()));

        address pool = address(vault.pool());

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(vault.pool()).slot0();
        uint8 numTrades = 100;
        uint256 tradeAmount = 1 ether;
        
        IWETH(WETH).deposit{ value:  tradeAmount * numTrades}();
        IWETH(WETH).transfer(idoManager, tradeAmount * numTrades);

        uint256 tokenBalanceBefore = NOMA.balanceOf(address(deployer));
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 1 / 100);

        for (uint i = 0; i < numTrades; i++) {
            (sqrtRatioX96,,,,,,) = IUniswapV3Pool(vault.pool()).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);
            purchasePrice = spotPrice + (spotPrice * 1 / 100);

            managerContract.buyTokens(purchasePrice, tradeAmount, address(deployer));
            uint256 tokenBalanceAfter = NOMA.balanceOf(address(deployer));
            
            uint256 receivedAmount = tokenBalanceAfter > tokenBalanceBefore 
                ? tokenBalanceAfter - tokenBalanceBefore
                : 0;

            // console.log("Traded %s Ethereum, received %s tokens", (i + 1) * tradeAmount, receivedAmount);

        }
        vm.stopBroadcast();
    }

    function testSellTokens() public {
        vm.recordLogs();
        vm.startBroadcast(privateKey);

        IDOManager managerContract = IDOManager(idoManager);

        LendingVault vault = LendingVault(address(managerContract.vault()));
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 1 / 100);

        console.log("Spot price is: ", spotPrice);

        uint8 totalTradesBuy = 24;
        uint256 tradeAmountWETH = 2 ether;

        IWETH(WETH).deposit{ value:  tradeAmountWETH * totalTradesBuy}();
        IWETH(WETH).transfer(idoManager, tradeAmountWETH * totalTradesBuy);

        uint256 tokenBalanceBefore = NOMA.balanceOf(address(deployer));
        console.log("Token balance before buying is %s", tokenBalanceBefore);

        for (uint i = 0; i < totalTradesBuy; i++) {
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            purchasePrice = spotPrice + (spotPrice * i / 100);

            if (i >= 4) {
                spotPrice = purchasePrice;
            }
            managerContract.buyTokens(spotPrice, tradeAmountWETH, address(deployer));

        }

        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        console.log("Spot price is: ", spotPrice);

        uint256 tokenBalanceBeforeSelling = NOMA.balanceOf(address(deployer));
        console.log("Token balance before selling is %s", tokenBalanceBeforeSelling);

        NOMA.transfer(idoManager, tokenBalanceBeforeSelling);

        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        managerContract.sellTokens(spotPrice - (spotPrice * 15/100), tokenBalanceBeforeSelling, address(deployer));

        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        console.log("Spot price is: ", spotPrice);

        vm.stopBroadcast();
    }

    function testLargePurchaseTriggerShift() public {
        IDOManager managerContract = IDOManager(idoManager);
        LendingVault vault = LendingVault(address(managerContract.vault()));
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 1 / 100);

        uint16 totalTrades = 50;
        uint256 tradeAmount = 1 ether;

        IWETH(WETH).deposit{ value: (tradeAmount * totalTrades)}();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        uint256 tokenBalanceBefore = NOMA.balanceOf(address(this));
        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            purchasePrice = spotPrice + (spotPrice * 1 / 100);
            if (i >= 4) {
                spotPrice = purchasePrice;
            }
            managerContract.buyTokens(spotPrice, tradeAmount, address(this));
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

    function testShiftAboveThreshold() public {
        IDOManager managerContract = IDOManager(idoManager);
        LendingVault vault = LendingVault(address(managerContract.vault()));

        address pool = address(vault.pool());        
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 2;
        uint256 tradeAmount = 0.005 ether;

        IWETH(WETH).deposit{ value: 10 ether }();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            managerContract.buyTokens(spotPrice, tradeAmount, address(deployer));
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
    
    function testShiftBelowThreshold() public {
        IDOManager managerContract = IDOManager(idoManager);
        LendingVault vault = LendingVault(address(managerContract.vault()));

        address pool = address(vault.pool());        
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 5;
        uint256 tradeAmount = 0.05 ether;

        IWETH(WETH).deposit{ value: 10 ether }();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            managerContract.buyTokens(spotPrice, tradeAmount, address(deployer));
        }

        LiquidityPosition[3] memory positions = LendingVault(address(vault)).getPositions();

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault));
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
    
    function testSlide() public {
        IDOManager managerContract = IDOManager(idoManager);
        LendingVault vault = LendingVault(address(managerContract.vault()));
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 1 / 100);

        uint16 totalTrades = 100;
        uint256 tradeAmount = 1 ether;

        IWETH(WETH).deposit{ value: tradeAmount * totalTrades }();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            purchasePrice = spotPrice + (spotPrice * i / 100);
            if (i >= 4) {
                spotPrice = purchasePrice;
            }
            managerContract.buyTokens(spotPrice, tradeAmount, address(this));
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
            spotPrice - (spotPrice * 10/100), 
            tokenBalanceBeforeSelling, 
            address(deployer)
        );

        liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));
        console.log("Liquidity ratio is: ", liquidityRatio);

        if (liquidityRatio > 1.15e18) {
            console.log("Attempt to slide positions");
            IVault(address(vault)).slide();
            solvencyInvariant();
        } else {
            revert("No slide triggered");
        
        }

    }

    function getNextFloorPrice(address pool, address vault) public view returns (uint256) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, vault);
        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, vault, positions[1], LiquidityType.Anchor);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, vault, positions[0]);

        return DecimalMath.divideDecimal(floorBalance, circulatingSupply > anchorCapacity ? circulatingSupply - anchorCapacity : circulatingSupply);
    }

    function solvencyInvariant() public view {
        IDOManager managerContract = IDOManager(idoManager);
        LendingVault vault = LendingVault(address(managerContract.vault()));
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

    // function getPositions(address vault) public view returns (LiquidityPosition[3] memory) {
    //     return IVault(vault).getPositions();
    // }
    
}
