// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import {Owned} from "solmate/auth/Owned.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {LiquidityOps} from "./libraries/LiquidityOps.sol";
import {IModelHelper} from "./interfaces/IModelHelper.sol";

import {
    tickSpacing, 
    LiquidityPosition, 
    LiquidityType,
    VaultInfo,
    ProtocolAddresses
} from "./Types.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IVaultsController {
    function shift(ProtocolAddresses _parameters, address vault) external;
    function slide(ProtocolAddresses _parameters, address vault) external;
}

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

        uint256 token0Balance = IERC20(vaultInfo.token0).balanceOf(address(this));
        uint256 token1Balance = IERC20(vaultInfo.token1).balanceOf(address(this));

        if (token0Balance >= amount0Owed) {
            if (amount0Owed > 0) IERC20(vaultInfo.token0).transfer(msg.sender, amount0Owed);
        } 

        if (token1Balance >= amount1Owed) {
            if (amount1Owed > 0) IERC20(vaultInfo.token1).transfer(msg.sender, amount1Owed); 
        } 
    }

    function shift() public {
        require(initialized, "not initialized");



    }    

    function slide() public  {
        require(initialized, "not initialized");

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

    function _getPositions() internal view
    returns (LiquidityPosition[3] memory) {
        LiquidityPosition[3] memory positions;

        positions[0] = floorPosition;
        positions[1] = anchorPosition;
        positions[2] = discoveryPosition;

        return positions;
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