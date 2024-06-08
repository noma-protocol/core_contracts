// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import {Owned} from "solmate/auth/Owned.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {LiquidityOps} from "../libraries/LiquidityOps.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";

import {
    tickSpacing, 
    LiquidityPosition, 
    LiquidityType,
    TokenInfo,
    ProtocolAddresses,
    VaultInfo
} from "../Types.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IVaultsController {
    function shift(ProtocolAddresses memory _parameters, address vault) external;
    function slide(ProtocolAddresses memory _parameters, address vault) external;
}

error AlreadyInitialized();
error InvalidCaller();

contract Vault is Owned {

    LiquidityPosition private floorPosition;
    LiquidityPosition private anchorPosition;
    LiquidityPosition private discoveryPosition;

    TokenInfo private tokenInfo;
    
    address private deployerContract;
    address private modelHelper;

    IUniswapV3Pool public pool;

    bool private initialized; 
    uint256 private lastLiquidityRatio;
    
    // uint256 public feesAccumulatorToken0;
    // uint256 public feesAccumulatorToken1;

    event FloorUpdated(uint256 floorPrice, uint256 floorCapacity);

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

        uint256 token0Balance = IERC20(tokenInfo.token0).balanceOf(address(this));
        uint256 token1Balance = IERC20(tokenInfo.token1).balanceOf(address(this));

        if (token0Balance >= amount0Owed) {
            if (amount0Owed > 0) IERC20(tokenInfo.token0).transfer(msg.sender, amount0Owed);
        } 

        if (token1Balance >= amount1Owed) {
            if (amount1Owed > 0) IERC20(tokenInfo.token1).transfer(msg.sender, amount1Owed); 
        } 
    }

    constructor(address owner, address _pool, address _modelHelper) Owned(owner) {
        pool = IUniswapV3Pool(_pool);
        modelHelper = _modelHelper;
        tokenInfo.token0 = pool.token0();
        tokenInfo.token1 = pool.token1();
        initialized = false;
        lastLiquidityRatio = 0;
    }

    function initialize(
        LiquidityPosition[3] memory positions
    ) public {
        if (initialized) revert AlreadyInitialized();
        if (msg.sender != deployerContract) revert InvalidCaller();

        require(positions[0].liquidity > 0 && 
                positions[1].liquidity > 0 && 
                positions[2].liquidity > 0, "invalid position");
                
        initialized = true;

        updatePositions(
            positions
        );

    }

    function shift() public {
        require(initialized, "not initialized");

        LiquidityPosition[3] memory positions = [floorPosition, anchorPosition, discoveryPosition];

        LiquidityOps
        .shift(
            ProtocolAddresses({
                pool: address(pool),
                vault: address(this),
                deployer: deployerContract,
                modelHelper: modelHelper
            }),
            positions
        );

    }    

    function slide() public  {
        require(initialized, "not initialized");

        LiquidityPosition[3] memory positions = [floorPosition, anchorPosition, discoveryPosition];
        LiquidityOps
        .slide(
            ProtocolAddresses({
                pool: address(pool),
                vault: address(this),
                deployer: deployerContract,
                modelHelper: modelHelper
            }),
            positions
        );
    }

    function updatePositions(LiquidityPosition[3] memory _positions) public {
        require(initialized, "not initialized");
        // TODO: check who is msg.sender w this call
        // require(msg.sender == address(this), "invalid caller");
        // require(
        //     _positions[0].liquidity > 0 &&
        //     _positions[1].liquidity > 0 && 
        //     _positions[2].liquidity > 0, 
        //     "slide: no liquidity in positions"
        // );           
        
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

    function setParameters(address _deployerContract) public /*onlyOwner*/ {
        if (initialized) revert AlreadyInitialized();

        deployerContract = _deployerContract;
    }

    // function setFees(
    //     uint256 _feesAccumulatedToken0, 
    //     uint256 _feesAccumulatedToken1
    // ) internal {

    //     feesAccumulatorToken0 += _feesAccumulatedToken0;
    //     feesAccumulatorToken1 += _feesAccumulatedToken1;
    // }

    function getPositions() public view
    returns (LiquidityPosition[3] memory positions) {
        positions = [floorPosition, anchorPosition, discoveryPosition];
    }

    function getVaultInfo() public view 
    returns (
        VaultInfo memory vaultInfo
    ) {
        (
            vaultInfo
        ) =
        IModelHelper(modelHelper).getVaultInfo(address(pool), address(this), tokenInfo);
    }

    function getFunctionSelectors() external pure virtual returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256(bytes("getVaultInfo()")));
        return selectors;
    }
}