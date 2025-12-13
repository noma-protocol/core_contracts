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
// Contract: BaseVault.sol
// Author: 0xsufi@noma.money
// Copyright Noma Protocol 2024/2026

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {VaultStorage} from "../libraries/LibAppStorage.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IAddressResolver} from "../interfaces/IAddressResolver.sol";
import {
    VaultDescription,
    LiquidityPosition, 
    LiquidityType,
    VaultInfo,
    ProtocolAddresses,
    ProtocolParameters,
    PostInitParams
} from "../types/Types.sol";

import {Utils} from "../libraries/Utils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface INomaFactory {
    function deferredDeploy(address deployer) external;
    function mintTokens(address to, uint256 amount) external;
    function burnFor(address from, uint256 amount) external;
    function teamMultiSig() external view returns (address);
    function getVaultsRepository(address vault) external view returns (VaultDescription memory);
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
error NotInitialized();

/**
 * @title BaseVault
 * @notice A base contract for managing a vault's liquidity positions and interactions with Uniswap V3.
 * @dev This contract handles initialization, fee management, and interactions with the Uniswap V3 pool.
 */
contract BaseVault  {
    VaultStorage internal _v;
    
    function _handleV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed
    ) internal {
        if (msg.sender != address(_v.pool)) revert CallbackCaller();

        if (amount0Owed > 0) {
            uint256 balance0 = IERC20(_v.tokenInfo.token0).balanceOf(address(this));
            if (balance0 < amount0Owed) {
                INomaFactory(factory()).mintTokens(address(this), amount0Owed);
            }
            IERC20(_v.tokenInfo.token0).transfer(msg.sender, amount0Owed);
        }

        if (amount1Owed > 0) {
            IERC20(_v.tokenInfo.token1).transfer(msg.sender, amount1Owed);
        }
    }

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
    ) external {
        _handleV3MintCallback(amount0Owed, amount1Owed);
    }

    /**
     * @notice Pancake V3 callback function, called back on pool.mint.
     * @param amount0Owed The amount of token0 owed to the pool.
     * @param amount1Owed The amount of token1 owed to the pool.
     * @param data Additional data passed to the callback.
     */
    function pancakeV3MintCallback(
        uint256 amount0Owed, 
        uint256 amount1Owed, 
        bytes calldata data
    ) external {
        _handleV3MintCallback(amount0Owed, amount1Owed);
    }

    /**
     * @notice Initializes the vault with the necessary parameters.
     * @param _factory The address of the factory contract.
     * @param _owner The address of the vault owner.
     * @param _deployer The address of the deployer contract.
     * @param _pool The address of the Uniswap V3 pool.
     * @param _params The protocol parameters.
     */
    function initialize(
        address _factory,
        address _owner,
        address _deployer,
        address _pool, 
        address _presaleContract,
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
        _v.tickSpacing = _v.pool.tickSpacing();
        _v.initialized = false; 
        _v.stakingEnabled = false;
        _v.isAdvancedConfEnabled = false; 
        _v.timeLastMinted = 0;
        _v.loanFee = uint8(_params.loanFee);
        _v.totalInterest = 0;
        _v.presaleContract = _presaleContract;
        _v.collateralAmount = 0;
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
                
        _v.floorPosition = positions[0];
        _v.anchorPosition = positions[1];
        _v.discoveryPosition = positions[2];
    }

    function postInit(
        PostInitParams memory params
    ) public onlyFactory {
        if (_v.initialized) {
            revert AlreadyInitialized();
        }
        _v.stakingContract = params.stakingContract;
        _v.tokenRepo = params.tokenRepo;
        _v.sToken = params.sToken;
        _v.vNOMAContract = params.vToken;
        _v.stakingEnabled = true;
        _v.isStakingSetup = true;
        _v.initialized = true;
    }

    /**
     * @notice Handles the post-presale actions.
     */
    function afterPresale() public  {
        if (msg.sender != _v.presaleContract) revert OnlyInternalCalls();
        INomaFactory(
            _v.factory
        ).deferredDeploy(
            INomaFactory(_v.factory)
            .getVaultsRepository(address(this)).deployerContract
        );
    }

    // *** VIEW FUNCTIONS *** //

    /**
     * @notice Retrieves the current liquidity positions.
     * @return positions The current liquidity positions.
     */
    function getPositions() public view
    returns (LiquidityPosition[3] memory positions) {
        positions = [
            _v.floorPosition, 
            _v.anchorPosition, 
            _v.discoveryPosition
        ];
    }

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
        vaultInfo.initialized = _v.initialized;
        vaultInfo.stakingContract = _v.stakingContract;
        vaultInfo.sToken = _v.sToken;
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
            adaptiveSupplyController: adaptiveSupply(),
            exchangeHelper: exchangeHelper()
        });
    }

    /**
     * @notice Retrieves the protocol parameters.
     * @return The protocol parameters.
     */
    function getProtocolParameters() public view returns 
    (ProtocolParameters memory ) {
        return _v.protocolParameters;
    }

    /*-------------------------------------- USED BY MODEL HELPER --------------------------------------*/

    /**
     * @notice Retrieves the staking contract address.
     * @return The address of the staking contract.
     */
    function getStakingContract() external virtual view returns (address) {
        return _v.stakingContract;
    }

    /**
     * @notice Retrieves the total collateral amount.
     * @return The total collateral amount.
     */
    function getCollateralAmount() public view returns (uint256) {
        return _v.collateralAmount;

    }
    /*-------------------------------------- USED BY MODEL HELPER --------------------------------------*/

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

    function exchangeHelper() public view returns (address) {
        IAddressResolver resolver = _getResolver();
        address _exchangeHelper = resolver.getVaultAddress(address(this), Utils.stringToBytes32("ExchangeHelper"));
        if (_exchangeHelper == address(0)) {
            _exchangeHelper = resolver
                .requireAndGetAddress(
                    Utils.stringToBytes32("ExchangeHelper"), 
                    "no ExchangeHelper"
                );
        }
        return _exchangeHelper;
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
        if (
            msg.sender != _v.factory && 
            msg.sender != address(this) &&
            msg.sender !=  _v.orchestrator
        ) revert OnlyInternalCalls();

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
        bytes4[] memory selectors = new bytes4[](15);
        selectors[0] = bytes4(keccak256(bytes("getVaultInfo()")));
        selectors[1] = bytes4(keccak256(
            bytes(
                "initialize(address,address,address,address,address,(uint8,uint8,uint8,uint16[2],uint256,uint256,int24,int24,int24,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,(uint8,uint8),uint256))"
            )
        ));
        selectors[2] = bytes4(
            keccak256(
                bytes("initializeLiquidity((int24,int24,uint128,uint256,int24,uint8)[3])")
            )
        );      
        selectors[3] = bytes4(keccak256(bytes("uniswapV3MintCallback(uint256,uint256,bytes)")));
        selectors[4] = bytes4(keccak256(bytes("getUnderlyingBalances(uint8)")));
        selectors[5] = bytes4(keccak256(bytes("getExcessReserveToken1()")));
        selectors[6] = bytes4(keccak256(bytes("getProtocolAddresses()")));
        selectors[7] = bytes4(keccak256(bytes("pancakeV3MintCallback(uint256,uint256,bytes)")));
        selectors[8] = bytes4(keccak256(bytes("getPositions()")));
        selectors[9] = bytes4(keccak256(bytes("getProtocolParameters()")));  
        selectors[10] = bytes4(keccak256(bytes("afterPresale()")));
        selectors[11] = bytes4(keccak256(bytes("postInit((address,address,address,address))")));
        selectors[12] = bytes4(keccak256(bytes("getStakingContract()")));
        selectors[13] = bytes4(keccak256(bytes("getCollateralAmount()")));
        // selectors[14] = bytes4(keccak256(bytes("uniswapV3SwapCallback(int256,int256,bytes)")));

        return selectors;
    }
}