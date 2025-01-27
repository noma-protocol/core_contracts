// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {OwnableUninitialized} from "../abstract/OwnableUninitialized.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {VaultStorage} from "../libraries/LibAppStorage.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IAddressResolver} from "../interfaces/IAddressResolver.sol";
import {
    LiquidityPosition, 
    LiquidityType,
    VaultInfo,
    ProtocolAddresses,
    LiquidityStructureParameters
} from "../types/Types.sol";

import "../libraries/DecimalMath.sol"; 
import "../libraries/Utils.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function mint(address receiver, uint256 amount) external;
    function approve(address spender, uint256 amount) external;
}

interface INomaFactory {
    function mintTokens(address to, uint256 amount) external;
    function burnFor(address from, uint256 amount) external;
    function teamMultiSig() external view returns (address);
}

interface IAdaptiveSupplyController {
    function adjustSupply(address pool, address vault, int256 volatility) external returns (uint256, uint256);
}

error AlreadyInitialized();
error InvalidPosition();
error OnlyFactory();
error OnlyDeployer();
error OnlyInternalCalls();
error CallbackCaller();
error ResolverNotSet();

contract BaseVault is OwnableUninitialized {
    VaultStorage internal _v;

    event FloorUpdated(uint256 floorPrice, uint256 floorCapacity);
    error MyError();

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
        if (msg.sender != address(_v.pool)) revert CallbackCaller();

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
        address _factory,
        address _owner,
        address _deployer,
        address _pool, 
        address _modelHelper,
        address _stakingContract,
        address _proxyAddress,
        address _adaptiveSupplyController,
        LiquidityStructureParameters memory _params
    ) public onlyFactory {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        if (ds.resolver == address(0)) {
            revert ResolverNotSet();
        }
        
        _v.resolver = IAddressResolver(ds.resolver);
        _v.pool = IUniswapV3Pool(_pool);
        _v.factory = _factory;
        _v.modelHelper = _modelHelper;
        _v.tokenInfo.token0 = _v.pool.token0();
        _v.tokenInfo.token1 = _v.pool.token1();
        _v.initialized = false;
        _v.stakingEnabled = false;
        _v.stakingContract = _stakingContract;
        _v.proxyAddress = _proxyAddress;
        _v.adaptiveSupplyController = _adaptiveSupplyController;
        _v.deployerContract = _deployer;
        _v.liquidityStructureParameters = _params;
        
        OwnableUninitialized(_owner);
    }
    
    function initializeLiquidity(
        LiquidityPosition[3] memory positions
    ) public onlyDeployer {
        if (_v.initialized) revert AlreadyInitialized();

        if (
            positions[0].liquidity == 0 || 
            positions[1].liquidity == 0 || 
            positions[2].liquidity == 0
        ) revert InvalidPosition();
                
        _v.initialized = true;

        _v.floorPosition = positions[0];
        _v.anchorPosition = positions[1];
        _v.discoveryPosition = positions[2];
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

    function mintTokens(
        address to,
        uint256 amount
    ) public onlyInternalCalls {
        
        INomaFactory(_v.factory)
        .mintTokens(
            to,
            amount
        );

        _v.timeLastMinted = block.timestamp;
    }

    function burnTokens(
        uint256 amount
    ) public onlyInternalCalls {

        IERC20(_v.pool.token0()).approve(address(_v.factory), amount);
        INomaFactory(_v.factory)
        .burnFor(
            address(this),
            amount
        );
    }
    

    function getVaultInfo() public view 
    returns (
        VaultInfo memory vaultInfo
    ) {
        (
            vaultInfo
        ) =
        IModelHelper(_v.modelHelper)
        .getVaultInfo(
            address(_v.pool), 
            address(this), 
            _v.tokenInfo
        );
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

    function getProtocolAddresses() public view returns (ProtocolAddresses memory) {
        return ProtocolAddresses({
            pool: address(_v.pool),
            vault: address(this),
            deployer: _v.deployerContract,
            modelHelper: _v.modelHelper,
            adaptiveSupplyController: _v.adaptiveSupplyController
        });
    }

    modifier onlyFactory() {
        IAddressResolver resolver = _getResolver();
        address factory = resolver
                .requireAndGetAddress(
                    Utils.stringToBytes32("NomaFactory"), 
                    "no factory"
                );
        if (msg.sender != factory) revert OnlyFactory();
        _;
    }

    function _getResolver() internal view returns (IAddressResolver resolver) {
        resolver = _v.resolver;
        if (address(resolver) == address(0)) {
            // Fallback to Diamond storage
            LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
            resolver = IAddressResolver(ds.resolver);
        }
    }

    function getTimeSinceLastMint() public view returns (uint256) {
        return block.timestamp - _v.timeLastMinted;
    }


    modifier onlyDeployer() {
        if (msg.sender != _v.deployerContract) revert OnlyDeployer();
        _;
    }

    modifier onlyInternalCalls() {
        if (msg.sender != _v.factory && msg.sender != address(this)) revert OnlyInternalCalls();
        _;        
    }

    function getFunctionSelectors() external pure virtual returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = bytes4(keccak256(bytes("getVaultInfo()")));
        selectors[1] = bytes4(keccak256(bytes("pool()")));
        selectors[2] = bytes4(keccak256(bytes("initialize(address,address,address,address,address,address,address,address,(uint8,uint8,uint8,uint16[2],uint256,uint256,int24,int24,int24,uint256,uint256,uint256))")));
        selectors[3] = bytes4(keccak256(bytes("initializeLiquidity((int24,int24,uint128,uint256)[3])")));
        selectors[4] = bytes4(keccak256(bytes("uniswapV3MintCallback(uint256,uint256,bytes)")));
        selectors[5] = bytes4(keccak256(bytes("getUnderlyingBalances(uint8)")));
        selectors[6] = bytes4(keccak256(bytes("getAccumulatedFees()")));
        selectors[7] = bytes4(keccak256(bytes("getExcessReserveToken1()")));
        selectors[8] = bytes4(keccak256(bytes("getCollateralAmount()")));
        selectors[9] = bytes4(keccak256(bytes("getProtocolAddresses()")));
        selectors[10] = bytes4(keccak256(bytes("mintTokens(address,uint256)")));
        selectors[11] = bytes4(keccak256(bytes("getTimeSinceLastMint()")));
        selectors[12] = bytes4(keccak256(bytes("burnTokens(uint256)")));
        return selectors;
    }

}