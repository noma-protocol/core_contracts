
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import { NomaFactoryStorage, VaultDescription } from "./libraries/LibAppStorage.sol";
import { Conversions } from "./libraries/Conversions.sol";
import { Utils } from "../src/libraries/Utils.sol";
import { IAddressResolver } from "./interfaces/IAddressResolver.sol";

import { BaseVault } from "./vault/BaseVault.sol";
import { MockNomaToken } from "./token/MockNomaToken.sol";

import {
    feeTier, 
    tickSpacing, 
    VaultDeployParams,
    VaultInitParams
} from "./types/Types.sol";

interface IVaultUpgrade {
    function doUpgradeStart(address diamond, address _vaultUpgradeFinalize) external;
    function doUpgradeFinalize(address diamond) external;
}

interface IEtchVault {
    function preDeployVault() external returns (address, address);
}

contract NomaFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

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
    ) external returns (address, address, address) {
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

        (MockNomaToken nomaToken, ERC1967Proxy proxy) = _deployNomaToken(
            _params.token1, 
            _params._totalSupply
        );

        // Set authority for future upgrades
        MockNomaToken(address(proxy)).setOwner(msg.sender);

        IUniswapV3Factory factory = IUniswapV3Factory(_n.uniswapV3Factory);
        
        IUniswapV3Pool pool = _deployPool(
            _params._IDOPrice,
            address(proxy), 
            _params.token1
        );

        (address vaultAddress, address vaultUpgrade) = IEtchVault(
            _n.resolver.requireAndGetAddress(
                Utils.stringToBytes32("EtchVault"), 
                "no EtchVault"
            )
        ).preDeployVault();

        {
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
                    vault: vaultAddress
                });

            IERC20Metadata(address(proxy)).transfer(
                _n.resolver
                .requireAndGetAddress(
                    Utils.stringToBytes32("Deployer"), 
                    "no deployer"
                ),
                _params._totalSupply
            );

            _n.deployers.add(msg.sender);
            _n.totalVaults += 1;
        }

        return (vaultAddress, address(pool), address(proxy));
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

    function _deployPool(uint256 _initPrice, address token0, address token1) internal returns (IUniswapV3Pool) {
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
            pool.initialize(
                Conversions
                .priceToSqrtPriceX96(
                    int256(_initPrice), 
                    tickSpacing
                )
            );            
        }

        return pool;
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
            _token1,
            _modelHelper,
            _vaultUpgrade,
            _vaultUpgradeFinalize
        );
    }

    function getVaultDescription(address deployer) external view returns (VaultDescription memory) {
        return _n.vaultsRepository[deployer];
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