// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ███╗   ██╗ ██████╗ ███╗   ███╗ █████╗                               
// ████╗  ██║██╔═══██╗████╗ ████║██╔══██╗                              
// ██╔██╗ ██║██║   ██║██╔████╔██║███████║                              
// ██║╚██╗██║██║   ██║██║╚██╔╝██║██╔══██║                              
// ██║ ╚████║╚██████╔╝██║ ╚═╝ ██║██║  ██║                              
// ╚═╝  ╚═══╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝                              
                                                                    
// ██████╗ ██████╗  ██████╗ ████████╗ ██████╗  ██████╗ ██████╗ ██╗     
// ██╔══██╗██╔══██╗██╔═══██╗╚══██╔══╝██╔═══██╗██╔════╝██╔═══██╗██║     
// ██████╔╝██████╔╝██║   ██║   ██║   ██║   ██║██║     ██║   ██║██║     
// ██╔═══╝ ██╔══██╗██║   ██║   ██║   ██║   ██║██║     ██║   ██║██║     
// ██║     ██║  ██║╚██████╔╝   ██║   ╚██████╔╝╚██████╗╚██████╔╝███████╗
// ╚═╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝  ╚═════╝ ╚═════╝ ╚══════╝
//
// Contract: NomaFactory.sol
// Author: 0xsufi@noma.money
// Copyright Noma Protocol 2024/2026

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IUniswapV3Factory } from "v3-core/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { VaultDescription } from "../types/Types.sol";
import { IAddressResolver } from "../interfaces/IAddressResolver.sol";
import { Conversions } from "../libraries/Conversions.sol";
import { Utils } from "../libraries/Utils.sol";
import { SupplyRules } from "../libraries/SupplyRules.sol";
import { BaseVault } from "../vault/BaseVault.sol";
import { NomaToken } from "../token/NomaToken.sol";
import { Deployer } from "../Deployer.sol";
import { VaultUpgrade, VaultUpgradeStep1 } from "../vault/init/VaultUpgrade.sol";
import {
    VaultInitParams,
    PresaleUserParams,
    PresaleDeployParams,
    VaultDeployParams,
    ProtocolParameters,
    PresaleProtocolParams,
    DeploymentData,
    ExistingDeployData,
    PostInitParams,
    ExtDeployParams
} from "../types/Types.sol";

import {IVaultUpgrade, IEtchVault, IExtFactory, IDeployerFactory} from "../interfaces/IVaultUpgrades.sol";
import "../errors/Errors.sol";

/**
 * @title IERC20
 * @notice Interface for the ERC20 standard token, including a mint function.
 */
interface IERC20Extended {
    /**
     * @notice Mints new tokens to a specified address.
     * @param to The address to receive the newly minted tokens.
     * @param amount The amount of tokens to be minted.
     */
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

interface IPresaleFactory {
    function createPresale(
        PresaleDeployParams memory params,
        PresaleProtocolParams memory protocolParams
    ) external returns (address);
}  

interface ITokenFactory {
    function deployNomaToken(VaultDeployParams memory vaultDeployParams, address owner) external returns (NomaToken, ERC1967Proxy, bytes32);
}

/**
 * @title IDiamondInterface
 * @notice Interface for the Diamond proxy contract.
 */
interface IDiamondInterface {
    function initialize() external;
    function transferOwnership(address) external;
}

interface IVault {
    function postInit(PostInitParams memory params) external;
}

/**
 * @title NomaFactory
 * @notice This contract facilitates the deployment and management of Noma Vaults, including associated tokens and liquidity pools.
 */
contract NomaFactory {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using SupplyRules for uint256;

    // Noma Factory state
    IAddressResolver private immutable resolver;
    address private immutable presaleFactory;
    address private immutable deployerFactory;
    address private immutable extFactory;
    address private immutable uniswapV3Factory;
    address private immutable pancakeSwapV3Factory;
    address private authority;
    address private teamMultisigAddress;

    uint256 private totalVaults;
    bool private permissionlessDeployEnabled;    

    ProtocolParameters private protocolParameters;
    PresaleProtocolParams private presaleProtocolParams;
    EnumerableSet.AddressSet private deployers; 

    mapping(address => EnumerableSet.AddressSet) private _vaults;
    mapping(address => VaultDescription) private vaultsRepository;
    mapping(bytes32 => bool) private deployedTokenHashes;
    mapping(address => VaultDeployParams) private deferredDeployParams;
    mapping(address => address) private poolToVaultMapping;

    /**
     * @notice Constructor to initialize the NomaFactory contract.
     * @param _uniswapV3Factory The address of the Uniswap V3 Factory contract.
     * @param _pancakeSwapV3Factory The address of the PancakeSwap V3 Factory contract.
     * @param _resolver The address of the Address Resolver contract.
     * @param _deployerFactory The address of the Deployment Factory contract.
     * @param _extFactory The address of the External Factory contract.
     */
    constructor(
        address _uniswapV3Factory,
        address _pancakeSwapV3Factory,
        address _resolver,
        address _deployerFactory,
        address _extFactory,
        address _presaleFactory
    ) {
        if (
            _uniswapV3Factory == address(0) ||
            _pancakeSwapV3Factory == address(0) ||
            _resolver == address(0)         || 
            _deployerFactory == address(0)  || 
            _extFactory == address(0)       ||
            _presaleFactory == address(0)
        ) revert ZeroAddress();

        authority = msg.sender;
        teamMultisigAddress = msg.sender;
        uniswapV3Factory = _uniswapV3Factory;
        pancakeSwapV3Factory = _pancakeSwapV3Factory;
        resolver = IAddressResolver(_resolver);
        deployerFactory = _deployerFactory;
        extFactory = _extFactory;
        presaleFactory = _presaleFactory;
        permissionlessDeployEnabled = true;
    }

    function deployVault(
        PresaleUserParams memory presaleParams,
        VaultDeployParams memory vaultDeployParams,
        ExistingDeployData memory existingDeployData
    ) public payable
    checkDeployAuthority  
    returns (address, address, address) {
        _validateToken1(vaultDeployParams.token1);
        int24 tickSpacing = Utils._validateFeeTier(vaultDeployParams.feeTier);
        SupplyRules.enforceMinTotalSupply(
            vaultDeployParams.IDOPrice, 
            vaultDeployParams.initialSupply,
            getProtocolParameters().basePriceDecimals
        );

        if (
            // Protected ticker
            (
                msg.sender != authority && 
                keccak256(bytes(vaultDeployParams.symbol)) == keccak256(bytes("NOMA"))
            ) || 
            deployedTokenHashes[
                keccak256(
                    abi.encodePacked(vaultDeployParams.name, vaultDeployParams.symbol)
                )
            ]
        ) revert TokenAlreadyExistsError();

        if (
            vaultDeployParams.decimals < getProtocolParameters().decimals.minDecimals ||
            vaultDeployParams.decimals > getProtocolParameters().decimals.maxDecimals
        ) {
            revert InvalidParams();
        }

        ERC1967Proxy proxy; 
        IUniswapV3Pool pool;
        
        if (vaultDeployParams.isFreshDeploy) {
            (, proxy, ) =
            ITokenFactory(tokenFactory())
            .deployNomaToken(
                vaultDeployParams, 
                msg.sender
            );

            pool = _deployPool(
                vaultDeployParams.IDOPrice,
                address(proxy), 
                vaultDeployParams.token1,
                vaultDeployParams.feeTier,
                tickSpacing,
                vaultDeployParams.useUniswap
            );
        } else {
            proxy = ERC1967Proxy(payable(address(existingDeployData.token0)));
            pool = IUniswapV3Pool(existingDeployData.pool);
        }

        if (vaultDeployParams.presale == 1 && msg.sender != authority) {
            uint256 deployFee = getProtocolParameters().deployFee;
            if (msg.value < deployFee) {
                revert InvalidParams();
            } else {
                address payable recipient = teamMultisigAddress != address(0)
                    ? payable(teamMultisigAddress)
                    : payable(authority);

                (bool success, ) = recipient.call{value: msg.value}("");
            }
        }

        return _finalizeVaultDeployment(
            vaultDeployParams, 
            DeploymentData({
                presaleParams: presaleParams,
                vaultDeployParams: vaultDeployParams,
                pool: pool,
                proxy: proxy,
                tickSpacing: tickSpacing,
                vaultAddress: address(0),
                vaultUpgrade: address(0),
                sNOMA: address(0),
                stakingContract: address(0),
                presaleContract: address(0),
                tokenRepo: address(0),
                vToken: address(0)
            })
        );
    }

    function _finalizeVaultDeployment(
        VaultDeployParams memory vaultDeployParams,
        DeploymentData memory data
    ) internal returns (address, address, address) {

        (
            data.vaultAddress, 
            data.vaultUpgrade
        ) = IEtchVault(
            resolver.requireAndGetAddress(
                Utils.stringToBytes32("EtchVault"), 
                "no EtchVault"
            )
        ).preDeployVault(address(resolver));

        Deployer deployer = Deployer(
            IDeployerFactory(deployerFactory)
            .deployDeployer(
                address(this), 
                address(resolver)
            )
        );

        deployer.initialize(
            address(this), 
            data.vaultAddress, 
            address(data.pool), 
            modelHelper()
        );

        // Basic Vault setup
        IVaultUpgrade(data.vaultUpgrade)
        .doUpgradeStart(
            data.vaultAddress
        );

        IERC20(address(data.proxy)).safeTransfer(address(deployer), data.vaultDeployParams.initialSupply);

        if (
            IERC20(address(data.proxy)).balanceOf(address(deployer)) != 
            data.vaultDeployParams.initialSupply
        ) {
            revert SupplyTransferError();
        }

        if (vaultDeployParams.presale == 1) {
            data.presaleContract = 
            _configurePresale(
                address(deployer),
                address(data.proxy),
                address(deployer),
                data.stakingContract,
                address(data.pool),
                data.vaultAddress,
                data.tokenRepo,
                data.vaultDeployParams,
                data.presaleParams
            );        
        } else {
            _deferDeploy(
                address(deployer),
                address(data.pool), 
                data.vaultAddress,
                data.stakingContract,
                data.tokenRepo,
                data.vaultDeployParams, 
                data.presaleParams
            );
        }

        vaultsRepository[data.vaultAddress] = 
        VaultDescription({
            tokenName: data.vaultDeployParams.name,
            tokenSymbol: data.vaultDeployParams.symbol,
            tokenDecimals: data.vaultDeployParams.decimals,
            token0: address(data.proxy),
            token1: data.vaultDeployParams.token1,
            deployer: msg.sender,
            deployerContract: address(deployer),
            vault: data.vaultAddress,
            presaleContract: data.presaleContract,
            stakingContract: data.stakingContract
        });

        _vaults[msg.sender].add(data.vaultAddress);
        poolToVaultMapping[address(data.pool)] = data.vaultAddress;

        deployers.add(msg.sender);
        totalVaults += 1;

        return (data.vaultAddress, address(data.pool), address(data.proxy));
    }

    function configureVault(address vaultAddress, uint8 step)
        public
        returns (DeploymentData memory data)
    {
        VaultDescription memory vaultDesc = vaultsRepository[vaultAddress];

        if (msg.sender != vaultDesc.deployer) {
            revert Unauthorized();
        }

        data = executeStep1(vaultAddress);
        doUpgrade(vaultAddress, "VaultUpgradeStep1");        
        doUpgrade(vaultAddress, "VaultUpgradeStep2");   
        doUpgrade(vaultAddress, "VaultUpgradeStep3");   
        doUpgrade(vaultAddress, "VaultUpgradeStep4");   
        doUpgrade(vaultAddress, "VaultUpgradeStep5");                           

        return data;
    }

    function doUpgrade(address vaultAddress, string memory contractName) internal {
        address vaultUpgradeStep = resolver.requireAndGetAddress(
            Utils.stringToBytes32(contractName),
            "Error etching vault"
        );
        IDiamondInterface(vaultAddress).transferOwnership(vaultUpgradeStep);
        VaultUpgrade(vaultUpgradeStep).doUpgradeStart(vaultAddress);        
    }

    function executeStep1(address vaultAddress)
        internal
        returns (DeploymentData memory data)
    {
        VaultDescription memory vaultDesc = vaultsRepository[vaultAddress];
        uint256 totalSupply = IERC20(vaultDesc.token0).totalSupply();

        // Original Step 1 logic
        (
            data.sNOMA, 
            data.stakingContract, 
            data.tokenRepo, 
            data.vToken
        ) = IExtFactory(extFactory)
        .deployAll(
            ExtDeployParams({
                name: vaultDesc.tokenName,
                symbol: vaultDesc.tokenSymbol,
                deployerAddress: address(this),
                vaultAddress: vaultAddress,
                token0: vaultDesc.token0,
                totalSupply: totalSupply
            })
        );

        address vaultUpgrade = resolver
        .requireAndGetAddress(
            Utils.stringToBytes32("VaultUpgrade"),
            "no VaultUpgrade"
        );

        IDiamondInterface(vaultAddress).transferOwnership(vaultUpgrade);
        VaultUpgrade(vaultUpgrade).doUpgradeStart(vaultAddress);

        Utils
        .configureVaultResolver(
            address(resolver),
            vaultAddress,
            data.stakingContract,
            data.sNOMA,
            vaultDesc.presaleContract,
            adaptiveSupply(),
            modelHelper(),
            vaultDesc.deployerContract,
            data.vToken
        );

        // This ideally should be executed after step 2, 3 and 4 
        IVault(vaultAddress)
        .postInit(
            PostInitParams({
                stakingContract: data.stakingContract,
                tokenRepo: data.tokenRepo,
                sToken: data.sNOMA,
                vToken: data.vToken
            })
        );

        // `data` is populated only for step 1; for others it stays default
        return data;
    }

    function _configurePresale(
        address deployerContract,
        address proxy,
        address deployer,
        address stakingContract,
        address pool,
        address vaultAddress,
        address tokenRepo,
        VaultDeployParams memory vaultDeployParams,
        PresaleUserParams memory presaleParams
    ) internal returns (address) {

        address presaleContract = 
        _deferDeploy(
            deployerContract,
            address(pool), 
            vaultAddress,
            stakingContract,
            tokenRepo,
            vaultDeployParams, 
            presaleParams
        );

        _initializeVault(
            VaultInitParams({
                vaultAddress: vaultAddress,
                owner: msg.sender,
                deployer: address(deployer),
                pool: pool,
                stakingContract: stakingContract,
                presaleContract: presaleContract,
                token0: proxy,
                tokenRepo: tokenRepo,
                protocolParameters: getProtocolParameters()
            })
        );
        
        return presaleContract;
    }

    function _deferDeploy(
        address deployerContract,
        address pool,
        address vaultAddress,
        address stakingContract,
        address tokenRepo,
        VaultDeployParams memory vaultDeployParams,
        PresaleUserParams memory presaleParams
    ) internal returns (address presaleAddress) {
        int24 tickSpacing = Utils._validateFeeTier(vaultDeployParams.feeTier);

        uint256 initialPrice = _calculatePresalePremium(vaultDeployParams.IDOPrice);

        if (vaultDeployParams.presale == 1) {
            // Deferred deploy - create parameters
            deferredDeployParams[vaultAddress] = vaultDeployParams;

            presaleAddress = 
            IPresaleFactory(presaleFactory)
            .createPresale(
                PresaleDeployParams({
                    deployer: msg.sender,
                    vaultAddress: vaultAddress,
                    pool: pool,
                    softCap: presaleParams.softCap,
                    initialPrice: initialPrice,
                    deadline: presaleParams.deadline,
                    name: string(abi.encodePacked(vaultDeployParams.name, " Pre Asset")),
                    symbol: string(abi.encodePacked("p-", vaultDeployParams.symbol)),
                    decimals: vaultDeployParams.decimals,
                    tickSpacing: tickSpacing,
                    floorPercentage: getProtocolParameters().floorPercentage,
                    totalSupply: vaultDeployParams.initialSupply
                }),
                getPresaleProtocolParams()
            );

            return presaleAddress;

        } else {
            // Deploy immediately
            _initializeVault(
                VaultInitParams({
                    vaultAddress: vaultAddress,
                    owner: msg.sender,
                    deployer: deployerContract,
                    pool: pool,
                    stakingContract: stakingContract,
                    presaleContract: address(0), // no presale contract
                    token0: IUniswapV3Pool(pool).token0(),
                    tokenRepo: tokenRepo,
                    protocolParameters: getProtocolParameters()
                })
            );
            _deployLiquidity(
                deployerContract,
                vaultDeployParams.IDOPrice, 
                vaultDeployParams.initialSupply, 
                tickSpacing, 
                getProtocolParameters()
            );
            Deployer(deployerContract).finalize();
        }    
    }

    function deferredDeploy(address _deployerContract) public onlyVaults {
        VaultDeployParams memory _params = deferredDeployParams[msg.sender];   
        int24 tickSpacing = Utils._validateFeeTier(_params.feeTier); 

        _deployLiquidity(
            _deployerContract,
            _params.IDOPrice, 
            _params.initialSupply, 
            tickSpacing, 
            getProtocolParameters()
        );

        Deployer(_deployerContract).finalize();
        delete deferredDeployParams[msg.sender];        
    }

    /**
    * @notice Deploys a Uniswap V3 pool for the given token pair and initializes it with the specified price.
    * @param _initPrice The initial price of the pool.
    * @param token0 The address of the first token.
    * @param token1 The address of the second token.
    * @param feeTier The fee tier of the pool.
    * @param tickSpacing The tick spacing of the pool.
    * @return pool The address of the deployed Uniswap V3 pool.
    * @dev This internal function checks if the pool already exists; if not, it creates a new pool and initializes it with the provided price.
    */
    function _deployPool(
        uint256 _initPrice,
        address token0,
        address token1,
        uint24 feeTier,
        int24 tickSpacing,
        bool useUniswap
    ) internal returns (IUniswapV3Pool pool) {
        IUniswapV3Factory factory = IUniswapV3Factory(useUniswap ? uniswapV3Factory : pancakeSwapV3Factory);
        IUniswapV3Pool _pool = IUniswapV3Pool(
            factory.getPool(token0, token1, feeTier)
        );
        uint8 decimals = IERC20Metadata(token0).decimals();

        if (address(_pool) == address(0)) {
            _pool = IUniswapV3Pool(
                factory.createPool(
                    token0, 
                    token1, 
                    feeTier
                )
            );
            _pool.initialize(
                Conversions
                .priceToSqrtPriceX96(
                    int256(_initPrice), 
                    tickSpacing,
                    decimals
                )
            );            
        }

        return _pool;
    }

    /**
    * @notice Deploys liquidity for the vault based on the provided parameters.
    * @param IDOPrice The initial DEX offering price.
    * @param totalSupply The total supply of the token.
    * @param _liquidityParams The parameters defining the liquidity structure.
    * @dev This internal function deploys floor, anchor, and discovery liquidity using the deployer contract.
    */
    function _deployLiquidity(
        address deployerContract,
        uint256 IDOPrice,
        uint256 totalSupply,
        int24 _tickSpacing,
        ProtocolParameters memory _liquidityParams
    ) internal {
        Deployer(deployerContract)
        .deployFloor(
            IDOPrice, 
            totalSupply * _liquidityParams.floorPercentage / 100, 
            _tickSpacing
        );  
        Deployer(deployerContract)
        .deployAnchor(
            _liquidityParams.floorBips[1], 
            totalSupply * _liquidityParams.anchorPercentage / 100
        );
        Deployer(deployerContract)
        .deployDiscovery(
            IDOPrice * _liquidityParams.idoPriceMultiplier
        );
    }


    /**
    * @notice Initializes the vault with the provided parameters.
    */
    function _initializeVault(
        VaultInitParams memory _params
    ) internal {
        BaseVault vault = BaseVault(_params.vaultAddress);

        vault.initialize(
            address(this),
            _params.owner,
            _params.deployer,
            _params.pool,
            _params.presaleContract,
            _params.protocolParameters
        );
    }

    /**
    * @notice Mints new tokens to the specified address.
    * @param to The address to receive the minted tokens.
    * @param amount The amount of tokens to mint.
    * @dev This function can only be called by authorized vaults.
    */
    function mintTokens(address to, uint256 amount) public onlyVaults {
        address token0 = vaultsRepository[msg.sender].token0;
        IERC20Extended(token0).mint(to, amount);
    }

    /**
    * @notice Burns tokens from the specified address.
    * @param from The address from which to burn tokens.
    * @param amount The amount of tokens to burn.
    * @dev This function can only be called by authorized vaults.
    */
    function burnFor(address from, uint256 amount) public onlyVaults {
        address token0 = vaultsRepository[msg.sender].token0;
        IERC20Extended(token0).burn(from, amount);
    }

    /**
    * @notice Sets the parameters for the liquidity structure.
    * @param _params The new liquidity structure parameters.
    * @dev This function can only be called by the authority.
    */
    function setProtocolParameters( 
        ProtocolParameters memory _params
    ) public isAuthority {
        protocolParameters = _params;
    }

    /**
    * @notice Sets the parameters for the presale structure.
    * @param _params The new presale structure parameters.
    * @dev This function can only be called by the authority.
    */
    function setPresaleProtocolParams(
        PresaleProtocolParams memory _params
    ) public isAuthority {
        presaleProtocolParams = _params;
    }

    /**
    * @notice Enables or disables permissionless deployment.
    * @param _flag A boolean indicating whether to enable (true) or disable (false) permissionless deployment.
    * @dev This function can only be called by the authority.
    */
    function setPermissionlessDeploy(bool _flag) public isAuthority {
        permissionlessDeployEnabled = _flag;
    }

    /**
    * @notice Sets the address of the multisig wallet.
    * @param _address The new address of the multisig wallet.
    * @dev This function can only be called by the current multisig address.
    * It reverts if the provided address is zero.
    */
    function setMultiSigAddress(address _address) public {
        if (msg.sender != teamMultisigAddress && msg.sender != authority) revert NotAuthorized();
        if (_address == address(0)) revert ZeroAddress();
        teamMultisigAddress = _address;
    }

    function setVaultOwnership(address vaultAddress, address newOwner) public {
        if (msg.sender != teamMultisigAddress && msg.sender != authority) revert NotAuthorized();
        IDiamondInterface(vaultAddress).transferOwnership(newOwner);
    }

    /**
    * @notice Upgrades the implementation of a token to a new version.
    * @param _token The address of the token to upgrade.
    * @param _newImplementation The address of the new implementation contract.
    * @dev This function can only be called by the authority.
    * It uses the `upgradeToAndCall` function of the NomaToken contract to perform the upgrade.
    */
    function upgradeToken(
        address _token,
        address _newImplementation
    ) public isAuthority {
        NomaToken(_token).upgradeToAndCall(_newImplementation, new bytes(0));
    }

    function _calculatePresalePremium(uint256 _idoPrice) internal view returns (uint256) {
        uint256 premium = protocolParameters.presalePremium;
        if (premium == 0) revert InvalidParams();
        uint256 presalePrice = _idoPrice + (_idoPrice * premium / 100);
        return presalePrice;
    }

    /**
    * @notice Validates the provided token address.
    * @param token The address of the token to validate.
    * @dev This internal function checks if the token has a valid symbol and is recognized by the resolver.
    * It reverts if the token symbol is invalid or not recognized.
    */
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
        resolver.requireAndGetAddress(result, "not a reserve token");
    }

    /**
    * @notice Retrieves the current liquidity structure parameters.
    * @return The current liquidity structure parameters.
    */
    function getProtocolParameters() public view returns 
    (ProtocolParameters memory) {
        return protocolParameters;
    }

    /**
    * @notice Retrieves the current presale structure parameters.
    * @return The current presale structure parameters.
    */
    function getPresaleProtocolParams() public view returns
    (PresaleProtocolParams memory) {
        return presaleProtocolParams;
    }
    
    /**
    * @notice Retrieves the description of a specific vault.
    * @param vault The address of the vault.
    * @return The vault description associated with the vault.
    */
    function getVaultDescription(address vault) external view returns (VaultDescription memory) {
        return vaultsRepository[vault];
    }

    /**
    * @notice Retrieves the list of all deployers.
    * @return An array containing the addresses of all deployers.
    */
    function getDeployers() public view returns (address[] memory) {
        uint256 length = numDeployers();
        address[] memory _deployers = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            _deployers[i] = _getDeployer(i);
        }

        return _deployers;
    }

    /**
    * @notice Retrieves the list of vaults deployed by a specific deployer.
    * @param _deployer The address of the deployer.
    * @return An array containing the addresses of the deployer's vaults.
    */
    function getVaults(address _deployer) public view returns (address[] memory) {
        uint256 length = numVaults(_deployer);
        address[] memory vaults = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            vaults[i] = _getVault(_deployer, i);
        }

        return vaults;
    }

    /**
    * @notice Retrieves the total number of deployers.
    * @return The total number of deployers.
    */
    function numDeployers() public view returns (uint256) {
        return deployers.length();
    }

    /**
    * @notice Retrieves the number of vaults deployed by a specific deployer.
    * @param _deployer The address of the deployer.
    * @return The number of vaults deployed by the specified deployer.
    */
    function numVaults(address _deployer) public view returns (uint256) {
        return _vaults[_deployer].length();
    }

    /**
     * @notice Retrieves the address of a deployer at a specific index.
     * @param index The index position of the deployer in the EnumerableSet.
     * @return The address of the deployer.
     */
    function _getDeployer(uint256 index) internal view returns (address) {
        return deployers.at(index);
    }

    /**
     * @notice Retrieves the address of a vault deployed by a specific deployer at a given index.
     * @param _deployer The address of the deployer.
     * @param index The index position of the vault in the deployer's EnumerableSet.
     * @return The address of the vault.
     */
    function _getVault(address _deployer, uint256 index) internal view returns (address) {
        return _vaults[_deployer].at(index);
    }

    function getVaultsRepository(address vault) public view returns (VaultDescription memory) {
        return vaultsRepository[vault];
    }
    
    /**
     * @notice Retrieves the vault address associated with a given Uniswap V3 pool.
     * @param pool The address of the Uniswap V3 pool.
     * @return The address of the vault associated with the specified pool.
     */
    function getVaultFromPool(address pool) public view returns (address) {
        return poolToVaultMapping[pool];
    }

    /**
     * @notice Retrieves the address of the authority.
     * @return The address of the authority.
     */
    function owner() public view returns (address) {
        return authority;
    }

    /**
     * @notice Fetches the address of the ModelHelper contract from the resolver.
     * @return The address of the ModelHelper contract.
     */
    function modelHelper() public view returns (address) {
        return resolver
        .requireAndGetAddress(
            Utils.stringToBytes32("ModelHelper"), 
            "no modelHelper"
        );
    }

    /**
     * @notice Fetches the address of the AdaptiveSupply contract from the resolver.
     * @return The address of the AdaptiveSupply contract.
     */
    function adaptiveSupply() public view returns (address) {
        return resolver
        .requireAndGetAddress(
            Utils.stringToBytes32("AdaptiveSupply"), 
            "no AdaptiveSupply"
        );
    }

    function tokenFactory() public view returns (address) {
        return resolver
        .requireAndGetAddress(
            Utils.stringToBytes32("TokenFactory"), 
            "no TokenFactory"
        );
    }

    /**
     * @notice Retrieves the address of the team multisig wallet.
     * @return The address of the team multisig wallet.
     */
    function teamMultiSig() public view returns (address) {
        return teamMultisigAddress;
    }

    /**
     * @notice Modifier to check if the caller has the authority to deploy.
     * @dev Reverts with NotAuthorityError if the caller lacks deployment authority.
     */
    modifier checkDeployAuthority() {
        if (!permissionlessDeployEnabled) {
            if (msg.sender != authority) revert NotAuthorized();
        }
        _;
    }

    /**
     * @notice Modifier to ensure that the caller is the designated authority.
     * @dev Reverts with NotAuthorityError if the caller is not the authority.
     */
    modifier isAuthority() {
        if (msg.sender != authority) revert NotAuthorized();
        _;
    }

    /**
     * @notice Modifier to restrict function access to authorized vaults.
     * @dev Reverts with OnlyVaultsError if the caller is not an authorized vault.
     */
    modifier onlyVaults() {
        if (vaultsRepository[msg.sender].vault != msg.sender) revert OnlyVault();
        _;
    }
}
