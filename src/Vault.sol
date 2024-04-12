// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {IWETH} from "./interfaces/IWETH.sol";
import {LiquidityOps} from "./libraries/LiquidityOps.sol";
import {Underlying} from "./libraries/Underlying.sol";
// import {ModelHelper} from "./libraries/ModelHelper.sol";
import {IModelHelper} from "./interfaces/IModelHelper.sol";

import {
    tickSpacing, 
    LiquidityPosition, 
    LiquidityType,
    VaultInfo,
    ProtocolAddresses
} from "./Types.sol";

error AlreadyInitialized();
error InvalidCaller();

contract Vault is Owned {

    LiquidityPosition private floorPosition;
    LiquidityPosition private anchorPosition;
    LiquidityPosition private discoveryPosition;

    VaultInfo private vaultInfo;
    address private deployerContract;
    address private modelHelper;
    IUniswapV3Pool public pool;

    bool private initialized; 
    uint256 private lastLiquidityRatio;

    event FloorUpdated(uint256 floorPrice, uint256 floorCapacity);

    constructor(address _pool, address _modelHelper) Owned(msg.sender) {
        pool = IUniswapV3Pool(_pool);
        modelHelper = _modelHelper;
        VaultInfo storage _vaultInfo = vaultInfo;
        _vaultInfo.token0 = pool.token0();
        _vaultInfo.token1 = pool.token1();
        initialized = false;
        lastLiquidityRatio = 0;
    }

    function initialize(
        LiquidityPosition memory _floorPosition,
        LiquidityPosition memory _anchorPosition,
        LiquidityPosition memory _discoveryPosition
    ) public {
        if (initialized) revert AlreadyInitialized();
        if (msg.sender != deployerContract) revert InvalidCaller();

        floorPosition = _floorPosition;
        anchorPosition = _anchorPosition;
        discoveryPosition = _discoveryPosition;

        LiquidityPosition[3] memory positions;

        positions[0] = _floorPosition;
        positions[1] = _anchorPosition;
        positions[2] = _discoveryPosition;

        require(positions[0].liquidity > 0 && 
                positions[1].liquidity > 0 && 
                positions[2].liquidity > 0, "invalid position");

        IModelHelper(modelHelper)
        .updatePositions(
            positions
        );

        initialized = true;
    }

    function setDeployer(address _deployerContract) public /*onlyOwner*/ {
        if (initialized) revert AlreadyInitialized();

        deployerContract = _deployerContract;
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

        uint256 token0Balance = ERC20(vaultInfo.token0).balanceOf(address(this));
        uint256 token1Balance = ERC20(vaultInfo.token1).balanceOf(address(this));

        if (token0Balance >= amount0Owed) {
            if (amount0Owed > 0) ERC20(vaultInfo.token0).transfer(msg.sender, amount0Owed);
        } 

        if (token1Balance >= amount1Owed) {
            if (amount1Owed > 0) ERC20(vaultInfo.token1).transfer(msg.sender, amount1Owed); 
        } 
    }

    function shift() public {
        require(initialized, "not initialized");
        
        LiquidityPosition[3] memory positions;

        positions[0] = floorPosition;
        positions[1] = anchorPosition;
        positions[2] = discoveryPosition;

        (
            uint256 currentLiquidityRatio,
            LiquidityPosition[3] memory newPositions
            // uint256 newFloorPrice
        ) = LiquidityOps
        .shift(
            ProtocolAddresses({
                pool: address(pool),
                vault: address(this),
                deployer: deployerContract,
                modelHelper: modelHelper
            }),
            positions
        );

        lastLiquidityRatio = currentLiquidityRatio;
        
        // floorPosition = newPositions[0];
        // anchorPosition = newPositions[1];
        // discoveryPosition = newPositions[2];

        // Emit event
        emit FloorUpdated(
            0, 
            IModelHelper(modelHelper)
            .getPositionCapacity(
                address(pool), 
                address(this),
                floorPosition
            )
        );
    }    

    function updatePositions(LiquidityPosition[3] memory _positions) public {
        require(initialized, "not initialized");
        require(msg.sender == address(this), "invalid caller");
        
        floorPosition = _positions[0];
        anchorPosition = _positions[1];
        discoveryPosition = _positions[2];
    }

        
    function getUnderlyingBalances(
        LiquidityType liquidityType
    ) external view 
    returns (int24, int24, uint256, uint256) {

        return IModelHelper(modelHelper)
        .getUnderlyingBalances(
            address(pool), 
            address(this), 
            liquidityType
        ); 
    }


    function getVaultInfo() public view 
    returns (
        uint256 liquidityRatio, 
        uint256 circulatingSupply, 
        uint256 spotPriceX96, 
        uint256 anchorCapacity, 
        uint256 floorCapacity, 
        address token0, 
        address token1,
        uint256 newFloor
    ) {
        LiquidityPosition[] memory positions = new LiquidityPosition[](3);

        positions[0] = floorPosition;
        positions[1] = anchorPosition;
        positions[2] = discoveryPosition;

        (
            liquidityRatio, 
            circulatingSupply, 
            spotPriceX96, 
            anchorCapacity, 
            floorCapacity, 
            token0, 
            token1
        ) =
        IModelHelper(modelHelper).getVaultInfo(address(pool), address(this), vaultInfo);

        newFloor = 0; //IModelHelper(modelHelper).estimateNewFloorPrice(address(pool), positions);

        return (
            liquidityRatio, 
            circulatingSupply, 
            spotPriceX96, 
            anchorCapacity, 
            floorCapacity, 
            token0, 
            token1, 
            newFloor
        );
    }

}