// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {IQuoter} from "@uniswap/v3-periphery/interfaces/IQuoter.sol";

import {Deployer} from "../src/Deployer.sol";
import {Vault} from  "../src/Vault.sol";
import {NomaToken} from  "../src/token/NomaToken.sol";
import {ModelHelper} from  "../src/ModelHelper.sol";
import {Underlying } from  "../src/libraries/Underlying.sol";
import {LiquidityType, LiquidityPosition} from "../src/Types.sol";
import {DecimalMath} from "../src/libraries/DecimalMath.sol";
import {Conversions} from "../src/libraries/Conversions.sol";
 
interface IWETH {
    function balanceOf(address account) external view returns (uint256);
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
}

interface IDOManager {
    function vault() external view returns (Vault);
    function buyTokens(uint256 price, uint256 amount, address receiver) external;
    function sellTokens(uint256 price, uint256 amount, address receiver) external;
}

interface IVault {
    function getPositions() external view returns (LiquidityPosition[3] memory);
    function shift() external;
    function slide() external;
}
 
contract Invariants is Test {
    // Get environment variables.
    address feeTo = vm.envAddress("FEE_TO");
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    bytes32 salt = keccak256(bytes(vm.envString("SALT")));

    // Constants
    address WETH = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
    
    // Protocol addresses
    address payable idoManager = payable(0xA1f98d493FA64c8Be923dc4A3cdd98B6f5D82f9F);
    address nomaToken = 0x5F4D2D020bDF4d01fFf90e9B6B8bDa3b287595e8;
    address deployerContract = 0xD45a7B3a64BE300146f9c9560dEBa8eC38330211;
    address modelHelperContract = 0x66D5AD70105945D4B551fEE8f6aB60F34E298Aba;
    address quoterAddress = 0xb27308f9F90d607463e3F2FA3b3e3F7B3F0F2fa3;

    NomaToken private noma;
    ModelHelper private modelHelper;

    function setUp() public {
        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");

        noma = NomaToken(nomaToken);
        require(address(noma) != address(0), "Noma token address is zero");
        
        modelHelper = ModelHelper(modelHelperContract);
    }

    
    // function testBoughtTokensMatchCirculating() public {
    //     vm.recordLogs();
    //     vm.startBroadcast(privateKey);

    //     IDOManager managerContract = IDOManager(idoManager);
    //     Vault vault = managerContract.vault();
    //     address pool = address(vault.pool());

    //     (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
    //     uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
    //     uint8 totalTrades = 1;

    //     // Simulating a deposit and transfer to the IDO manager contract
    //     IWETH(WETH).deposit{ value: 10 ether }();
    //     IWETH(WETH).transfer(idoManager, 1 ether * totalTrades);

    //     uint256 tokenBalanceBefore = noma.balanceOf(address(this));

    //     for (uint i = 0; i < totalTrades; i++) {
    //         // Buy tokens using the manager contract
    //         managerContract.buyTokens(spotPrice, 1 ether, address(this));
    //     }
        
    //     // Check the new token balance after buying
    //     uint256 tokenBalanceAfter = noma.balanceOf(address(this));
    //     console.log("Token balance after buying is %s", tokenBalanceAfter);

    //     // Check that the token balance has increased after buying
    //     // Utils.testLessThan(tokenBalanceBefore, tokenBalanceAfter);


    //     // uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault));

    //     // assertEq(tokenBalanceAfter + 4, circulatingSupply, "Circulating supply does not match bought tokens");

    //     // console.log("Circulating supply is: ", circulatingSupply);
    //     vm.stopBroadcast();
    // }

    function testCirculatingSupply() public {
        IDOManager managerContract = IDOManager(idoManager);

        vm.recordLogs();
        vm.startBroadcast(privateKey);

        Vault vault = managerContract.vault();
        address pool = address(vault.pool());

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault));

        console.log("Circulating supply is: ", circulatingSupply);
        vm.stopBroadcast();
    }

    // function testTotalSupply() public {
    //     IDOManager managerContract = IDOManager(idoManager);

    //     vm.recordLogs();
    //     vm.startBroadcast(privateKey);

    //     // Check the total supply of the token
    //     uint256 totalSupply = noma.totalSupply();
    //     console.log("Total supply is %s", totalSupply);

    //     // Assert that the total supply is as expected
    //     assertEq(totalSupply, 100e18, "Total supply is not correct");

    //     vm.stopBroadcast();
    // }

    function testBuyTokens() public {
        IDOManager managerContract = IDOManager(idoManager);
        Vault vault = managerContract.vault();

        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice;

        uint8 numTrades = 2;
        uint256 tradeAmount = 0.005 ether;
        
        IWETH(WETH).deposit{ value:  tradeAmount * numTrades}();
        IWETH(WETH).transfer(idoManager, tradeAmount * numTrades);

        uint256 tokenBalanceBefore = noma.balanceOf(address(deployer));

        for (uint i = 0; i < numTrades; i++) {
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);

            managerContract.buyTokens(spotPrice, tradeAmount, address(deployer));
            uint256 tokenBalanceAfter = noma.balanceOf(address(deployer));
            
            uint256 receivedAmount = tokenBalanceAfter > tokenBalanceBefore 
                ? tokenBalanceAfter - tokenBalanceBefore
                : 0;

            console.log("Traded %s Ethereum, received %s tokens", (i + 1) * tradeAmount, receivedAmount);

            // Check that received amount is within 4% of tradeAmount
            // This requires knowing how many tokens we expect to receive per Ether
            // uint256 tradeAmount, address quoterAddress, address tokenIn, address tokenOut, uint24 poolFee
            // uint256 expectedAmount = getExpectedTokens(
            //     tradeAmount, 
            //     quoterAddress, 
            //     IUniswapV3Pool(pool).token0(), 
            //     IUniswapV3Pool(pool).token1(), 
            //     3000,
            //     sqrtPriceX96
            // );

            // console.log("Expected amount is: ", expectedAmount);
            // uint256 lowerBound = expectedAmount * 96 / 100; // 4% less than expected
            // uint256 upperBound = expectedAmount * 104 / 100; // 4% more than expected
            // require(
            //     receivedAmount >= lowerBound && receivedAmount <= upperBound,
            //     "Received token amount is outside the acceptable range"
            // );

            // Update tokenBalanceBefore for the next iteration
            // tokenBalanceBefore = tokenBalanceAfter;
        }
    }

    function testSellTokens() public {
        vm.recordLogs();
        vm.startBroadcast(privateKey);

        IDOManager managerContract = IDOManager(idoManager);

        Vault vault = managerContract.vault();
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);

        uint8 totalTrades = 2;
        uint256 tradeAmount = 1 ether;
        uint256 tradeAmountWETH = 1 ether;

        IWETH(WETH).deposit{ value:  tradeAmountWETH * totalTrades}();
        IWETH(WETH).transfer(idoManager, tradeAmountWETH * totalTrades);

        uint256 tokenBalanceBefore = noma.balanceOf(address(deployer));
        console.log("Token balance before buying is %s", tokenBalanceBefore);

        for (uint i = 0; i < totalTrades; i++) {
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            managerContract.buyTokens(spotPrice, tradeAmountWETH, address(deployer));
        }

        uint256 tokenBalanceBeforeSelling = noma.balanceOf(address(deployer));
        console.log("Token balance before selling is %s", tokenBalanceBeforeSelling);

        uint256 tokenToSend = tradeAmount * totalTrades;

        if (tokenBalanceBeforeSelling >= tokenToSend - (tokenToSend * 4/100)) {
            noma.transfer(idoManager, tokenBalanceBeforeSelling);
        } else {
            revert(Utils._uint2str(tokenBalanceBeforeSelling));
            revert("Not enough balance to sell");
        }

        // for (uint i = 0; i < totalTrades; i++) {
        //     spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        //     managerContract.sellTokens(spotPrice, tradeAmount, address(deployer));
        // }

         
        // // uint256 wethBalanceBefore = IWETH(WETH).balanceOf(address(deployer));
        // uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault));

        // console.log("Circulating supply is: ", circulatingSupplyBefore);

        // noma.transfer(idoManager, tokenBalanceBefore);

        // spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        // // Sell tokens using the manager contract
        // managerContract.sellTokens(spotPrice, tokenBalanceBefore, address(this));

        // uint256 circulatingSupplyAfter = modelHelper.getCirculatingSupply(pool, address(vault));
        // console.log("Circulating supply is: ", circulatingSupplyAfter);

        // uint256 delta = circulatingSupplyBefore - circulatingSupplyAfter;
        // console.log("Amount sold is %s", delta);
        
        // // test that remaining amount is less than 4% of initial amount
        // Utils.testLessThan(circulatingSupplyBefore - delta, 1e18 * 4 / 100);

        vm.stopBroadcast();
    }

    function testCirculatingSupplyMatchesBalances() public {
        IDOManager managerContract = IDOManager(idoManager);
        Vault vault = managerContract.vault();
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 2;
        uint256 tradeAmount = 0.005 ether;

        // Simulating a deposit and transfer to the IDO manager contract
        IWETH(WETH).deposit{ value: 10 ether }();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        uint256 tokenBalanceBefore = noma.balanceOf(address(this));
        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            // Buy tokens using the manager contract
            managerContract.buyTokens(spotPrice, tradeAmount, address(this));
        }
        
        // Check the new token balance after buying
        uint256 tokenBalanceAfter = noma.balanceOf(address(this));
        console.log("Token balance after buying is %s", tokenBalanceAfter);

        uint256 circulatingSupplyAfter = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyAfter);

        // Check that the token balance has increased after buying
        // Utils.testLessThan(tokenBalanceBefore, tokenBalanceAfter);

        // Check that the circulating supply matches the token balance after buying
        assertEq(tokenBalanceAfter + 3, circulatingSupplyAfter, "Circulating supply does not match bought tokens");
    }

    function testShiftAboveThreshold() public {
        IDOManager managerContract = IDOManager(idoManager);
        Vault vault = managerContract.vault();

        address pool = address(vault.pool());        
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 2;
        uint256 tradeAmount = 0.005 ether;


        // Simulating a deposit and transfer to the IDO manager contract
        IWETH(WETH).deposit{ value: 10 ether }();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            // Buy tokens using the manager contract
            managerContract.buyTokens(spotPrice, tradeAmount, address(deployer));
        }

        LiquidityPosition[3] memory positions = vault.getPositions();

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault));
        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, address(vault), positions[1]);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, address(vault), positions[0]);

        uint256 nextFloorPrice = DecimalMath.divideDecimal(floorBalance, circulatingSupply > anchorCapacity ? circulatingSupply - anchorCapacity : circulatingSupply);
        console.log("Next floor price is: ", nextFloorPrice);

        if (nextFloorPrice > 0.98e18) {

            console.log("Attempt to shift positions");
            vm.expectRevert(bytes4(0xe40aeaf5)); // custom error AboveThreshold()"
            vault.shift();

            // nextFloorPrice = getNextFloorPrice(pool, address(vault));
            // console.log("Next floor price (after shift) is: ", nextFloorPrice);
        }  
        
    }
    
    function testShiftBelowThreshold() public {
        IDOManager managerContract = IDOManager(idoManager);
        Vault vault = managerContract.vault();

        address pool = address(vault.pool());        
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 5;
        uint256 tradeAmount = 0.05 ether;

        // Simulating a deposit and transfer to the IDO manager contract
        IWETH(WETH).deposit{ value: 10 ether }();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            // Buy tokens using the manager contract
            managerContract.buyTokens(spotPrice, tradeAmount, address(deployer));
        }

        LiquidityPosition[3] memory positions = vault.getPositions();

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault));
        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, address(vault), positions[1]);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, address(vault), positions[0]);

        uint256 nextFloorPrice = DecimalMath.divideDecimal(floorBalance, circulatingSupply > anchorCapacity ? circulatingSupply - anchorCapacity : circulatingSupply);
        console.log("Next floor price is: ", nextFloorPrice);

        if (nextFloorPrice < 0.98e18) {
            console.log("Attempt to shift positions");
            vault.shift();
            nextFloorPrice = getNextFloorPrice(pool, address(vault));
            console.log("Next floor price (after shift) is: ", nextFloorPrice);     
            require(nextFloorPrice > 0.98e18, "Next floor price is below threshold");  
        }  
    }

    function getNextFloorPrice(address pool, address vault) public view returns (uint256) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, vault);
        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, vault, positions[1]);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, vault, positions[0]);

        return DecimalMath.divideDecimal(floorBalance, circulatingSupply - anchorCapacity);
    }

    function getPositions(address vault) public view returns (LiquidityPosition[3] memory) {
        return IVault(vault).getPositions();
    }

    function getExpectedTokens(
        uint256 tradeAmount, 
        address quoterAddress, 
        address tokenIn, 
        address tokenOut, 
        uint24 poolFee,
        uint160 sqrtPriceX96
    ) internal returns (uint256 expectedAmount) {
        IQuoter quoter = IQuoter(quoterAddress);
        
        expectedAmount = quoter
        .quoteExactInputSingle(
            tokenIn,
            tokenOut,
            poolFee,
            tradeAmount,
            sqrtPriceX96
        );
    }
    
}

library Utils {
    function testLessThan(uint256 a, uint256 b) public {
        // Use require to assert 'a' is less than 'b' with a custom error message
        require(a <= b, "Value 'a' should be less than 'b'.");
    } 
    
    function _uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }    
}