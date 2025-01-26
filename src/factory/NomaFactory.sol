// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import { VaultDescription } from "../types/Types.sol";

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
    LiquidityStructureParameters
} from "../types/Types.sol";

/**
 * @title IVaultUpgrade
 * @notice Interface for initiating and finalizing vault upgrades.
 */
interface IVaultUpgrade {
    /**
     * @notice Initiates the upgrade process for a vault.
     * @param diamond The address of the diamond contract to be upgraded.
     * @param _vaultUpgradeFinalize The address of the contract responsible for finalizing the upgrade.
     */
    function doUpgradeStart(address diamond, address _vaultUpgradeFinalize) external;

    /**
     * @notice Finalizes the upgrade process for a vault.
     * @param diamond The address of the diamond contract that has been upgraded.
     */
    function doUpgradeFinalize(address diamond) external;
}

/**
 * @title IEtchVault
 * @notice Interface for pre-deploying a vault.
 */
interface IEtchVault {
    /**
     * @notice Pre-deploys a vault using the provided resolver.
     * @param _resolver The address of the resolver contract.
     * @return vaultAddress The address of the pre-deployed vault.
     * @return vaultUpgrade The address of the associated vault upgrade contract.
     */
    function preDeployVault(address _resolver) external returns (address vaultAddress, address vaultUpgrade);
}

/**
 * @title IExtFactory
 * @notice Interface for deploying auxiliary contracts related to a vault.
 */
interface IExtFactory {
    /**
     * @notice Deploys all necessary auxiliary contracts for a vault.
     * @param deployerAddress The address of the deployer initiating the process.
     * @param vaultAddress The address of the vault for which auxiliary contracts are being deployed.
     * @param token0 The address of the primary token associated with the vault.
     * @return auxiliaryContract1 The address of the first auxiliary contract deployed.
     * @return auxiliaryContract2 The address of the second auxiliary contract deployed.
     */
    function deployAll(
        address deployerAddress,
        address vaultAddress,
        address token0
    ) external returns (address auxiliaryContract1, address auxiliaryContract2);
}

/**
 * @title IDeployerFactory
 * @notice Interface for deploying a Deployer contract.
 */
interface IDeployerFactory {
    /**
     * @notice Deploys a new Deployer contract.
     * @param owner The address designated as the owner of the new Deployer contract.
     * @param resolver The address of the resolver contract to be associated with the Deployer.
     * @return deployer The address of the newly deployed Deployer contract.
     */
    function deployDeployer(address owner, address resolver) external returns (address deployer);
}

/**
 * @title IERC20
 * @notice Interface for the ERC20 standard token, including a mint function.
 */
interface IERC20 {
    /**
     * @notice Mints new tokens to a specified address.
     * @param to The address to receive the newly minted tokens.
     * @param amount The amount of tokens to be minted.
     */
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/**
 * @dev Thrown when a function is called by an address that is not recognized as an authorized vault.
 */
error OnlyVaultsError();

/**
 * @dev Thrown when a function is called by an address that does not have the required authority.
 */
error NotAuthorityError();

/**
 * @dev Thrown when the deployment of a token contract fails.
 */
error TokenDeployFailedError();

/**
 * @dev Thrown when an invalid token address is encountered, such as when the token address is greater than or equal to the paired token address.
 */
error InvalidTokenAddressError();

/**
 * @dev Thrown when the transfer of the total supply to the deployer contract fails.
 */
error SupplyTransferError();

/**
 * @dev Thrown when attempting to deploy a token that has already been deployed.
 */
error TokenAlreadyExistsError();

/**
 * @dev Thrown when an operation is attempted that requires only one vault, but multiple vaults are present.
 */
error OnlyOneVaultError();

/**
 * @dev Thrown when a token's symbol is invalid, such as being empty or not recognized.
 */
error InvalidSymbol();

/**
 * @title NomaFactory
 * @notice This contract facilitates the deployment and management of Noma Vaults, including associated tokens and liquidity pools.
 */
contract NomaFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Noma Factory state
    IAddressResolver resolver;
    Deployer deployer;

    address deploymentFactory;
    address extFactory;
    address authority;
    address uniswapV3Factory;

    uint256 totalVaults;
    
    bool permissionlessDeployEnabled;    

    LiquidityStructureParameters liquidityStructureParameters;

    EnumerableSet.AddressSet deployers; 

    mapping(address => EnumerableSet.AddressSet) _vaults;
    mapping(address => VaultDescription) vaultsRepository;
    mapping(bytes32 => bool) deployedTokenHashes;

    /**
     * @notice Constructor to initialize the NomaFactory contract.
     * @param _uniswapV3Factory The address of the Uniswap V3 Factory contract.
     * @param _resolver The address of the Address Resolver contract.
     * @param _deploymentFactory The address of the Deployment Factory contract.
     * @param _extFactory The address of the External Factory contract.
     * @param _permissionlessDeployEnabled Boolean flag to enable or disable permissionless deployment.
     */
    constructor(
        address _uniswapV3Factory,
        address _resolver,
        address _deploymentFactory,
        address _extFactory,
        bool _permissionlessDeployEnabled
    ) {
        authority = msg.sender;
        uniswapV3Factory = _uniswapV3Factory;
        resolver = IAddressResolver(_resolver);
        deploymentFactory = _deploymentFactory;
        extFactory = _extFactory;
        permissionlessDeployEnabled = false;
    }

    /**
    * @notice Deploys a new vault with the specified parameters.
    * @param _params The parameters required for vault deployment.
    * @return vaultAddress The address of the newly deployed vault.
    * @return poolAddress The address of the associated Uniswap V3 pool.
    * @return nomaTokenAddress The address of the deployed Noma token.
    * @dev This function validates the provided token, deploys a new Noma token, creates a Uniswap V3 pool, and initializes the vault.
    * It also handles the deployment of liquidity and finalizes the deployment process.
    * Access control: Deployment authority is required unless permissionless deployment is enabled.
    */
    function deployVault(
        VaultDeployParams memory _params
    ) external checkDeployAuthority returns (address vaultAddress, address poolAddress, address nomaTokenAddress) {
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
            resolver.requireAndGetAddress(
                Utils.stringToBytes32("EtchVault"), 
                "no EtchVault"
            )
        ).preDeployVault(address(resolver));

        (, address stakingContract) = IExtFactory(extFactory)
        .deployAll(
            address(this),
            vaultAddress,
            address(nomaToken)
        );

        deployer = Deployer(
            IDeployerFactory(deploymentFactory)
            .deployDeployer(
                address(this), 
                address(resolver)
            )
        );

        deployer.initialize(
            address(this), 
            vaultAddress, 
            address(pool), 
            modelHelper()
        );
        
        IVaultUpgrade(vaultUpgrade).doUpgradeStart(
            vaultAddress, 
            resolver
            .requireAndGetAddress(
                Utils.stringToBytes32("VaultUpgradeFinalize"), 
                "no vaultUpgradeFinalize"
            )
        );

        _initializeVault(
            vaultAddress,
            msg.sender,
            address(deployer), 
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

        IERC20Metadata(address(nomaToken)).transfer(address(deployer), _params._totalSupply);

        if (nomaToken.balanceOf(address(deployer)) != _params._totalSupply) revert SupplyTransferError();

        _deployLiquidity(_params._IDOPrice, _params._totalSupply, getLiquidityStructureParameters());

        bytes32 name = Utils.stringToBytes32("AdaptiveSupply");
        bytes32[] memory names = new bytes32[](1);
        names[0] = name;

        address _adaptiveSupply = adaptiveSupply();
        address[] memory destinations  = new address[](1);
        destinations[0] = _adaptiveSupply;

        resolver.configureDeployerACL(vaultAddress);  
        resolver.importVaultAddress(vaultAddress, names, destinations);
        deployer.finalize();

        vaultsRepository[vaultAddress] = vaultDesc;
        _vaults[msg.sender].add(vaultAddress);
        deployers.add(msg.sender);
        totalVaults += 1;

        return (vaultAddress, address(pool), address(nomaToken));
    }

    /**
    * @notice Deploys a new Noma token with the specified parameters.
    * @param _name The name of the token.
    * @param _symbol The symbol of the token.
    * @param _token1 The address of the paired token (token1).
    * @param _totalSupply The total supply of the token.
    * @return nomaToken The address of the newly deployed MockNomaToken.
    * @dev This internal function ensures the token does not already exist, generates a unique address using a salt, and initializes the token.
    * It reverts if the token address is invalid or if the token already exists.
    */
    function _deployNomaToken(
        string memory _name,
        string memory _symbol,
        address _token1,
        uint256 _totalSupply
    ) internal returns (MockNomaToken nomaToken) {
        bytes32 tokenHash = keccak256(abi.encodePacked(_name, _symbol));

        if (deployedTokenHashes[tokenHash]) revert TokenAlreadyExistsError();

        deployedTokenHashes[tokenHash] = true;
        uint256 nonce = uint256(tokenHash);

        MockNomaToken _nomaToken;
        do {
            _nomaToken = new MockNomaToken{salt: bytes32(nonce)}();
            nonce++;
        } while (address(_nomaToken) >= _token1);

        _nomaToken.initialize(authority, _totalSupply, _name, _symbol, address(resolver));

        if (address(_nomaToken) >= _token1) revert InvalidTokenAddressError();

        return _nomaToken;
    }

    /**
    * @notice Deploys a Uniswap V3 pool for the given token pair and initializes it with the specified price.
    * @param _initPrice The initial price of the pool.
    * @param token0 The address of the first token.
    * @param token1 The address of the second token.
    * @return pool The address of the deployed Uniswap V3 pool.
    * @dev This internal function checks if the pool already exists; if not, it creates a new pool and initializes it with the provided price.
    */
    function _deployPool(
        uint256 _initPrice,
        address token0,
        address token1
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
    * @notice Initializes the vault with the provided parameters.
    * @param _vault The address of the vault to initialize.
    * @param _owner The address of the vault owner.
    * @param _deployer The address of the deployer contract.
    * @param _pool The address of the associated Uniswap V3 pool.
    * @param _modelHelper The address of the model helper contract.
    * @param _stakingContract The address of the staking contract.
    * @param _token0 The address of the primary token (token0).
    * @param _adaptiveSupply The address of the adaptive supply contract.
    * @param _params The liquidity structure parameters.
    * @dev This internal function initializes the vault by setting its parameters and linking it with the necessary contracts.
    */
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

    /**
    * @notice Deploys liquidity for the vault based on the provided parameters.
    * @param _IDOPrice The initial DEX offering price.
    * @param _totalSupply The total supply of the token.
    * @param _liquidityParams The parameters defining the liquidity structure.
    * @dev This internal function deploys floor, anchor, and discovery liquidity using the deployer contract.
    */
    function _deployLiquidity(
        uint256 _IDOPrice,
        uint256 _totalSupply,
        LiquidityStructureParameters memory _liquidityParams
    ) internal {
        deployer.deployFloor(_IDOPrice, _totalSupply * _liquidityParams.floorPercentage / 100);  
        deployer.deployAnchor(
            _liquidityParams.floorBips[0], 
            _liquidityParams.floorBips[1], 
            _totalSupply * _liquidityParams.anchorPercentage / 100
        );
        deployer.deployDiscovery(_IDOPrice * _liquidityParams.idoPriceMultiplier);
    }

    /**
    * @notice Mints new tokens to the specified address.
    * @param to The address to receive the minted tokens.
    * @param amount The amount of tokens to mint.
    * @dev This function can only be called by authorized vaults.
    */
    function mintTokens(address to, uint256 amount) public onlyVaults {
        IERC20(vaultsRepository[msg.sender].token0).mint(to, amount);
    }

    /**
    * @notice Burns tokens from the specified address.
    * @param from The address from which to burn tokens.
    * @param amount The amount of tokens to burn.
    * @dev This function can only be called by authorized vaults.
    */
    function burnFor(address from, uint256 amount) public onlyVaults {
        IERC20(vaultsRepository[msg.sender].token0).burn(from, amount);
    }

    /**
    * @notice Sets the parameters for the liquidity structure.
    * @param _params The new liquidity structure parameters.
    * @dev This function can only be called by the authority.
    */
    function setLiquidityStructureParameters(
        LiquidityStructureParameters memory _params
    ) public isAuthority {
        liquidityStructureParameters = _params;
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
    function getLiquidityStructureParameters() public view returns 
    (LiquidityStructureParameters memory) {
        return liquidityStructureParameters;
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
