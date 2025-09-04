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

import {Utils} from "../libraries/Utils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface INomaFactory {
    function deferredDeploy(address deployer) external;
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

// Custom errors
error AlreadyInitialized();
error InvalidPosition();
error OnlyFactory();
error OnlyDeployer();
error OnlyInternalCalls();
error CallbackCaller();
error ResolverNotSet();
error Locked();

/**
 * @title BaseVault
 * @notice A base contract for managing a vault's liquidity positions and interactions with Uniswap V3.
 * @dev This contract handles initialization, fee management, and interactions with the Uniswap V3 pool.
 */
contract BaseVault  {
    VaultStorage internal _v;

    // Events
    event FloorUpdated(uint256 floorPrice, uint256 floorCapacity);

    /**
     * @notice Uniswap V3 callback function, called back on pool.mint.
     * @param amount0Owed The amount of token0 owed to the pool.
     * @param amount1Owed The amount of token1 owed to the pool.
     * @param data Additional data passed to the callback.
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

    /**
     * @notice Initializes the vault with the necessary parameters.
     * @param _factory The address of the factory contract.
     * @param _owner The address of the vault owner.
     * @param _deployer The address of the deployer contract.
     * @param _pool The address of the Uniswap V3 pool.
     * @param _stakingContract The address of the staking contract.
     * @param _params The protocol parameters.
     */
    function initialize(
        address _factory,
        address _owner,
        address _deployer,
        address _pool, 
        address _stakingContract,
        address _presaleContract,
        address _tokenRepo,
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
        _v.stakingEnabled = true;
        _v.timeLastMinted = 0;
        _v.loanFee = uint8(_params.loanFee);
        _v.totalInterest = 0;
        _v.stakingContract = _stakingContract;
        _v.presaleContract = _presaleContract;
        _v.collateralAmount = 0;
        _v.tokenRepo = _tokenRepo;
        _v.deployerContract = _deployer;
        _v.modelHelper = modelHelper();
        _v.protocolParameters = _params;
        _v.manager = _owner;
        _v.isLocked[address(this)] = false;
        IERC20(_v.pool.token0()).approve(_deployer, type(uint256).max);
    }
    
    // *** MUTATIVE FUNCTIONS *** //

    /**
     * @notice Initializes the liquidity positions for the vault.
     * @param positions An array of liquidity positions (Floor, Anchor, Discovery).
     */
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

    /**
     * @notice Sets the accumulated fees for token0 and token1.
     * @param _feesAccumulatedToken0 The accumulated fees for token0.
     * @param _feesAccumulatedToken1 The accumulated fees for token1.
     */
    function setFees(
        uint256 _feesAccumulatedToken0, 
        uint256 _feesAccumulatedToken1
    ) public onlyInternalCalls {
        _v.feesAccumulatorToken0 += _feesAccumulatedToken0;
        _v.feesAccumulatorToken1 += _feesAccumulatedToken1;
    }

    // *** VIEW FUNCTIONS *** //

    /**
     * @notice Retrieves the underlying balances for a specific liquidity type.
     * @param liquidityType The type of liquidity position (Floor, Anchor, Discovery).
     * @return lowerTick The lower tick of the position.
     * @return upperTick The upper tick of the position.
     * @return amount0Current The amount of token0 in the position.
     * @return amount1Current The amount of token1 in the position.
     */
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

    /**
     * @notice Retrieves the vault's information.
     * @return vaultInfo The vault's information.
     */
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

        vaultInfo.totalInterest = _v.totalInterest;
    }

    /**
     * @notice Retrieves the excess reserve balance of token1.
     * @return The excess reserve balance of token1.
     */
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

    /**
     * @notice Retrieves the protocol addresses.
     * @return The protocol addresses.
     */
    function getProtocolAddresses() public view returns (ProtocolAddresses memory) {
        return ProtocolAddresses({
            pool: address(_v.pool),
            vault: address(this),
            deployer: _v.deployerContract,
            modelHelper: modelHelper(),
            presaleContract: _v.presaleContract,
            adaptiveSupplyController: adaptiveSupply()
        });
    }

    // *** ADDRESS RESOLVER *** //

    /**
     * @notice Retrieves the address resolver.
     * @return resolver The address resolver.
     */
    function _getResolver() internal view returns (IAddressResolver resolver) {
        resolver = _v.resolver;
        if (address(resolver) == address(0)) {
            // Fallback to Diamond storage
            LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
            resolver = IAddressResolver(ds.resolver);
        }
    }

    /**
     * @notice Retrieves the address of the adaptive supply controller.
     * @return The address of the adaptive supply controller.
     */
    function adaptiveSupply() public view returns (address) {
        IAddressResolver resolver = _getResolver();
        address _adaptiveSupply = resolver.getVaultAddress(address(this), Utils.stringToBytes32("AdaptiveSupply"));
        if (_adaptiveSupply == address(0)) {
            _adaptiveSupply = resolver
                .requireAndGetAddress(
                    Utils.stringToBytes32("AdaptiveSupply"), 
                    "no AdaptiveSupply"
                );
        }
        return _adaptiveSupply;
    }

    /**
     * @notice Retrieves the address of the model helper.
     * @return The address of the model helper.
     */
    function modelHelper() public view returns (address) {
        IAddressResolver resolver = _getResolver();
        address _modelHelper = resolver.getVaultAddress(address(this), Utils.stringToBytes32("ModelHelper"));
        if (_modelHelper == address(0)) {
            _modelHelper = resolver
                .requireAndGetAddress(
                    Utils.stringToBytes32("ModelHelper"), 
                    "no ModelHelper"
                );
        }
        return _modelHelper;
    }

    function factory() public view returns (address) {
        IAddressResolver resolver = _getResolver();
        address _factory = resolver.getVaultAddress(address(this), Utils.stringToBytes32("NomaFactory"));
        if (_factory == address(0)) {
            _factory = resolver
                .requireAndGetAddress(
                    Utils.stringToBytes32("NomaFactory"), 
                    "no Factory"
                );
        }
        return _factory;
    }
    // *** MODIFIERS *** //

    /**
     * @notice Modifier to restrict access to the deployer contract.
     */
    modifier onlyDeployer() {
        if (msg.sender != _v.deployerContract) revert OnlyDeployer();
        _;
    }

    /**
     * @notice Modifier to restrict access to internal calls.
     */
    modifier onlyInternalCalls() {
        if (msg.sender != _v.factory && msg.sender != address(this)) revert OnlyInternalCalls();
        _;        
    }

    /**
     * @notice Modifier to restrict access to the factory contract.
     */
    modifier onlyFactory() {
        if (msg.sender != factory()) revert OnlyFactory();
        _;
    }

    // *** FUNCTION SELECTORS *** //
    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
    function getFunctionSelectors() external pure virtual returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = bytes4(keccak256(bytes("getVaultInfo()")));
        selectors[1] = bytes4(keccak256(bytes("initialize(address,address,address,address,address,address,address,(uint8,uint8,uint8,uint16[2],uint256,uint256,int24,int24,int24,uint256,uint256,uint256,uint256,uint256,uint256,uint256))")));
        selectors[2] = bytes4(keccak256(bytes("initializeLiquidity((int24,int24,uint128,uint256,int24)[3])")));
        selectors[3] = bytes4(keccak256(bytes("uniswapV3MintCallback(uint256,uint256,bytes)")));
        selectors[4] = bytes4(keccak256(bytes("getUnderlyingBalances(uint8)")));
        selectors[5] = bytes4(keccak256(bytes("getExcessReserveToken1()")));
        selectors[6] = bytes4(keccak256(bytes("getProtocolAddresses()")));
        selectors[7] = bytes4(keccak256(bytes("setFees(uint256,uint256)")));
        return selectors;
    }
}