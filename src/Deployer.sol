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
    DeployLiquidityParameters,
    ProtocolAddresses
} from "./Types.sol";

interface IVault {
    function initialize(
        LiquidityPosition[3] memory positions
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

        if (token0Balance >= amount0Owed) {
            if (amount0Owed > 0) ERC20(token0).transfer(msg.sender, amount0Owed);
        } else {
            ERC20(token0).transferFrom(vault, address(this), amount0Owed);
            ERC20(token0).transfer(msg.sender, amount0Owed);
        }

        if (token1Balance >= amount1Owed) {
            if (amount1Owed > 0) ERC20(token1).transfer(msg.sender, amount1Owed);
        } else {
            ERC20(token1).transferFrom(vault, address(this), amount1Owed);
            ERC20(token1).transfer(msg.sender, amount1Owed);
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

    function deployPosition(
        address pool,
        address receiver,
        int24 lowerTick,
        int24 upperTick,
        LiquidityType liquidityType,
        AmountsToMint memory amounts
    ) public returns (LiquidityPosition memory newPosition) {
        return LiquidityDeployer
        ._deployPosition(
            address(pool),
            receiver,
            lowerTick,
            upperTick,
            liquidityType,
            amounts
        );
    }

    function shiftFloor(
        address _pool,
        address receiver,
        uint256 currentFloorPrice,
        uint256 newFloorPrice,
        uint256 newFloorBalance,
        uint256 currentFloorBalance,
        LiquidityPosition memory _floorPosition
    ) public  returns (LiquidityPosition memory newPosition) {

        return LiquidityDeployer.shiftFloor(
            _pool, 
            receiver, 
            currentFloorPrice, 
            newFloorPrice,
            newFloorBalance,
            currentFloorBalance,
            _floorPosition
        );
    }

    function computeNewFloorPrice(
        address _pool,
        uint256 toSkim,
        uint256 floorNewToken1Balance,
        uint256 circulatingSupply,
        uint256 anchorCapacity,
        LiquidityPosition[3] memory positions
    ) external view returns (uint256 newFloorPrice) {
        return LiquidityDeployer.computeNewFloorPrice(
            _pool,
            toSkim,
            floorNewToken1Balance,
            circulatingSupply,
            anchorCapacity,
            positions
            // newPositions
        );
    }

    function finalize() public initialized /*onlyOwner*/ {
        require(
            floorPosition.upperTick != 0 &&
            anchorPosition.upperTick != 0 &&
            discoveryPosition.upperTick != 0, 
            "not deployed"
        );

        LiquidityPosition[3] memory positions = [floorPosition, anchorPosition, discoveryPosition];
        
        uint256 balanceToken0 = ERC20(token0).balanceOf(address(this));
        ERC20(token0).transfer(vault, balanceToken0);
        IVault(vault).initialize(positions);
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