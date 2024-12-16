
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { NomaFactoryStorage, ResolverStorage, VaultDescription } from "./libraries/LibAppStorage.sol";
import { IAddressResolver } from "./interfaces/IAddressResolver.sol";
import { MockNomaToken } from "./token/MockNomaToken.sol";

import { Diamond } from "./Diamond.sol";
import { DiamondInit } from "./init/DiamondInit.sol";
import { OwnershipFacet } from "./facets/OwnershipFacet.sol";
import { DiamondCutFacet } from "./facets/DiamondCutFacet.sol";
import { IDiamondCut } from "./interfaces/IDiamondCut.sol";
import { IFacet } from "./interfaces/IFacet.sol";
import { IDiamond } from "./interfaces/IDiamond.sol";
import { BaseVault } from "./vault/BaseVault.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";

import {Conversions} from "./libraries/Conversions.sol";

import {
    feeTier, 
    tickSpacing, 
    LiquidityPosition, 
    LiquidityType, 
    VaultDeployParams
} from "./types/Types.sol";

contract NomaFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    Diamond diamond;
    DiamondCutFacet dCutFacet;
    OwnershipFacet ownerF;
    DiamondInit dInit;

    NomaFactoryStorage internal _n;
    ResolverStorage internal _r;
    
    address private vaultUpgrade;
    address private vaultUpgradeFinalize;

    constructor(
        address _uniswapV3Factory,
        address _resolver 
    ) {
        _n.authority = msg.sender;
        _n.uniswapV3Factory = _uniswapV3Factory;
        _r.resolver = IAddressResolver(_resolver);
    }

    function deployVault(
        VaultDeployParams memory _params
    ) external {
        _validateToken1(_params.token1);

        uint256 _launchSupply = _params._totalSupply * _params._percentageForSale / 100;

        // Force desired token order on Uniswap V3
        uint256 nonce = 0;
        MockNomaToken nomaToken;

        // Encode the initialize function call
        bytes memory data = abi.encodeWithSelector(
            nomaToken.initialize.selector,
            address(this),          // Deployer address
            _params._totalSupply    // Initial supply
        );

        do {
            nomaToken = new MockNomaToken{salt: bytes32(nonce)}();            
            nonce++;
        } while (address(nomaToken) >= _params.token1);

        require(address(nomaToken) < _params.token1, "invalid token address");

        uint256 totalSupplyFromContract = nomaToken.totalSupply();

        require(totalSupplyFromContract == _params._totalSupply, "wrong parameters");

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(nomaToken),
            data
        );      

        require(address(proxy) != address(0), "Token deploy failed");

        nomaToken.initialize(address(this), _params._totalSupply);

        // Set authority for future upgrades
        MockNomaToken(address(proxy)).setOwner(msg.sender);

        IUniswapV3Factory factory = IUniswapV3Factory(_n.uniswapV3Factory);
        IUniswapV3Pool pool = _deployPool(address(proxy), _params.token1);

        address vaultAddress = _preDeployVault();
        BaseVault vault = BaseVault(vaultAddress);

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

        _n.deployers.add(msg.sender);
        _n.totalVaults += 1;
    }

    function _deployPool(address token0, address token1) internal returns (IUniswapV3Pool) {
        IUniswapV3Factory factory = IUniswapV3Factory(_n.uniswapV3Factory);
        IUniswapV3Pool pool = IUniswapV3Pool(
            factory.getPool(token0, token1, feeTier)
        );

        if (address(pool) == address(0)) {
            pool = IUniswapV3Pool(
                factory.createPool(token0, token1, feeTier)
            );
        }

        return pool;
    }

    function _preDeployVault()
        internal
        returns (address vault)
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

        //upgrade diamond
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");
        IDiamond(address(diamond)).transferOwnership(vaultUpgrade);

        //Initialization
        DiamondInit(address(diamond)).init();
        vault = address(diamond);
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
        _r.resolver.requireAndGetAddress(result, "not a reserve token");
    }

    modifier isAuthority() {
        require(msg.sender == _n.authority, "NFA");
        _;
    }
}