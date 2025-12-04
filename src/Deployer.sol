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
// Author: 0xsufi@noma.money
// Copyright Noma Protocol 2025/2026

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LiquidityDeployer} from "./libraries/LiquidityDeployer.sol";
// import {DeployHelper} from "./libraries/DeployHelper.sol";
import {
    AmountsToMint, 
    LiquidityPosition, 
    LiquidityType, 
    DeployLiquidityParams
} from "./types/Types.sol";
import {IAddressResolver} from "./interfaces/IAddressResolver.sol";
import {Utils} from "./libraries/Utils.sol";

/// @title IVault Interface
/// @notice Interface defining the functionality of the Vault contract.
/// @dev Used for initializing liquidity after the deployment process.
interface IVault {
    /**
     * @notice Initializes liquidity in the Vault with predefined positions.
     * @param positions An array of three liquidity positions (floor, anchor, discovery).
     */
    function initializeLiquidity(
        LiquidityPosition[3] memory positions
    ) external;
}

/// @title Liquidity Deployment Contract
/// @notice This contract manages the deployment of liquidity positions, including floor, anchor, and discovery positions.
/// @dev Integrates with Uniswap V3 for liquidity management and includes safety mechanisms like reentrancy protection.
contract Deployer is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Stores the floor liquidity position details.
    LiquidityPosition private floorPosition;

    /// @notice Stores the anchor liquidity position details.
    LiquidityPosition private anchorPosition;

    /// @notice Stores the discovery liquidity position details.
    LiquidityPosition private discoveryPosition;

    /// @notice Address of the vault contract.
    address private vault;

    /// @notice Address of token0 in the Uniswap V3 pool.
    address private token0;

    /// @notice Address of token1 in the Uniswap V3 pool.
    address private token1;

    /// @notice Address of the model helper contract.
    address private modelHelper;

    /// @notice Address of the factory contract.
    address private factory;

    /// @notice Address of the address resolver contract.
    address private immutable resolver;

    /// @notice Lock state for reentrancy protection.
    bool private locked;

    /// @notice Initialization state to prevent reinitialization.
    bool private initialized;

    /// @notice The Uniswap V3 pool instance.
    IUniswapV3Pool public pool;

    /// @dev Event emitted when a floor position is deployed.
    event FloorDeployed(LiquidityPosition position);

    /// @dev Event emitted when an anchor position is deployed.
    event AnchorDeployed(LiquidityPosition position);

    /// @dev Event emitted when a discovery position is deployed.
    event DiscoveryDeployed(LiquidityPosition position);

    /// @dev Error thrown when a function is called by an unauthorized address.
    error OnlyFactoryAllowed();

    /// @dev Error thrown when the deployment is incomplete.
    error NotDeployed();

    /// @dev Error thrown when a function is called while locked.
    error Locked();

    /// @dev Error thrown when a callback is made by an unauthorized address.
    error CallBackCaller();

    /// @dev Error thrown when the contract is already initialized.
    error AlreadyInitialized();

    /// @dev Error thrown when the contract is not deployed.
    event Initialized();

    /// @notice Initializes the contract with the owner and resolver addresses.
    /// @param _ownerAddress Address of the contract owner.
    /// @param _resolver Address of the address resolver.
    constructor(address _ownerAddress, address _resolver) Ownable(_ownerAddress) {
        if (_resolver == address(0)) revert NotDeployed();
        resolver = _resolver;
    }

    /// @notice Initializes the contract state
    /// @dev This function is protected by a lock modifier to prevent reentrancy.
    /// @param _factory Address of the factory.
    /// @param _vault Address of the vault.
    /// @param _pool Address of the Uniswap V3 pool.
    /// @param _modelHelper Address of the model helper contract.
    function initialize(
        address _factory,
        address _vault,
        address _pool,
        address _modelHelper
    ) public onlyOwner notInitialized() {
        if (
            _factory == address(0)    || 
            _vault == address(0)      || 
            _pool == address(0)       || 
            _modelHelper == address(0)
            ) {
            revert NotDeployed();
        }
        factory = _factory;
        pool = IUniswapV3Pool(_pool);
        vault = _vault;
        token0 = pool.token0();
        token1 = pool.token1();


        modelHelper = _modelHelper;
        initialized = true;
        emit Initialized();
    }

    /// @notice Callback function called by Uniswap V3 during mint operations.
    /// @dev Transfers owed amounts of token0 and token1 to the pool.
    /// @param amount0Owed Amount of token0 owed to the pool.
    /// @param amount1Owed Amount of token1 owed to the pool.
    /// @param data Additional callback data.
    function uniswapV3MintCallback(
        uint256 amount0Owed, 
        uint256 amount1Owed, 
        bytes calldata data
    ) external {
        if (msg.sender != address(pool)) revert CallBackCaller();

        uint256 token0Balance = IERC20(token0).balanceOf(address(this));
        uint256 token1Balance = IERC20(token1).balanceOf(address(this));

        if (token0Balance >= amount0Owed) {
            if (amount0Owed > 0) IERC20(token0).safeTransfer(msg.sender, amount0Owed);
        } else {
            IERC20(token0).safeTransferFrom(vault, address(this), amount0Owed);
            IERC20(token0).safeTransfer(msg.sender, amount0Owed);
        }

        if (token1Balance >= amount1Owed) {
            if (amount1Owed > 0) IERC20(token1).safeTransfer(msg.sender, amount1Owed);
        } else {
            IERC20(token1).safeTransferFrom(vault, address(this), amount1Owed);
            IERC20(token1).safeTransfer(msg.sender, amount1Owed);
        }
    }

    /// @notice Callback function called by Uniswap V3 during mint operations.
    /// @dev Transfers owed amounts of token0 and token1 to the pool.
    /// @param amount0Owed Amount of token0 owed to the pool.
    /// @param amount1Owed Amount of token1 owed to the pool.
    /// @param data Additional callback data.
    function pancakeV3MintCallback(
        uint256 amount0Owed, 
        uint256 amount1Owed, 
        bytes calldata data
    ) external {
        if (msg.sender != address(pool)) revert CallBackCaller();

        uint256 token0Balance = IERC20(token0).balanceOf(address(this));
        uint256 token1Balance = IERC20(token1).balanceOf(address(this));

        if (token0Balance >= amount0Owed) {
            if (amount0Owed > 0) IERC20(token0).safeTransfer(msg.sender, amount0Owed);
        } else {
            IERC20(token0).safeTransferFrom(vault, address(this), amount0Owed);
            IERC20(token0).safeTransfer(msg.sender, amount0Owed);
        }

        if (token1Balance >= amount1Owed) {
            if (amount1Owed > 0) IERC20(token1).safeTransfer(msg.sender, amount1Owed);
        } else {
            IERC20(token1).safeTransferFrom(vault, address(this), amount1Owed);
            IERC20(token1).safeTransfer(msg.sender, amount1Owed);
        }
    }

    /// @notice Deploys a floor liquidity position.
    /// @param _floorPrice The target floor price.
    /// @param _amount0 The amount of token0 to allocate.
    function deployFloor(uint256 _floorPrice, uint256 _amount0, int24 tickSpacing) public onlyFactory {
        (LiquidityPosition memory newPosition ) = LiquidityDeployer.deployFloor(
            address(pool), 
            vault, 
            _floorPrice,
            _amount0,
            0,
            tickSpacing
        );

        floorPosition = newPosition;
        emit FloorDeployed(newPosition);
    }

    /// @notice Deploys an anchor liquidity position.
    /// @param _bipsWidth Width of the position in basis points.
    /// @param _amount0 Amount of token0 to allocate.
    function deployAnchor(uint256 _bipsWidth, uint256 _amount0) public onlyFactory {
        (LiquidityPosition memory newPosition,) = LiquidityDeployer
        .deployAnchor(
            floorPosition,
            DeployLiquidityParams({
                pool: address(pool),
                receiver: vault,
                bips: _bipsWidth,
                lowerTick: 0,
                upperTick: 0,
                tickSpacing: floorPosition.tickSpacing,
                liquidityType: LiquidityType.Anchor,
                amounts: AmountsToMint({
                    amount0: _amount0,
                    amount1: 0
                })
            })
        );

        anchorPosition = newPosition;
        emit AnchorDeployed(newPosition);
    }

    /// @notice Deploys a discovery liquidity position.
    /// @param _upperDiscoveryPrice The upper discovery price.
    /// @return newPosition The deployed liquidity position.
    /// @return liquidityType The type of liquidity deployed.
    function deployDiscovery(uint256 _upperDiscoveryPrice) public onlyFactory returns (
        LiquidityPosition memory newPosition, 
        LiquidityType liquidityType
    ) {
        (newPosition,) = LiquidityDeployer.deployDiscovery(
            _upperDiscoveryPrice, 
            anchorPosition,
            DeployLiquidityParams({
                pool: address(pool),
                receiver: vault,
                bips: 0,
                lowerTick: 0,
                upperTick: 0,
                tickSpacing: anchorPosition.tickSpacing,
                liquidityType: LiquidityType.Discovery,
                amounts: AmountsToMint({
                    amount0: 0, 
                    amount1: 0
                })
            })
        );

        liquidityType = LiquidityType.Discovery;
        discoveryPosition = newPosition;
        emit DiscoveryDeployed(newPosition);
    }

    function deployPosition(
        address _pool,
        address receiver,
        int24 lowerTick,
        int24 upperTick,
        LiquidityType liquidityType,
        AmountsToMint memory amounts
    ) public isVault
    returns (
        LiquidityPosition memory newPosition
    ) {
        return LiquidityDeployer
        .deployPosition(
            DeployLiquidityParams({
                pool: _pool,
                receiver: receiver,
                bips: 0,
                lowerTick: lowerTick,
                upperTick: upperTick,
                tickSpacing: floorPosition.tickSpacing,
                liquidityType: liquidityType,
                amounts: AmountsToMint({
                    amount0: amounts.amount0,
                    amount1: amounts.amount1
                })
            }) 
        );
    }

    /**
     * @notice Adjusts the floor liquidity position by shifting it to a new price range.
     * @dev This function interacts with the LiquidityDeployer library to modify the floor position.
     * @param pool The address of the Uniswap V3 pool containing the floor position.
     * @param receiver The address that will receive the adjusted floor position.
     * @param newFloorPrice The new price for the adjusted floor liquidity.
     * @param newFloorBalance The new balance of token1 for the adjusted floor liquidity.
     * @param floorPosition The existing floor liquidity position to be adjusted.
     * @return newPosition The newly adjusted floor liquidity position.
     */
    function shiftFloor(
        address pool,
        address receiver,
        uint256 newFloorPrice,
        uint256 newFloorBalance,
        LiquidityPosition memory floorPosition
    ) public isVault returns (LiquidityPosition memory newPosition) {
        if (receiver == address(0)) revert ("No receiver");
        // revert(
        //     string(
        //         abi.encodePacked(
        //             "shiftFloor: newFloorPrice is : ", 
        //             Utils._uint2str(uint256(newFloorPrice))
        //         )
        //     )
        // );        
        return LiquidityDeployer
        .shiftFloor(
            pool, 
            receiver, 
            newFloorPrice,
            newFloorBalance,
            floorPosition
        );
    }
    
    /**
     * @notice Calculates the new floor price after a liquidity adjustment.
     * @dev This function computes the floor price based on the provided parameters.
     * @param newBalance The new balance of token1 for the floor position.
     * @param circulatingSupply The circulating supply of tokens.
     * @return newFloorPrice The calculated new floor price.
     */
    function computeNewFloorPrice(
        uint256 newBalance,
        uint256 circulatingSupply
    ) external pure returns (uint256 newFloorPrice) {
        return Utils
        .computeNewFloorPrice(
            newBalance,
            circulatingSupply
        );
    }

    /// @notice Finalizes the deployment and transfers remaining balances back to the vault.
    function finalize() public onlyFactory {
        if (
            floorPosition.upperTick == 0 || 
            anchorPosition.upperTick == 0 || 
            discoveryPosition.upperTick == 0
        ) {
            revert NotDeployed();
        }

        LiquidityPosition[3] memory positions = [floorPosition, anchorPosition, discoveryPosition];

        uint256 balanceToken0 = IERC20(token0).balanceOf(address(this));
        IERC20(token0).safeTransfer(vault, balanceToken0);
        IVault(vault).initializeLiquidity(positions);
    }

    /// @dev Reentrancy lock modifier.
    modifier lock() {
        if (locked) revert Locked();
        locked = true;
        _;
        locked = false;
    }

    /// @dev Modifier to ensure only the vault can call certain functions.
    modifier isVault() {
        IAddressResolver(resolver).requireDeployerACL(msg.sender);
        _;
    }

    /// @dev Modifier to ensure only the factory can call certain functions.
    modifier onlyFactory() {
        if (msg.sender != factory) revert OnlyFactoryAllowed();
        _;
    }

    /// @dev Modifier to ensure the contract is initialized before certain functions can be called.
    modifier notInitialized() {
        if (initialized) revert AlreadyInitialized();
        _;
    }
}
