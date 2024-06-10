// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {OwnableUninitialized} from "../abstract/OwnableUninitialized.sol";

import {IWETH} from "../interfaces/IWETH.sol";
import {LiquidityOps} from "../libraries/LiquidityOps.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {VaultStorage} from "../libraries/LibAppStorage.sol";

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

contract BaseVault is OwnableUninitialized {
    VaultStorage internal _v;

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
        require(msg.sender == address(_v.pool), "cc");

        uint256 token0Balance = IERC20(_v.tokenInfo.token0).balanceOf(address(this));
        uint256 token1Balance = IERC20(_v.tokenInfo.token1).balanceOf(address(this));

        if (token0Balance >= amount0Owed) {
            if (amount0Owed > 0) IERC20(_v.tokenInfo.token0).transfer(msg.sender, amount0Owed);
        } 

        if (token1Balance >= amount1Owed) {
            if (amount1Owed > 0) IERC20(_v.tokenInfo.token1).transfer(msg.sender, amount1Owed); 
        } 
    }

    function initialize(
        address _deployer,
        address _pool, 
        address _modelHelper,
        address _stakingContract
    ) public {
        _v.pool = IUniswapV3Pool(_pool);
        _v.modelHelper = _modelHelper;
        _v.tokenInfo.token0 = _v.pool.token0();
        _v.tokenInfo.token1 = _v.pool.token1();
        _v.initialized = false;
        _v.lastLiquidityRatio = 0;
        _v.stakingContract = _stakingContract;
        OwnableUninitialized(_deployer);
    }

    function initializeLiquidity(
        LiquidityPosition[3] memory positions
    ) public {
        if (_v.initialized) revert AlreadyInitialized();
        if (msg.sender != _v.deployerContract) revert InvalidCaller();

        require(positions[0].liquidity > 0 && 
                positions[1].liquidity > 0 && 
                positions[2].liquidity > 0, "invalid position");
                
        _v.initialized = true;

        _updatePositions(
            positions
        );
    }

    function shift() public {
        require(_v.initialized, "not initialized");

        LiquidityPosition[3] memory positions = [_v.floorPosition, _v.anchorPosition, _v.discoveryPosition];

        LiquidityOps
        .shift(
            ProtocolAddresses({
                pool: address(_v.pool),
                vault: address(this),
                deployer: _v.deployerContract,
                modelHelper: _v.modelHelper
            }),
            positions
        );

    }    

    function slide() public  {
        require(_v.initialized, "not initialized");

        LiquidityPosition[3] memory positions = [_v.floorPosition, _v.anchorPosition, _v.discoveryPosition];
        LiquidityOps
        .slide(
            ProtocolAddresses({
                pool: address(_v.pool),
                vault: address(this),
                deployer: _v.deployerContract,
                modelHelper: _v.modelHelper
            }),
            positions
        );
    }

    function updatePositions(LiquidityPosition[3] memory _positions) public {
        require(msg.sender == address(this), "invalid caller");
        require(_v.initialized, "not initialized");
        
        require(
            _positions[0].liquidity > 0 &&
            _positions[1].liquidity > 0 && 
            _positions[2].liquidity > 0, 
            "updatePositions: no liquidity in positions"
        );           
        
        _v.floorPosition = _positions[0];
        _v.anchorPosition = _positions[1];
        _v.discoveryPosition = _positions[2];
    }
    
    function _updatePositions(LiquidityPosition[3] memory _positions) internal {
        require(_v.initialized, "not initialized");          
        
        _v.floorPosition = _positions[0];
        _v.anchorPosition = _positions[1];
        _v.discoveryPosition = _positions[2];
    }

        
    function getUnderlyingBalances(
        LiquidityType liquidityType
    ) external view 
    returns (int24, int24, uint256, uint256) {

        return IModelHelper(_v.modelHelper)
        .getUnderlyingBalances(
            address(_v.pool), 
            address(this), 
            liquidityType
        ); 
    }

    function setParameters(address _deployerContract) public /*onlyOwner*/ {
        if (_v.initialized) revert AlreadyInitialized();

        _v.deployerContract = _deployerContract;
    }

    function setFees(
        uint256 _feesAccumulatedToken0, 
        uint256 _feesAccumulatedToken1
    ) external {
        require(msg.sender == address(this), "invalid caller");

        _v.feesAccumulatorToken0 += _feesAccumulatedToken0;
        _v.feesAccumulatorToken1 += _feesAccumulatedToken1;
    }

    function getPositions() public view
    returns (LiquidityPosition[3] memory positions) {
        positions = [
            _v.floorPosition, 
            _v.anchorPosition, 
            _v.discoveryPosition
        ];
    }

    function getVaultInfo() public view 
    returns (
        VaultInfo memory vaultInfo
    ) {
        (
            vaultInfo
        ) =
        IModelHelper(_v.modelHelper).getVaultInfo(address(_v.pool), address(this), _v.tokenInfo);
    }

    function pool() public view returns (IUniswapV3Pool) {
        return _v.pool;
    }

    function getAccumulatedFees() public view returns (uint256, uint256) {
        return (_v.feesAccumulatorToken0, _v.feesAccumulatorToken1);
    }

    function setStakingContract(address _stakingContract) external onlyManager {
        _v.stakingContract = _stakingContract;
    }

    function getFunctionSelectors() external pure virtual returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](14);
        selectors[0] = bytes4(keccak256(bytes("getVaultInfo()")));
        selectors[1] = bytes4(keccak256(bytes("pool()")));
        selectors[2] = bytes4(keccak256(bytes("initialize(address,address,address,address)")));
        selectors[3] = bytes4(keccak256(bytes("setParameters(address)")));
        selectors[4] = bytes4(keccak256(bytes("initializeLiquidity((int24,int24,uint128,uint256)[3])")));
        selectors[5] = bytes4(keccak256(bytes("getPositions()")));
        selectors[6] = bytes4(keccak256(bytes("shift()")));
        selectors[7] = bytes4(keccak256(bytes("slide()")));
        selectors[8] = bytes4(keccak256(bytes("uniswapV3MintCallback(uint256,uint256,bytes)")));
        selectors[9] = bytes4(keccak256(bytes("getUnderlyingBalances(uint8)")));
        selectors[10] = bytes4(keccak256(bytes("updatePositions((int24,int24,uint128,uint256)[3])")));
        selectors[11] = bytes4(keccak256(bytes("setFees(uint256,uint256)")));
        selectors[12] = bytes4(keccak256(bytes("getAccumulatedFees()")));
        selectors[13] = bytes4(keccak256(bytes("setStakingContract(address)")));
        return selectors;
    }

}