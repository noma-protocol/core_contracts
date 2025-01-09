// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {Utils} from "./libraries/Utils.sol";
import {IWETH} from "./interfaces/IWETH.sol";

// import {LiquidityOps} from "./libraries/LiquidityOps.sol";
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
} from "./types/Types.sol";

import { IAddressResolver } from "./interfaces/IAddressResolver.sol";

interface IVault {
    function initializeLiquidity(
        LiquidityPosition[3] memory positions
    ) external;
}

contract Deployer is Owned {

    LiquidityPosition private floorPosition;
    LiquidityPosition private anchorPosition;
    LiquidityPosition private discoveryPosition;

    address private vault;
    address private token0;
    address private token1;
    address private modelHelper;
    address private factory;
    address private resolver;

    bool private locked; // Lock mechanism
    bool private initialized; // Reinitialization state

    IUniswapV3Pool public pool;

    event FloorDeployed(LiquidityPosition position);
    event AnchorDeployed(LiquidityPosition position);
    event DiscoveryDeployed(LiquidityPosition position);

    constructor(address _owner, address _resolver) Owned(_owner) {
        resolver = _resolver;
    }

    /**
     * @notice Reinitializable function to set up state for a new deployment
     */
    function initialize(
        address _factory,
        address _vault,
        address _pool,
        address _modelHelper
    ) public onlyOwner lock {
        factory = _factory;
        pool = IUniswapV3Pool(_pool);
        vault = _vault;
        token0 = pool.token0();
        token1 = pool.token1();
        modelHelper = _modelHelper;
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

    function deployFloor(uint256 _floorPrice, uint256 _amount0) public 
    onlyFactory {
        
        (LiquidityPosition memory newPosition, ) = 
        DeployHelper
        .deployFloor(
            pool, 
            vault, 
            _floorPrice,
            _amount0,
            tickSpacing
        );

        floorPosition = newPosition;
        emit FloorDeployed(newPosition);
    }

    function deployAnchor(uint256 _bipsBelowSpot, uint256 _bipsWidth, uint256 amount0) public 
    onlyFactory {

        (LiquidityPosition memory newPosition,) = LiquidityDeployer
        .deployAnchor(
            address(pool),
            vault,
            amount0,
            floorPosition,
            DeployLiquidityParameters({
                bips: _bipsWidth,
                bipsBelowSpot: _bipsBelowSpot,
                tickSpacing: tickSpacing,
                lowerTick: 0,
                upperTick: 0
            })
        );

        anchorPosition = newPosition;
        emit AnchorDeployed(newPosition);
    }

    function deployDiscovery(uint256 _upperDiscoveryPrice) public 
    onlyFactory 
    returns (
        LiquidityPosition memory newPosition, 
        LiquidityType liquidityType
    ) {

        (newPosition,) = LiquidityDeployer
        .deployDiscovery(
            address(pool), 
            vault,
            anchorPosition, 
            _upperDiscoveryPrice, 
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
    ) public isVault
    returns (
        LiquidityPosition memory newPosition
    ) {
        return LiquidityDeployer
        ._deployPosition(
            pool,
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
    ) public isVault returns (LiquidityPosition memory newPosition) {

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

    /**
     * @notice Finalize function to clear the state after deployment
     */
    function finalize() public onlyFactory lock {
        require(
            floorPosition.upperTick != 0 &&
            anchorPosition.upperTick != 0 &&
            discoveryPosition.upperTick != 0,
            "not deployed"
        );

        LiquidityPosition[3] memory positions = [floorPosition, anchorPosition, discoveryPosition];

        uint256 balanceToken0 = ERC20(token0).balanceOf(address(this));
        ERC20(token0).transfer(vault, balanceToken0);
        IVault(vault).initializeLiquidity(positions);
    }

    /**
     * @dev Lock modifier to prevent reentrancy
     */
    modifier lock() {
        require(!locked, "Deployer: Locked");
        locked = true;
        _;
        locked = false;
    }

    modifier isVault() {
        IAddressResolver(resolver)
        .requireDeployerACL(msg.sender);
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "only factory");
        _;
    }
}