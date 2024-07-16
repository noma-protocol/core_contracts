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

import "../libraries/DecimalMath.sol"; 

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function mint(address receiver, uint256 amount) external;
    function approve(address spender, uint256 amount) external;
}

interface IExtVault {
    function mintAndDistributeRewards(ProtocolAddresses memory) external;
}

interface ILendingVault {
    function borrowFromFloor(address who, uint256 borrowAmount, int256 duration) external;
    function paybackLoan(address who) external;
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
        address _stakingContract,
        address _proxyAddress,
        address _escrowContract
    ) public {
        _v.pool = IUniswapV3Pool(_pool);
        _v.modelHelper = _modelHelper;
        _v.tokenInfo.token0 = _v.pool.token0();
        _v.tokenInfo.token1 = _v.pool.token1();
        _v.initialized = false;
        _v.lastLiquidityRatio = 0;
        _v.stakingContract = _stakingContract;
        _v.proxyAddress = _proxyAddress;
        _v.escrowContract = _escrowContract;
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

    function updatePositions(LiquidityPosition[3] memory _positions) public {
        require(msg.sender == address(this), "invalid caller");
        require(_v.initialized, "not initialized");
        
        require(
            _positions[0].liquidity > 0 &&
            _positions[1].liquidity > 0 && 
            _positions[2].liquidity > 0, 
            "updatePositions: no liquidity in positions"
        );           
        
        _updatePositions(_positions);
    }
    
    function _updatePositions(LiquidityPosition[3] memory _positions) internal {
        
        _v.floorPosition = _positions[0];
        _v.anchorPosition = _positions[1];
        _v.discoveryPosition = _positions[2];
    }

    function borrow(
        address who,
        uint256 borrowAmount
    ) external {
        ILendingVault(address(this))
        .borrowFromFloor(
            who,
            borrowAmount,
            30 days
        );
    }

    function payback(
        address who
    ) external {
        ILendingVault(address(this))
        .paybackLoan(
            who
        );
    }

    function calcDynamicAmount(
        address pool, 
        address modelHelper,
        bool isBurn
    ) 
    external 
    view 
    returns (uint256) {
        require(msg.sender == address(this), "unathorized");

        uint256 currentLiquidityRatio = IModelHelper(modelHelper)
        .getLiquidityRatio(pool, address(this));

        uint256 circulatingSupply = IModelHelper(modelHelper)
        .getCirculatingSupply(
            pool,
            address(this)
        );

        uint256 result = DecimalMath
        .multiplyDecimal(
            circulatingSupply, 
            isBurn ? currentLiquidityRatio - 1e18 : 
            1e18 - currentLiquidityRatio
        ); 

        result = isBurn ? result / 100 : result;

        return result;  
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

    function setParameters(
        address _deployerContract, 
        address _stakingRewards
    ) public 
    /*onlyOwner*/ {
        if (_v.initialized) revert AlreadyInitialized();

        _v.deployerContract = _deployerContract;
        _v.stakingContract = _stakingRewards;
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

    function getCollateralAmount() public view returns (uint256) {
        return _v.collateralAmount;
    }

    function pool() public view returns (IUniswapV3Pool) {
        return _v.pool;
    }

    function getAccumulatedFees() public view returns (uint256, uint256) {
        return (_v.feesAccumulatorToken0, _v.feesAccumulatorToken1);
    }

    function getExcessReserveToken1() external view returns (uint256) {
        bool isToken0 = false;
        return IModelHelper(_v.modelHelper)
        .getExcessReserveBalance(
            address(_v.pool), 
            address(this), 
            isToken0
        );
    }

    function setStakingContract(address _stakingContract) external onlyManager {
        _v.stakingContract = _stakingContract;
    }

    function getFunctionSelectors() external pure virtual returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](17);
        selectors[0] = bytes4(keccak256(bytes("getVaultInfo()")));
        selectors[1] = bytes4(keccak256(bytes("pool()")));
        selectors[2] = bytes4(keccak256(bytes("initialize(address,address,address,address,address,address)")));
        selectors[3] = bytes4(keccak256(bytes("setParameters(address,address)")));
        selectors[4] = bytes4(keccak256(bytes("initializeLiquidity((int24,int24,uint128,uint256)[3])")));
        selectors[5] = bytes4(keccak256(bytes("getPositions()")));
        selectors[6] = bytes4(keccak256(bytes("uniswapV3MintCallback(uint256,uint256,bytes)")));
        selectors[7] = bytes4(keccak256(bytes("getUnderlyingBalances(uint8)")));
        selectors[8] = bytes4(keccak256(bytes("updatePositions((int24,int24,uint128,uint256)[3])")));
        selectors[9] = bytes4(keccak256(bytes("setFees(uint256,uint256)")));
        selectors[10] = bytes4(keccak256(bytes("getAccumulatedFees()")));
        selectors[11] = bytes4(keccak256(bytes("setStakingContract(address)")));
        selectors[12] = bytes4(keccak256(bytes("getExcessReserveToken1()")));
        selectors[13] = bytes4(keccak256(bytes("borrow(address,uint256)")));
        selectors[14] = bytes4(keccak256(bytes("calcDynamicAmount(address,address,bool)")));
        selectors[15] = bytes4(keccak256(bytes("getCollateralAmount()")));
        selectors[16] = bytes4(keccak256(bytes("payback(address)")));
        return selectors;
    }

}