// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { IUniswapV3Factory } from "v3-core/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { VaultDescription } from "../types/Types.sol";

import { IAddressResolver } from "../interfaces/IAddressResolver.sol";
import { Conversions } from "../libraries/Conversions.sol";
import { Utils } from "../libraries/Utils.sol";

import { BaseVault } from "../vault/BaseVault.sol";
import { MockNomaToken } from "../token/MockNomaToken.sol";
import { Deployer } from "../Deployer.sol";

import {
    PresaleUserParams,
    PresaleDeployParams,
    VaultDeployParams,
    ProtocolParameters,
    PresaleProtocolParams,
    DeploymentData
} from "../types/Types.sol";

import {IVaultUpgrade, IEtchVault, IExtFactory, IDeployerFactory} from "../interfaces/IVaultUpgrades.sol";

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
    function deployNomaToken(VaultDeployParams memory vaultDeployParams) external returns (MockNomaToken, ERC1967Proxy, bytes32);
}

error OnlyVaultsError();
error NotAuthorityError();
error SupplyTransferError();
error InvalidSymbol();
error ZeroAddressError();
error InvalidTickSpacing();
error TokenAlreadyExistsError();

/**
 * @title NomaFactory
 * @notice This contract facilitates the deployment and management of Noma Vaults, including associated tokens and liquidity pools.
 */
contract NomaFactory {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // Noma Factory state
    IAddressResolver private resolver;
    Deployer private deployer;

    address private presaleFactory;
    address private deployerFactory;
    address private extFactory;
    address private authority;
    address private uniswapV3Factory;
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

    /**
     * @notice Constructor to initialize the NomaFactory contract.
     * @param _uniswapV3Factory The address of the Uniswap V3 Factory contract.
     * @param _resolver The address of the Address Resolver contract.
     * @param _deployerFactory The address of the Deployment Factory contract.
     * @param _extFactory The address of the External Factory contract.
     */
    constructor(
        address _uniswapV3Factory,
        address _resolver,
        address _deployerFactory,
        address _extFactory,
        address _presaleFactory
    ) {
        if (
            _uniswapV3Factory == address(0) || 
            _resolver == address(0)         || 
            _deployerFactory == address(0)  || 
            _extFactory == address(0)       ||
            _presaleFactory == address(0)
        ) revert ZeroAddressError();

        authority = msg.sender;
        uniswapV3Factory = _uniswapV3Factory;
        resolver = IAddressResolver(_resolver);
        deployerFactory = _deployerFactory;
        extFactory = _extFactory;
        presaleFactory = _presaleFactory;
        permissionlessDeployEnabled = false;
    }

    function deployVault(
        PresaleUserParams memory presaleParams,
        VaultDeployParams memory vaultDeployParams
    ) public checkDeployAuthority returns (address, address, address) {
        _validateToken1(vaultDeployParams.token1);
        int24 tickSpacing = Utils._validateFeeTier(vaultDeployParams.feeTier);
    
        bytes32 tokenHash = keccak256(abi.encodePacked(vaultDeployParams.name, vaultDeployParams.symbol));
        if (deployedTokenHashes[tokenHash]) revert TokenAlreadyExistsError();

        (MockNomaToken nomaToken, ERC1967Proxy proxy, ) =
        ITokenFactory(tokenFactory())
            .deployNomaToken(vaultDeployParams);
        
        deployedTokenHashes[tokenHash] = true;

        IUniswapV3Pool pool = _deployPool(
            vaultDeployParams.IDOPrice,
            address(proxy), 
            vaultDeployParams.token1,
            vaultDeployParams.feeTier,
            tickSpacing
        );

        DeploymentData memory data;
        data.presaleParams = presaleParams;
        data.vaultDeployParams = vaultDeployParams;
        data.pool = pool;
        data.proxy = proxy;
        data.tickSpacing = tickSpacing;

        return _finalizeVaultDeployment(data);
    }

    function _finalizeVaultDeployment(
        DeploymentData memory data
    ) internal returns (address, address, address) {
        (data.vaultAddress, data.vaultUpgrade) = IEtchVault(
            resolver.requireAndGetAddress(
                Utils.stringToBytes32("EtchVault"), 
                "no EtchVault"
            )
        ).preDeployVault(address(resolver));

        (data.sNoma, data.stakingContract) = IExtFactory(extFactory)
            .deployAll(
                address(this),
                data.vaultAddress,
                address(data.proxy)
            );

        deployer = Deployer(
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

        IVaultUpgrade(data.vaultUpgrade).doUpgradeStart(
            data.vaultAddress, 
            resolver.requireAndGetAddress(
                Utils.stringToBytes32("VaultUpgradeFinalize"), 
                "no vaultUpgradeFinalize"
            )
        );

        IERC20(address(data.proxy)).safeTransfer(address(deployer), data.vaultDeployParams.totalSupply);
        if (IERC20(address(data.proxy)).balanceOf(address(deployer)) != data.vaultDeployParams.totalSupply) revert SupplyTransferError();

        data.presaleContract = _configurePresale(
            address(data.proxy),
            address(deployer),
            data.stakingContract,
            address(data.pool),
            data.vaultAddress,
            data.vaultDeployParams,
            data.presaleParams
        );

        VaultDescription memory vaultDesc = VaultDescription({
            tokenName: data.vaultDeployParams.name,
            tokenSymbol: data.vaultDeployParams.symbol,
            tokenDecimals: data.vaultDeployParams.decimals,
            token0: address(data.proxy),
            token1: data.vaultDeployParams.token1,
            deployer: msg.sender,
            vault: data.vaultAddress,
            presaleContract: data.presaleContract
        });

        vaultsRepository[data.vaultAddress] = vaultDesc;
        _vaults[msg.sender].add(data.vaultAddress);
        deployers.add(msg.sender);
        totalVaults += 1;

        Utils.configureVaultResolver(
            address(resolver),
            data.vaultAddress,
            data.stakingContract,
            data.sNoma,
            data.presaleContract,
            adaptiveSupply(),
            modelHelper(),
            address(deployer)
        );

        return (data.vaultAddress, address(data.pool), address(data.proxy));
    }

    function _configurePresale(
        address proxy,
        address deployer,
        address stakingContract,
        address pool,
        address vaultAddress,
        VaultDeployParams memory vaultDeployParams,
        PresaleUserParams memory presaleParams
    ) internal returns (address) {

        address presaleContract = 
        _deferDeploy(
            address(pool), 
            vaultAddress,
            stakingContract,
            vaultDeployParams, 
            presaleParams
        );

        if (vaultDeployParams.presale == 1) {
            _initializeVault(
                vaultAddress,
                msg.sender,
                deployer, 
                pool, 
                stakingContract,
                presaleContract,
                proxy,
                getProtocolParameters()
            );
        }
        
        return presaleContract;
    }

    function _deferDeploy(
        address pool,
        address vaultAddress,
        address stakingContract,
        VaultDeployParams memory vaultDeployParams,
        PresaleUserParams memory presaleParams
    ) internal returns (address presaleAddress) {
        int24 tickSpacing = Utils._validateFeeTier(vaultDeployParams.feeTier);

        if (vaultDeployParams.presale == 1) {
            
            deferredDeployParams[vaultAddress] = vaultDeployParams;

            presaleAddress = IPresaleFactory(presaleFactory)
            .createPresale(
                PresaleDeployParams({
                    deployer: msg.sender,
                    vaultAddress: vaultAddress,
                    pool: pool,
                    softCap: presaleParams.softCap,
                    initialPrice: vaultDeployParams.IDOPrice + (vaultDeployParams.IDOPrice * getProtocolParameters().presalePremium / 100),
                    deadline: presaleParams.deadline,
                    name: vaultDeployParams.name,
                    symbol: vaultDeployParams.symbol,
                    decimals: vaultDeployParams.decimals,
                    tickSpacing: tickSpacing,
                    floorPercentage: getProtocolParameters().floorPercentage,
                    totalSupply: vaultDeployParams.totalSupply
                }),
                getPresaleProtocolParams()
            );

            return presaleAddress;

        } else {
            _initializeVault(
                vaultAddress,
                msg.sender,
                address(deployer), 
                pool, 
                stakingContract,
                presaleAddress,
                IUniswapV3Pool(pool).token0(),
                getProtocolParameters()
            );
            _deployLiquidity(
                vaultDeployParams.IDOPrice, 
                vaultDeployParams.totalSupply, 
                tickSpacing, 
                getProtocolParameters()
            );
            deployer.finalize();
        }    
    }

    function deferredDeploy(address _deployerContract) public onlyVaults {
        VaultDeployParams memory _params = deferredDeployParams[msg.sender];   

        int24 tickSpacing = Utils._validateFeeTier(_params.feeTier); 

        _deployLiquidity(
            _params.IDOPrice, 
            _params.totalSupply, 
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
        int24 tickSpacing
    ) internal returns (IUniswapV3Pool pool) {
        IUniswapV3Factory factory = IUniswapV3Factory(uniswapV3Factory);
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
        uint256 IDOPrice,
        uint256 totalSupply,
        int24 _tickSpacing,
        ProtocolParameters memory _liquidityParams
    ) internal {
        deployer.deployFloor(IDOPrice, totalSupply * _liquidityParams.floorPercentage / 100, _tickSpacing);  
        deployer.deployAnchor(
            _liquidityParams.floorBips[0], 
            _liquidityParams.floorBips[1], 
            totalSupply * _liquidityParams.anchorPercentage / 100
        );
        deployer.deployDiscovery(IDOPrice * _liquidityParams.idoPriceMultiplier);
    }

    /**
    * @notice Initializes the vault with the provided parameters.
    * @param _vault The address of the vault to initialize.
    * @param _owner The address of the vault owner.
    * @param _deployer The address of the deployer contract.
    * @param _pool The address of the associated Uniswap V3 pool.
    * @param _stakingContract The address of the staking contract.
    * @param _token0 The address of the primary token (token0).
    * @param _params The liquidity structure parameters.
    * @dev This internal function initializes the vault by setting its parameters and linking it with the necessary contracts.
    */
    function _initializeVault(
        address _vault,
        address _owner,
        address _deployer,
        address _pool,
        address _stakingContract,
        address _presaleContract,
        address _token0,
        ProtocolParameters memory _params
    ) internal {
        BaseVault vault = BaseVault(_vault);

        vault.initialize(
            address(this),
            _owner,
            _deployer,
            _pool,
            _stakingContract,
            _token0,
            _presaleContract,
            _params
        );
    }

    /**
    * @notice Mints new tokens to the specified address.
    * @param to The address to receive the minted tokens.
    * @param amount The amount of tokens to mint.
    * @dev This function can only be called by authorized vaults.
    */
    function mintTokens(address to, uint256 amount) public onlyVaults {
        IERC20Extended(vaultsRepository[msg.sender].token0).mint(to, amount);
    }

    /**
    * @notice Burns tokens from the specified address.
    * @param from The address from which to burn tokens.
    * @param amount The amount of tokens to burn.
    * @dev This function can only be called by authorized vaults.
    */
    function burnFor(address from, uint256 amount) public onlyVaults {
        IERC20Extended(vaultsRepository[msg.sender].token0).burn(from, amount);
    }

    /**
    * @notice Sets the parameters for the liquidity structure.
    * @param _params The new liquidity structure parameters.
    * @dev This function can only be called by the authority.
    */
    function setProtocolParameters( //TODO check this
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
    * @notice Retrieves the description of a vault deployed by a specific deployer.
    * @param _deployer The address of the deployer.
    * @return The vault description associated with the deployer.
    */
    function getVaultDescription(address _deployer) external view returns (VaultDescription memory) {
        return vaultsRepository[_deployer];
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
    * @notice Retrieves the total number of vaults deployed.
    * @return result The total number of vaults.
    */
    function numVaults() public view returns (uint256 result) {
        address[] memory _deployers = getDeployers();
        for (uint256 i = 0; i < _deployers.length; i++) {
            result += numVaults(_deployers[i]);
        }
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

    function teamMultiSig() public view returns (address) {
        return teamMultisigAddress;
    }

    /**
     * @notice Modifier to check if the caller has the authority to deploy.
     * @dev Reverts with NotAuthorityError if the caller lacks deployment authority.
     */
    modifier checkDeployAuthority() {
        if (!permissionlessDeployEnabled) {
            if (msg.sender != authority) revert NotAuthorityError();
        }
        _;
    }

    /**
     * @notice Modifier to ensure that the caller is the designated authority.
     * @dev Reverts with NotAuthorityError if the caller is not the authority.
     */
    modifier isAuthority() {
        if (msg.sender != authority) revert NotAuthorityError();
        _;
    }

    /**
     * @notice Modifier to restrict function access to authorized vaults.
     * @dev Reverts with OnlyVaultsError if the caller is not an authorized vault.
     */
    modifier onlyVaults() {
        if (vaultsRepository[msg.sender].vault != msg.sender) revert OnlyVaultsError();
        _;
    }
}
