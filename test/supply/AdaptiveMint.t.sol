// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../../src/controllers/supply/AdaptiveSupply.sol";

contract AdaptiveMintTest is Test {
    AdaptiveSupply adaptiveMint;
    address vault = 0x1b26D84372D1F8699a3a71801B4CA757B95C9929;

    function setUp() public {
        adaptiveMint = new AdaptiveSupply();
    }

    function testLowVolatility() public returns (uint256) {
        uint256 deltaSupply = 1_000 ether; // Example delta supply
        uint256 timeElapsed = 7 days;      // Example time elapsed

        vm.prank(vault);
        uint256 mintAmount = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 2e18, 1e18);

        emit log_named_uint("Mint Amount (Low Volatility)", mintAmount);
        assertGt(mintAmount, 0, "Mint amount should be greater than 0 for low volatility");

        return mintAmount;
    }

    function testNormalVolatility() public returns (uint256) {
        uint256 deltaSupply = 1_000 ether; // Example delta supply
        uint256 timeElapsed = 7 days;      // Example time elapsed

        vm.prank(vault);
        uint256 mintAmount = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 4e18, 1e18);

        uint256 toMintLowVolatility = testLowVolatility();

        emit log_named_uint("Mint Amount (Normal Volatility)", mintAmount);

        assertGt(mintAmount, 0, "Mint amount should be greater than 0 for normal volatility");
        assertLt(toMintLowVolatility, mintAmount, "Mint amount should be more than low volatility");

        return mintAmount;
    }

    function testMediumVolatility() public returns (uint256) {
        uint256 deltaSupply = 1_000 ether; // Example delta supply
        uint256 timeElapsed = 1 days;      // Example time elapsed

        vm.prank(vault);
        uint256 mintAmount = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 6e18, 1e18);

        uint256 toMintNormalVolatility = testNormalVolatility();

        emit log_named_uint("Mint Amount (Medium Volatility)", mintAmount);

        assertGt(mintAmount, 0, "Mint amount should be greater than 0 for medium volatility");
        assertLt(toMintNormalVolatility, mintAmount, "Mint amount should be more than normal volatility");

        return mintAmount;
    }

    function testHighVolatility() public {
        uint256 deltaSupply = 1_000 ether; // Example delta supply
        uint256 timeElapsed = 12 hours;    // Example time elapsed

        vm.prank(vault);
        uint256 mintAmount = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 10e18, 1e18);

        uint256 toMintMediumVolatility = testMediumVolatility();

        emit log_named_uint("Mint Amount (High Volatility)", mintAmount);

        assertGt(mintAmount, 0, "Mint amount should be greater than 0 for high volatility");
        assertLt(toMintMediumVolatility, mintAmount, "Mint amount should be more than medium volatility");
    }

    function testRewardLogic() public {
        uint256 deltaSupply = 1_000 ether; // Example delta supply
        uint256 timeElapsed = 14 days;     // Example time elapsed

        vm.prank(vault);
        uint256 lowMint = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 2e18, 1e18);
        vm.prank(vault);
        uint256 normalMint = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed - 2 days, 4e18, 1e18);
        vm.prank(vault);
        uint256 mediumMint = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed - 3 days, 6e18, 1e18);
        vm.prank(vault);
        uint256 highMint = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed - 1 weeks, 10e18, 1e18);
        
        emit log_named_uint("Mint Amount (Low Volatility)", lowMint);
        emit log_named_uint("Mint Amount (Normal Volatility)", normalMint);
        emit log_named_uint("Mint Amount (Medium Volatility)", mediumMint);
        emit log_named_uint("Mint Amount (High Volatility)", highMint);

        assertLt(lowMint, normalMint, "Low volatility mint should be smaller than normal");
        assertLt(normalMint, mediumMint, "Normal volatility mint should be smaller than medium");
        assertLt(mediumMint, highMint, "Medium volatility mint should be smaller than high");
    }


}
