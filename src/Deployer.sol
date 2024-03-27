// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {Utils} from "./libraries/Utils.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {LiquidityOps} from "./libraries/LiquidityOps.sol";
import {LiquidityDeployer} from "./libraries/LiquidityDeployer.sol";

import {DeployHelper} from "./libraries/DeployHelper.sol";

import {
    feeTier,
    AmountsToMint, 
    tickSpacing, 
    LiquidityPosition, 
    LiquidityType, 
    DeployLiquidityParameters
} from "./Types.sol";

interface IVault {
    function initialize(
        LiquidityPosition memory _floorPosition,
        LiquidityPosition memory _anchorPosition,
        LiquidityPosition memory _discoveryPosition
    ) external;
}

contract Deployer is Owned {

    LiquidityPosition public floorPosition;
    LiquidityPosition public anchorPosition;
    LiquidityPosition public discoveryPosition;

    address vault;
    address public token0;
    address public token1;
    address private modelHelper;

    IUniswapV3Pool public pool;

    event FloorDeployed(LiquidityPosition position);
    event AnchorDeployed(LiquidityPosition position);
    event DiscoveryDeployed(LiquidityPosition position);

    constructor(
        address _vault, 
        address _pool,
        address _modelHelper
    ) Owned(msg.sender) {
        pool = IUniswapV3Pool(_pool);
        vault = _vault;
        token0 = pool.token0();
        token1 = pool.token1();
    }

    /**
     * @notice Uniswap V3 callback function, called back on pool.mint
     */
    function uniswapV3MintCallback(
        uint256 amount0Owed, 
        uint256 amount1Owed, 
        bytes calldata data
    )
        external
    {
        require(msg.sender == address(pool), "cc");

        uint256 token0Balance = ERC20(token0).balanceOf(address(this));
        uint256 token1Balance = ERC20(token1).balanceOf(address(this));

        // (uint256 code, string memory message) = abi.decode(data, (uint256, string));

        if (token0Balance >= amount0Owed) {

            if (amount0Owed > 0) ERC20(token0).transfer(msg.sender, amount0Owed);
            
            // if (code == 0 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
            //     floorPosition.amount0LowerBound = amount0Owed;
            // } else if (code == 1 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
            //     anchorPosition.amount0LowerBound = amount0Owed;
            // } else if (code == 2 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
            //     discoveryPosition.amount0LowerBound = amount0Owed;
            // }
        
        } else {
            // revert(
            //     string(
            //         abi.encodePacked(
            //             "insufficient token0 balance, owed: ", 
            //             Utils._uint2str(amount0Owed)
            //             )
            //         )
            //     );
        }

        if (token1Balance >= amount1Owed) {

            if (amount1Owed > 0) ERC20(token1).transfer(msg.sender, amount1Owed);

            // if (code == 0 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
            //     floorPosition.amount1UpperBound = amount1Owed;
            // } else if (code == 1 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
            //     anchorPosition.amount1UpperBound = amount1Owed;
            // } else if (code == 2 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
            //     discoveryPosition.amount1UpperBound = amount1Owed;
            // }      

        } else {
            // revert(
            //     string(
            //         abi.encodePacked("insufficient token1 balance, owed: ", 
            //         Utils._uint2str(amount1Owed)
            //         )
            //     )
            // );
        }
    }

    function deployFloor(uint256 _floorPrice) public initialized /*onlyOwner*/ {
        
        (LiquidityPosition memory newPosition,) = 
        DeployHelper
        .deployFloor(
            pool, 
            vault, 
            _floorPrice, 
            tickSpacing
        );

        floorPosition = newPosition;
        emit FloorDeployed(newPosition);
    }

    function deployAnchor(uint256 bips, uint256 bipsBelowSpot) public initialized /*onlyOwner*/ {

        (LiquidityPosition memory newPosition,) = LiquidityDeployer
        .deployAnchor(
            address(pool),
            vault,
            floorPosition,
            DeployLiquidityParameters({
                bips: bips,
                bipsBelowSpot: bipsBelowSpot,
                tickSpacing: tickSpacing,
                lowerTick: 0,
                upperTick: 0
            }),
            false
        );

        anchorPosition = newPosition;
        emit AnchorDeployed(newPosition);
    }

    function doDeployPosition(
        address pool,
        address receiver,
        int24 lowerTick,
        int24 upperTick,
        LiquidityType liquidityType,
        AmountsToMint memory amounts
    ) public returns (LiquidityPosition memory newPosition) {
        return LiquidityDeployer
        .doDeployPosition(
            address(pool),
            receiver,
            lowerTick,
            upperTick,
            liquidityType,
            amounts
        );
    }

    function deployDiscovery(uint256 upperDiscoveryPrice) public initialized /*onlyOwner*/ 
    returns (LiquidityPosition memory newPosition, LiquidityType liquidityType) {

        (newPosition,) = LiquidityDeployer
        .deployDiscovery(
            address(pool), 
            vault,
            anchorPosition, 
            upperDiscoveryPrice, 
            tickSpacing
        );

        liquidityType = LiquidityType.Discovery;
        discoveryPosition = newPosition;
        emit DiscoveryDeployed(newPosition);
    }
 
    function shiftFloor(
        address _pool,
        address receiver,
        uint256 newPrice,
        LiquidityPosition memory _floorPosition
    ) public  returns (LiquidityPosition memory newPosition) {

        return LiquidityDeployer.shiftFloor(_pool, receiver, newPrice, _floorPosition);
    }

    function finalize() public initialized /*onlyOwner*/ {
        require(
            floorPosition.upperTick != 0 &&
            anchorPosition.upperTick != 0 &&
            discoveryPosition.upperTick != 0, 
            "not deployed"
        );

        // ERC20(token0).transfer(vault, ERC20(token0).balanceOf(address(this)));
        // ERC20(token1).transfer(vault, ERC20(token1).balanceOf(address(this)));

        IVault(vault).initialize(floorPosition, anchorPosition, discoveryPosition);
    }

    modifier initialized() {
        require(
            address(vault) != address(0) && 
            address(pool) != address(0), 
            "not initialized"
        );
        _;
    }
}