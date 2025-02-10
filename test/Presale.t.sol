// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { PresaleDeployParams } from "../src/types/Types.sol";

contract PresaleTest is Test {

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    PresaleDeployParams params;

    error InvalidParameters();

    function setUp() public {
        
        PresaleDeployParams memory params = PresaleDeployParams({ 
            deployer: 0xcC91EB5D1AB2D577a64ACD71F0AA9C5cAf35D111, 
            vaultAddress: 0xA000E35B1D1BC68BfB26a72Fe3E4F34BB9185a9e, 
            pool: 0x48aEB161773D98528fa133fAfb5508D8B614fFBb, 
            softCap: 1000000000000000000, 
            initialPrice: 1250000000000000000, 
            deadline: 7776000, 
            name: "MY TOKEN 2", 
            symbol: "MINE", 
            decimals: 18, 
            tickSpacing: 60, 
            floorPercentage: 10, 
            totalSupply: 100000000000000000000
        });
    
        params = params;
        mathTest(params);
    }

    function mathTest(PresaleDeployParams memory params) public {

        uint256 softCap = params.softCap;
        uint256 initialPrice = params.initialPrice;
        uint256 deadline = params.deadline;
        int24   tickSpacing = params.tickSpacing;
        uint256 launchSupply = params.totalSupply;
        uint256 floorPercentage = params.floorPercentage;

        uint256 floorToken1Amount = (((launchSupply * floorPercentage / 100)) / initialPrice) * 10 ** 18 ; 

        console.log("floorToken1Amount: ", floorToken1Amount);
        console.log("launchSupply: ", launchSupply);
        console.log("softCap: ", softCap);
        console.log("initialPrice: ", initialPrice);
        console.log("deadline: ", deadline);

        if (softCap > (floorToken1Amount * 40/100)) revert InvalidParameters();
    }

    function testTest() public {
        console.log("Test");
    }

}
