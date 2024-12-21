
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import { NomaFactoryStorage, VaultDescription } from "../libraries/LibAppStorage.sol";

import { IAddressResolver } from "../interfaces/IAddressResolver.sol";
import { Conversions } from "../libraries/Conversions.sol";
import { Utils } from "../libraries/Utils.sol";

import { BaseVault } from "../vault/BaseVault.sol";
import { MockNomaToken } from "../token/MockNomaToken.sol";

import { Deployer } from "../Deployer.sol";

import {
    feeTier, 
    tickSpacing, 
    VaultDeployParams,
    VaultInitParams
} from "../types/Types.sol";

interface IVaultUpgrade {
    function doUpgradeStart(address diamond, address _vaultUpgradeFinalize) external;
    function doUpgradeFinalize(address diamond) external;
}

interface IEtchVault {
    function preDeployVault() external returns (address, address);
}

interface IExtFactory {
    function deployAll(
        address deployerAddress,
        address vaultAddress,
        address token0
    ) external returns (address, address);
}

interface IDeployerFactory {
    function deployDeployer(address owner, address resolver) external returns (address);
}

contract NomaFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    NomaFactoryStorage internal _n;
    
    constructor(
        address _uniswapV3Factory,
        address _resolver,
        address _deploymentFactory,
        address _extFactory
    ) {
        _n.authority = msg.sender;
        _n.uniswapV3Factory = _uniswapV3Factory;
        _n.resolver = IAddressResolver(_resolver);
        _n.deploymentFactory = _deploymentFactory;
        _n.extFactory = _extFactory;
    }

    function deployVault(
        VaultDeployParams memory _params
    ) external returns (address, address, address) {
        _validateToken1(_params.token1);

        (MockNomaToken nomaToken) = 
        _deployNomaToken(
            _params._name,
            _params._symbol,
            _params.token1, 
            _params._totalSupply
        );

        // Set authority for future upgrades
        // MockNomaToken(address(proxy)).setOwner(msg.sender);
        
        IUniswapV3Pool pool = _deployPool(
            _params._IDOPrice,
            address(nomaToken), 
            _params.token1
        );

        (address vaultAddress, address vaultUpgrade) = 
        IEtchVault(
            _n.resolver.requireAndGetAddress(
                Utils.stringToBytes32("EtchVault"), 
                "no EtchVault"
            )
        ).preDeployVault();

        (, address stakingContract) = 
        IExtFactory(_n.extFactory)
        .deployAll(
            address(this),
            vaultAddress,
            address(nomaToken)
        );

        _n.deployer = Deployer(
            IDeployerFactory(_n.deploymentFactory)
            .deployDeployer(
                address(this), 
                address(_n.resolver)
            )
        );

        _n.deployer.initialize(
            address(this), 
            vaultAddress, 
            address(pool), 
            modelHelper()
        );
        
        IVaultUpgrade(vaultUpgrade)
        .doUpgradeStart(
            vaultAddress, 
            _n.resolver
            .requireAndGetAddress(
                Utils.stringToBytes32("VaultUpgradeFinalize"), 
                "no vaultUpgradeFinalize"
            )
        );

        _initializeVault(
            vaultAddress,
            msg.sender,
            address(_n.deployer), 
            address(pool), 
            modelHelper(), 
            stakingContract,
            address(nomaToken),
            address(0)
        );

        _n.vaultsRepository[address(nomaToken)] = 
        VaultDescription({
            tokenName: _params._name,
            tokenSymbol: _params._symbol,
            tokenDecimals: _params._decimals,
            token0: address(nomaToken),
            token1: _params.token1,
            deployer: msg.sender,
            vault: vaultAddress
        });

        IERC20Metadata(address(nomaToken)).transfer(
            address(_n.deployer),
            _params._totalSupply
        );

        require(nomaToken.balanceOf(                
            address(_n.deployer)
        ) == _params._totalSupply, "supply transfer failed");


        _deployLiquidity(_params._IDOPrice, _params._totalSupply);

        _n.deployers.add(msg.sender);
        _n.totalVaults += 1;
        _n.resolver.importDeployerACL(vaultAddress);        
        _n.deployer.finalize();

        return (vaultAddress, address(pool), address(nomaToken));
    }
    
    function _deployNomaToken(
        string memory _name,
        string memory _symbol,
        address _token1,
        uint256 _totalSupply
    ) internal returns (MockNomaToken) {
        MockNomaToken nomaToken;

        // Calculate the hash of the name and symbol
        bytes32 tokenHash = keccak256(abi.encodePacked(_name, _symbol));

        // Check if the token hash already exists
        require(!_n.deployedTokenHashes[tokenHash], "Token with same name and symbol already exists");

        // Mark this token hash as deployed
        _n.deployedTokenHashes[tokenHash] = true;

        // Generate a pseudo-random nonce from the hash
        uint256 nonce =  uint256(tokenHash);

        do {
            nomaToken = new MockNomaToken{salt: bytes32(nonce)}();
            nonce++; // Increment to avoid collisions in the loop
        } while (address(nomaToken) >= _token1);

        nomaToken.initialize(address(this), _totalSupply, _name, _symbol);

        require(address(nomaToken) < _token1, "invalid token address");

        uint256 totalSupplyFromContract = nomaToken.totalSupply();

        require(totalSupplyFromContract == _totalSupply, "wrong parameters");

        // Encode the initialize function call
        bytes memory data = abi.encodeWithSelector(
            nomaToken.initialize.selector,
            address(this),  // Deployer address
            _totalSupply,   // Initial supply
            _name,          // Token name
            _symbol         // Token symbol
        );

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(nomaToken),
            data
        );

        require(address(proxy) != address(0), "Token deploy failed");

        return nomaToken;
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
        address _owner,
        address _deployer,
        address _pool,
        address _modelHelper,
        address _stakingContract,
        address _token0,
        address _escrowContract
    ) internal {
        BaseVault vault = BaseVault(_vault);

        vault.initialize(
            address(this),
            _owner,
            _deployer,
            _pool,
            _modelHelper,
            _stakingContract,
            _token0,
            _escrowContract
        );
    }

    function _deployLiquidity(uint256 _IDOPrice, uint256 _totalSupply) internal {
        // TODO liquidity structure parameters
        _n.deployer.deployFloor(_IDOPrice, _totalSupply * 25 / 100);
        _n.deployer.deployAnchor(500, 1200, _totalSupply * 15 / 100);
        _n.deployer.deployDiscovery(_IDOPrice * 3);
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

    function getVaultDescription(address deployer) external view returns (VaultDescription memory) {
        return _n.vaultsRepository[deployer];
    }

    function getDeployers() external view returns (address[] memory) {
        address[] memory deployers = new address[](_n.deployers.length());
        for (uint256 i = 0; i < _n.deployers.length(); i++) {
            deployers[i] = _n.deployers.at(i);
        }
        return deployers;
    }

    function modelHelper() public view returns (address) {
        return _n.resolver
                .requireAndGetAddress(
                    Utils.stringToBytes32("ModelHelper"), 
                    "no modelHelper"
                );
    }

    function deployer() public view returns (address) {
        return _n.resolver
                .requireAndGetAddress(
                    Utils.stringToBytes32("Deployer"), 
                    "no Deployer"
                );
    }


    modifier isAuthority() {
        require(msg.sender == _n.authority, "NFA");
        _;
    }
}