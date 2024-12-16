
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import { TickMath } from '@uniswap/v3-core/libraries/TickMath.sol';

import { NomaFactoryStorage, VaultDescription } from "./libraries/LibAppStorage.sol";
import { Conversions } from "./libraries/Conversions.sol";
import { Utils } from "../src/libraries/Utils.sol";
import { IAddressResolver } from "./interfaces/IAddressResolver.sol";
import { IDiamondCut } from "./interfaces/IDiamondCut.sol";
import { IFacet } from "./interfaces/IFacet.sol";
import { IDiamond } from "./interfaces/IDiamond.sol";
import { BaseVault } from "./vault/BaseVault.sol";

import { MockNomaToken } from "./token/MockNomaToken.sol";
import { Diamond } from "./Diamond.sol";
import { DiamondInit } from "./init/DiamondInit.sol";
import { OwnershipFacet } from "./facets/OwnershipFacet.sol";
import { DiamondCutFacet } from "./facets/DiamondCutFacet.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

import {
    feeTier, 
    tickSpacing, 
    LiquidityPosition, 
    LiquidityType, 
    VaultDeployParams
} from "./types/Types.sol";

interface IVaultUpgrade {
    function doUpgradeStart(address diamond, address _vaultUpgradeFinalize) external;
    function doUpgradeFinalize(address diamond) external;
}

contract NomaFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    Diamond diamond;
    DiamondCutFacet dCutFacet;
    OwnershipFacet ownerF;
    DiamondInit dInit;

    NomaFactoryStorage internal _n;
    
    constructor(
        address _uniswapV3Factory,
        address _resolver 
    ) {
        _n.authority = msg.sender;
        _n.uniswapV3Factory = _uniswapV3Factory;
        _n.resolver = IAddressResolver(_resolver);
    }

    function deployVault(
        VaultDeployParams memory _params
    ) external returns (address) {
        _validateToken1(_params.token1);

        address modelHelper = _n.resolver
        .requireAndGetAddress(
            Utils.stringToBytes32("ModelHelper"), 
            "no modelHelper"
        );

        address vaultUpgradeFinalize = _n.resolver
        .requireAndGetAddress(
            Utils.stringToBytes32("VaultUpgradeFinalize"), 
            "no vaultUpgradeFinalize"
        );

        uint256 _launchSupply = _params._totalSupply * _params._percentageForSale / 100;

        (MockNomaToken nomaToken, ERC1967Proxy proxy) = _deployNomaToken(
            _params.token1, 
            _params._totalSupply
        );

        // Set authority for future upgrades
        MockNomaToken(address(proxy)).setOwner(msg.sender);

        IUniswapV3Factory factory = IUniswapV3Factory(_n.uniswapV3Factory);
        
        IUniswapV3Pool pool = _deployPool(
            address(proxy), 
            _params.token1
        );

        (address vaultAddress, address vaultUpgrade) = _preDeployVault();
        BaseVault vault = BaseVault(vaultAddress);

        IVaultUpgrade(vaultUpgrade)
        .doUpgradeStart(
            vaultAddress, 
            vaultUpgradeFinalize
        );

        _initializeVault(
            vaultAddress, 
            address(pool), 
            _params.token1, 
            modelHelper, 
            vaultUpgrade, 
            vaultUpgradeFinalize
        );

       _n.vaultsRepository[address(proxy)] = 
        VaultDescription({
            tokenName: _params._name,
            tokenSymbol: _params._symbol,
            tokenDecimals: _params._decimals,
            token0: address(proxy),
            token1: _params.token1,
            deployer: msg.sender,
            vault: address(0)
        });

        _bootstrapLiquidity(
            _params._IDOPrice, 
            _launchSupply,
            _params._totalSupply, 
            address(proxy), 
            address(pool), 
            address(0)
        );

        _n.deployers.add(msg.sender);
        _n.totalVaults += 1;

        return vaultAddress;
    }
    
    function _deployNomaToken(
        address _token1,
        uint256 _totalSupply
    ) internal returns (MockNomaToken, ERC1967Proxy) {
        
        // Force desired token order on Uniswap V3
        uint256 nonce = 0;

        MockNomaToken nomaToken;

        // Encode the initialize function call
        bytes memory data = abi.encodeWithSelector(
            nomaToken.initialize.selector,
            address(this),  // Deployer address
            _totalSupply    // Initial supply
        );

        do {
            nomaToken = new MockNomaToken{salt: bytes32(nonce)}();            
            nonce++;
        } while (address(nomaToken) >= _token1);

        nomaToken.initialize(address(this), _totalSupply);

        require(address(nomaToken) < _token1, "invalid token address");

        uint256 totalSupplyFromContract = nomaToken.totalSupply();

        require(totalSupplyFromContract == _totalSupply, "wrong parameters");

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(nomaToken),
            data
        );      

        require(address(proxy) != address(0), "Token deploy failed");

        return (nomaToken, proxy);
    }

    function _initializeVault(
        address _vault,
        address _token0,
        address _token1,
        address _modelHelper,
        address _vaultUpgrade,
        address _vaultUpgradeFinalize
    ) internal {
        BaseVault vault = BaseVault(_vault);
        vault.initialize(
            msg.sender, 
            _token0, 
            _modelHelper, 
            _vaultUpgrade, 
            _token1, 
            _vaultUpgradeFinalize
        );
    }

    function _deployPool(address token0, address token1) internal returns (IUniswapV3Pool) {
        IUniswapV3Factory factory = IUniswapV3Factory(_n.uniswapV3Factory);
        IUniswapV3Pool pool = IUniswapV3Pool(
            factory.getPool(token0, token1, feeTier)
        );

        if (address(pool) == address(0)) {
            pool = IUniswapV3Pool(
                factory.createPool(
                    token0, 
                    token1, 
                    feeTier
                )
            );
        }

        return pool;
    }

    function _preDeployVault()
        internal
        returns (address vault, address vaultUpgrade)
    {
        //deploy facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(dCutFacet));
        ownerF = new OwnershipFacet();
        dInit = new DiamondInit();

        //build cut struct
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](3);

        cut[0] = (
            IDiamondCut.FacetCut({
                facetAddress: address(ownerF),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: IFacet(address(ownerF)).getFunctionSelectors()
            })
        );

        cut[1] = (
            IDiamondCut.FacetCut({
                facetAddress: address(dInit),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: IFacet(address(dInit)).getFunctionSelectors()
            })
        );

        cut[2] = (
            IDiamondCut.FacetCut({
                facetAddress: address(dCutFacet),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: IFacet(address(dCutFacet)).getFunctionSelectors()
            })
        );

        vaultUpgrade = _n.resolver
        .requireAndGetAddress(
            Utils.stringToBytes32("VaultUpgrade"), 
            "no VaultUpgrade"
        );

        //upgrade diamond
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");
        IDiamond(address(diamond)).transferOwnership(vaultUpgrade);
            
        //Initialization
        DiamondInit(address(diamond)).init();
        vault = address(diamond);

        return (vault, vaultUpgrade);
    }

    function _bootstrapLiquidity(
        uint256 _idoPrice,
        uint256 _launchSupply,
        uint256 _totalSupply,
        address _token0,
        address _pool, 
        address _deployerContract
    ) internal {
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(_pool).slot0();

        (int24 lowerTick, int24 upperTick) = Conversions
        .computeSingleTick(_idoPrice, tickSpacing);

        uint256 amount0Max = _launchSupply;
        uint256 amount1Max = 0;

        uint128 liquidity = LiquidityAmounts
        .getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount0Max,
            amount1Max
        );

        ERC20(_token0).transfer(_deployerContract, _totalSupply);
    }

    function _validateToken1(address token) internal view {
        bytes32 result;
        string memory symbol = IERC20Metadata(token).symbol();
        bytes memory symbol32 = bytes(symbol);

        if (symbol32.length == 0) {
            revert("IT");
        }

        assembly {
            result := mload(add(symbol, 32))
        }
        _n.resolver.requireAndGetAddress(result, "not a reserve token");
    }

    modifier isAuthority() {
        require(msg.sender == _n.authority, "NFA");
        _;
    }
}