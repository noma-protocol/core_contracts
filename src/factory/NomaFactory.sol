// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
    VaultInitParams,
    LiquidityStructureParameters
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

interface IERC20 {
    function mint(address to, uint256 amount) external;
}

error OnlyVaultsError();
error NotAuthorityError();
error TokenDeployFailedError();
error InvalidTokenAddressError();
error SupplyTransferFailedError();
error TokenAlreadyExistsError();
error OnlyOneVaultError();
error InvalidSymbol();

contract NomaFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    NomaFactoryStorage internal _n;
    
    constructor(
        address _uniswapV3Factory,
        address _resolver,
        address _deploymentFactory,
        address _extFactory,
        bool _permissionlessDeployEnabled
    ) {
        _n.authority = msg.sender;
        _n.uniswapV3Factory = _uniswapV3Factory;
        _n.resolver = IAddressResolver(_resolver);
        _n.deploymentFactory = _deploymentFactory;
        _n.extFactory = _extFactory;
        _n.permissionlessDeployEnabled = false;
    }

    function deployVault(
        VaultDeployParams memory _params
    ) external checkDeployAuthority returns (address, address, address) {
        _validateToken1(_params.token1);

        MockNomaToken nomaToken = _deployNomaToken(
            _params._name,
            _params._symbol,
            _params.token1, 
            _params._totalSupply
        );
        
        IUniswapV3Pool pool = _deployPool(
            _params._IDOPrice,
            address(nomaToken), 
            _params.token1
        );

        (address vaultAddress, address vaultUpgrade) = IEtchVault(
            _n.resolver.requireAndGetAddress(
                Utils.stringToBytes32("EtchVault"), 
                "no EtchVault"
            )
        ).preDeployVault();

        (, address stakingContract) = IExtFactory(_n.extFactory).deployAll(
            address(this),
            vaultAddress,
            address(nomaToken)
        );

        _n.deployer = Deployer(
            IDeployerFactory(_n.deploymentFactory).deployDeployer(
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
        
        IVaultUpgrade(vaultUpgrade).doUpgradeStart(
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
            adaptiveSupply(),
            getLiquidityStructureParameters()
        );

        VaultDescription memory vaultDesc = VaultDescription({
            tokenName: _params._name,
            tokenSymbol: _params._symbol,
            tokenDecimals: _params._decimals,
            token0: address(nomaToken),
            token1: _params.token1,
            deployer: msg.sender,
            vault: vaultAddress
        });

        IERC20Metadata(address(nomaToken)).transfer(address(_n.deployer), _params._totalSupply);

        if (nomaToken.balanceOf(address(_n.deployer)) != _params._totalSupply) revert SupplyTransferFailedError();

        _deployLiquidity(_params._IDOPrice, _params._totalSupply, getLiquidityStructureParameters());

        _n.resolver.configureDeployerACL(vaultAddress);        
        _n.deployer.finalize();

        _n.vaultsRepository[vaultAddress] = vaultDesc;
        _n._vaults[msg.sender].add(vaultAddress);
        _n.deployers.add(msg.sender);
        _n.totalVaults += 1;

        return (vaultAddress, address(pool), address(nomaToken));
    }

    function _deployNomaToken(
        string memory _name,
        string memory _symbol,
        address _token1,
        uint256 _totalSupply
    ) internal returns (MockNomaToken) {
        bytes32 tokenHash = keccak256(abi.encodePacked(_name, _symbol));

        if (_n.deployedTokenHashes[tokenHash]) revert TokenAlreadyExistsError();

        _n.deployedTokenHashes[tokenHash] = true;
        uint256 nonce = uint256(tokenHash);

        MockNomaToken nomaToken;
        do {
            nomaToken = new MockNomaToken{salt: bytes32(nonce)}();
            nonce++;
        } while (address(nomaToken) >= _token1);

        nomaToken.initialize(_n.authority, _totalSupply, _name, _symbol, address(_n.resolver));

        if (address(nomaToken) >= _token1) revert InvalidTokenAddressError();

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
        address _adaptiveSupply,
        LiquidityStructureParameters memory _params
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
            _adaptiveSupply,
            _params
        );
    }

    function _deployLiquidity(
        uint256 _IDOPrice, 
        uint256 _totalSupply,
        LiquidityStructureParameters memory _liquidityParams
        ) internal {
        _n.deployer.deployFloor(_IDOPrice, _totalSupply * _liquidityParams.floorPercentage / 100);  
        _n.deployer.deployAnchor(
            _liquidityParams.floorBips[0], 
            _liquidityParams.floorBips[1], 
            _totalSupply * _liquidityParams.anchorPercentage / 100
        );
        _n.deployer.deployDiscovery(_IDOPrice * _liquidityParams.idoPriceMultiplier);
    }

    function mintTokens(address to, uint256 amount) public onlyVaults {
        IERC20(_n.vaultsRepository[msg.sender].token0).mint(to, amount);
    }

    function setLiquidityStructureParameters(
        LiquidityStructureParameters memory _params
    ) public isAuthority {
        _n.liquidityStructureParameters = _params;
    }

    function setPermissionlessDeploy(bool _flag) public isAuthority {
        _n.permissionlessDeployEnabled = _flag;
    }

    function _validateToken1(address token) internal view {
        bytes32 result;
        string memory symbol = IERC20Metadata(token).symbol();
        bytes memory symbol32 = bytes(symbol);

        if (symbol32.length == 0) {
            revert InvalidSymbol();
        }

        assembly {
            result := mload(add(symbol, 32))
        }
        _n.resolver.requireAndGetAddress(result, "not a reserve token");
    }

    function getLiquidityStructureParameters() public view returns 
    (LiquidityStructureParameters memory) {
        return _n.liquidityStructureParameters;
    }

    function getVaultDescription(address deployer) external view returns (VaultDescription memory) {
        return _n.vaultsRepository[deployer];
    }

    function getDeployers() public view returns (address[] memory) {
        uint256 length = numDeployers();
        address[] memory deployers = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            deployers[i] = _getDeployer(i);
        }

        return deployers;
    }

    function getVaults(address deployer) public view returns (address[] memory) {
        uint256 length = numVaults(deployer);
        address[] memory vaults = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            vaults[i] = _getVault(deployer, i);
        }

        return vaults;
    }

    function numVaults() public view returns (uint256 result) {
        address[] memory deployers = getDeployers();
        for (uint256 i = 0; i < deployers.length; i++) {
            result += numVaults(deployers[i]);
        }
    }

    function numDeployers() public view returns (uint256) {
        return _n.deployers.length();
    }

    function numVaults(address deployer) public view returns (uint256) {
        return _n._vaults[deployer].length();
    }

    function _getDeployer(uint256 index) internal view returns (address) {
        return _n.deployers.at(index);
    }

    function _getVault(address deployer, uint256 index) internal view returns (address) {
        return _n._vaults[deployer].at(index);
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

    function adaptiveSupply() public view returns (address) {
        return _n.resolver
                .requireAndGetAddress(
                    Utils.stringToBytes32("AdaptiveSupply"), 
                    "no AdaptiveSupply"
                );
    }

    modifier checkDeployAuthority() {
        if (!_n.permissionlessDeployEnabled) {
            if (msg.sender != _n.authority) revert NotAuthorityError();
        }
        _;
    }

    modifier isAuthority() {
        if (msg.sender != _n.authority) revert NotAuthorityError();
        _;
    }

    modifier onlyVaults() {
        if (_n.vaultsRepository[msg.sender].vault != msg.sender) revert OnlyVaultsError();
        _;
    }

}
