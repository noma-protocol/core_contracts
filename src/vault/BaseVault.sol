// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {VaultStorage} from "../libraries/LibAppStorage.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IAddressResolver} from "../interfaces/IAddressResolver.sol";
import {
    LiquidityPosition, 
    LiquidityType,
    VaultInfo,
    ProtocolAddresses,
    ProtocolParameters
} from "../types/Types.sol";

import "../libraries/DecimalMath.sol"; 
import "../libraries/Utils.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface INomaFactory {
    function mintTokens(address to, uint256 amount) external;
    function burnFor(address from, uint256 amount) external;
    function teamMultiSig() external view returns (address);
}

interface IAdaptiveSupplyController {
    function adjustSupply(address pool, address vault, int256 volatility) external returns (uint256, uint256);
}

interface ILendingVault {
    function setFee(uint256 fee, uint256 feeToTreasury) external;
}

error AlreadyInitialized();
error InvalidPosition();
error OnlyFactory();
error OnlyDeployer();
error OnlyInternalCalls();
error CallbackCaller();
error ResolverNotSet();

contract BaseVault {
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
        address _stakingContract,
        address _proxyAddress,
        ProtocolParameters memory _params
    ) public onlyFactory {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        if (ds.resolver == address(0)) {
            revert ResolverNotSet();
        }
        
        _v.resolver = IAddressResolver(ds.resolver);
        _v.pool = IUniswapV3Pool(_pool);
        _v.factory = _factory;
        _v.tokenInfo.token0 = _v.pool.token0();
        _v.tokenInfo.token1 = _v.pool.token1();
        _v.initialized = false;
        _v.stakingEnabled = false;
        _v.loanFee = _params.loanFee;
        _v.stakingContract = _stakingContract;
        _v.proxyAddress = _proxyAddress;
        _v.deployerContract = _deployer;
        _v.protocolParameters = _params;
        _v.manager = _owner;
        
        IERC20(_v.pool.token0()).approve(_deployer, type(uint256).max);
    }
    
    // *** MUTATIVE FUNCTIONS *** //

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

    function setFees(
        uint256 _feesAccumulatedToken0, 
        uint256 _feesAccumulatedToken1
    ) public  onlyInternalCalls {
        _v.feesAccumulatorToken0 += _feesAccumulatedToken0;
        _v.feesAccumulatorToken1 += _feesAccumulatedToken1;
    }

    // *** VIEW FUNCTIONS *** //

    function getUnderlyingBalances(
        LiquidityType liquidityType
    ) external view 
    returns (int24, int24, uint256, uint256) {

        return IModelHelper(
            modelHelper()
        )
        .getUnderlyingBalances(
            address(_v.pool), 
            address(this), 
            liquidityType
        ); 
    }    

    function getVaultInfo() public view 
    returns (
        VaultInfo memory vaultInfo
    ) {
        (
            vaultInfo
        ) =
        IModelHelper(
            modelHelper()
        )
        .getVaultInfo(
            address(_v.pool), 
            address(this), 
            _v.tokenInfo
        );
    }

    function getExcessReserveToken1() external view returns (uint256) {
        bool isToken0 = false;
        return IModelHelper(
            modelHelper()
        )
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
            modelHelper: modelHelper(),
            adaptiveSupplyController: adaptiveSupply()
        });
    }

    // *** ADDRESS RESOLVER *** //

    function _getResolver() internal view returns (IAddressResolver resolver) {
        resolver = _v.resolver;
        if (address(resolver) == address(0)) {
            // Fallback to Diamond storage
            LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
            resolver = IAddressResolver(ds.resolver);
        }
    }

    function adaptiveSupply() public view returns (address) {
        IAddressResolver resolver = _getResolver();
        return resolver
            .requireAndGetAddress(
                Utils.stringToBytes32("AdaptiveSupply"), 
                "no AdaptiveSupply"
            );
    }

    function modelHelper() public view returns (address) {
        IAddressResolver resolver = _getResolver();
        return resolver
            .requireAndGetAddress(
                Utils.stringToBytes32("ModelHelper"), 
                "no ModelHelper"
            );
    }

    // *** MODIFIERS *** //

    modifier onlyDeployer() {
        if (msg.sender != _v.deployerContract) revert OnlyDeployer();
        _;
    }

    modifier onlyInternalCalls() {
        if (msg.sender != _v.factory && msg.sender != address(this)) revert OnlyInternalCalls();
        _;        
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

    // *** FUNCTION SELECTORS *** //

    function getFunctionSelectors() external pure virtual returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = bytes4(keccak256(bytes("getVaultInfo()")));
        selectors[1] = bytes4(keccak256(bytes("initialize(address,address,address,address,address,address,(uint8,uint8,uint8,uint16[2],uint256,uint256,int24,int24,int24,uint256,uint256,uint256,uint256))")));
        selectors[2] = bytes4(keccak256(bytes("initializeLiquidity((int24,int24,uint128,uint256,int24)[3])")));
        selectors[3] = bytes4(keccak256(bytes("uniswapV3MintCallback(uint256,uint256,bytes)")));
        selectors[4] = bytes4(keccak256(bytes("getUnderlyingBalances(uint8)")));
        selectors[5] = bytes4(keccak256(bytes("getAccumulatedFees()")));
        selectors[6] = bytes4(keccak256(bytes("getExcessReserveToken1()")));
        selectors[7] = bytes4(keccak256(bytes("getProtocolAddresses()")));
        selectors[8] = bytes4(keccak256(bytes("setFees(uint256,uint256)")));
        return selectors;
    }

}