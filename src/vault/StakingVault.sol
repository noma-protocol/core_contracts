// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseVault} from "./BaseVault.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {IDeployer} from "../interfaces/IDeployer.sol";
import {LiquidityOps} from "../libraries/LiquidityOps.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Conversions} from "../libraries/Conversions.sol";
import {Utils} from "../libraries/Utils.sol";
import {Uniswap} from "../libraries/Uniswap.sol";
import {IVault} from "../interfaces/IVault.sol";
import {TickMath} from 'v3-core/libraries/TickMath.sol';

import {
    LiquidityPosition, 
    LiquidityType,
    ProtocolAddresses,
    RewardParams,
    LiquidityInternalPars
} from "../types/Types.sol";

interface IStakingRewards {
    function notifyRewardAmount(uint256 reward) external;
}

interface IRewardsCalculator {
    function calculateRewards(RewardParams memory params, uint256 timeElapsed, address token0) external pure returns (uint256);
}

// Custom errors
error NotInitialized();
error LiquidityRatioOutOfRange();
error StakingContractNotSet();
error Unauthorized();
error NoStakingRewards();
error StakingNotEnabled();

/**
 * @title StakingVault
 * @notice A contract for managing staking rewards and distributing them to stakers.
 * @dev This contract extends the `BaseVault` contract and provides functionality for minting and distributing staking rewards.
 */
contract StakingVault is BaseVault {

    /**
     * @notice Mints and distributes staking rewards to the staking contract.
     * @param addresses The protocol addresses.
     */
    function mintAndDistributeRewards(ProtocolAddresses memory addresses) public onlyInternalCalls {
        if (msg.sender != address(this)) {
            revert Unauthorized();
        }

        if (_v.stakingContract == address(0)) {
            revert StakingContractNotSet();
        }

        if (!_v.stakingEnabled) {
            return;
        }

        LiquidityPosition[3] memory positions = [
            _v.floorPosition, 
            _v.anchorPosition, 
            _v.discoveryPosition
        ];

        uint256 excessReservesToken1 = IModelHelper(modelHelper())
        .getExcessReserveBalance(
            address(_v.pool),
            address(this),
            false
        );

        uint256 intrinsicMinimumValue = IModelHelper(modelHelper())
        .getIntrinsicMinimumValue(address(this));

        uint256 circulatingSupply = IModelHelper(modelHelper()).getCirculatingSupply(addresses.pool, address(this));
        uint256 totalSupply = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).totalSupply();

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(addresses.pool).slot0();

        uint256 toMint = IRewardsCalculator(rewardsCalculator()).
        calculateRewards(
            RewardParams(
                excessReservesToken1,
                intrinsicMinimumValue,
                Conversions.sqrtPriceX96ToPrice(
                    sqrtRatioX96, 
                    IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).decimals()
                ),
                circulatingSupply,
                totalSupply,
                10e8 // sensitivity for r TODO remove hardcoded
            ),
            block.timestamp - _v.timeLastMinted,
            IUniswapV3Pool(addresses.pool).token0()
        );
                
        if (toMint > 0) {        
            IERC20Metadata(_v.tokenInfo.token0).approve(_v.stakingContract, toMint);
            IVault(address(this)).mintTokens(_v.stakingContract, toMint);
            // Update total minted (NOMA)
            _v.totalMinted += toMint;

            // Call notifyRewardAmount 
            IStakingRewards(_v.stakingContract).notifyRewardAmount(toMint);  

            // Send tokens to Floor
            _sendToken1ToFloor(positions, addresses, toMint);
        } else {
            revert NoStakingRewards();
        }
    }

    /**
     * @notice Sends token1 to the floor position.
     * @param positions The current liquidity positions.
     * @param addresses The protocol addresses.
     * @param toMint The amount of tokens to mint.
     */
    function _sendToken1ToFloor(
        LiquidityPosition[3] memory positions, 
        ProtocolAddresses memory addresses,
        uint256 toMint
    ) internal {

        (,,, uint256 floorToken1Balance) = IModelHelper(addresses.modelHelper)
        .getUnderlyingBalances(
            addresses.pool, 
            address(this), 
            LiquidityType.Floor
        );

        (
            uint256 circulatingSupply,,,
        ) = LiquidityOps.getVaultData(addresses);

        uint256 newFloorPrice = IDeployer(addresses.deployer)
        .computeNewFloorPrice(
            toMint,
            floorToken1Balance,
            circulatingSupply,
            positions
        );

        uint256 currentFloorPrice = Conversions
        .sqrtPriceX96ToPrice(
            Conversions
            .tickToSqrtPriceX96(
                positions[0].upperTick
            ), 
        IERC20Metadata(address(IUniswapV3Pool(addresses.pool).token0())).decimals());
        
        // Bump floor if necessary
        if (newFloorPrice > currentFloorPrice) {
            _shiftPositions(
                positions, 
                addresses, 
                newFloorPrice, 
                toMint, 
                floorToken1Balance
            );
        }  
    }

    /**
     * @notice Collects liquidity from all positions.
     * @param positions The current liquidity positions.
     * @param addresses The protocol addresses.
     */
    function _collectLiquidity(
        LiquidityPosition[3] memory positions,
        ProtocolAddresses memory addresses
    ) internal {
        // Collect floor liquidity
        Uniswap.collect(
            addresses.pool, 
            address(this), 
            positions[0].lowerTick, 
            positions[0].upperTick
        );

        // Collect discovery liquidity
        Uniswap.collect(
            addresses.pool, 
            address(this), 
            positions[2].lowerTick, 
            positions[2].upperTick
        );

        // Collect anchor liquidity
        Uniswap.collect(
            addresses.pool, 
            address(this), 
            positions[1].lowerTick, 
            positions[1].upperTick
        );
    }

    /**
     * @notice Shifts the liquidity positions to adjust for new rewards.
     * @param positions The current liquidity positions.
     * @param addresses The protocol addresses.
     * @param newFloorPrice The new floor price.
     * @param toMint The amount of tokens to mint.
     * @param floorToken1Balance The balance of token1 in the floor position.
     */
    function _shiftPositions(
        LiquidityPosition[3] memory positions, 
        ProtocolAddresses memory addresses,
        uint256 newFloorPrice,
        uint256 toMint,
        uint256 floorToken1Balance
    ) internal {
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(addresses.pool).slot0();

        ( , uint256 anchorToken1Balance, 
            uint256 discoveryToken1Balance,
        ) = LiquidityOps.getVaultData(addresses);

        // Collect all liquidity
        _collectLiquidity(positions, addresses);

        // TODO check this
        if (floorToken1Balance + toMint > floorToken1Balance) {
            _transferExcessBalance(addresses, floorToken1Balance + toMint);
        }

        _deployNewPositions(
            positions, 
            addresses, 
            newFloorPrice, 
            toMint, 
            floorToken1Balance, 
            anchorToken1Balance, 
            discoveryToken1Balance, 
            sqrtRatioX96
        );

        IModelHelper(modelHelper())
            .enforceSolvencyInvariant(address(this));   
    }

    /**
     * @notice Transfers excess balance to the deployer.
     * @param addresses The protocol addresses.
     * @param totalAmount The total amount to transfer.
     */
    function _transferExcessBalance(ProtocolAddresses memory addresses, uint256 totalAmount) internal {
        IERC20Metadata token1 = IERC20Metadata(IUniswapV3Pool(addresses.pool).token1());
        token1.transfer(addresses.deployer, totalAmount);
    }

    /**
     * @notice Deploys new liquidity positions.
     * @param positions The current liquidity positions.
     * @param addresses The protocol addresses.
     * @param newFloorPrice The new floor price.
     * @param toMint The amount of tokens to mint.
     * @param floorToken1Balance The balance of token1 in the floor position.
     * @param anchorToken1Balance The balance of token1 in the anchor position.
     * @param discoveryToken1Balance The balance of token1 in the discovery position.
     * @param sqrtRatioX96 The current sqrt price of the pool.
     */
    function _deployNewPositions(
        LiquidityPosition[3] memory positions, 
        ProtocolAddresses memory addresses,
        uint256 newFloorPrice,
        uint256 toMint,
        uint256 floorToken1Balance,
        uint256 anchorToken1Balance,
        uint256 discoveryToken1Balance,
        uint160 sqrtRatioX96
    ) internal {
        positions[0] = _shiftFloorPosition(
            positions[0],
            addresses,
            newFloorPrice,
            floorToken1Balance,
            toMint
        );

        positions[1] = _deployAnchorPosition(
            positions[0].upperTick,
            positions[0].tickSpacing,
            addresses,
            anchorToken1Balance,
            discoveryToken1Balance,
            toMint,
            sqrtRatioX96
        );

        positions[2] = _deployDiscoveryPosition(
            positions[1].upperTick,
            positions[1].tickSpacing,
            addresses,
            discoveryToken1Balance,
            sqrtRatioX96
        );

        IVault(address(this)).updatePositions(positions);  
    }

    /**
     * @notice Shifts the floor position to a new price.
     * @param floorPosition The current floor position.
     * @param addresses The protocol addresses.
     * @param newFloorPrice The new floor price.
     * @param floorToken1Balance The balance of token1 in the floor position.
     * @param toMint The amount of tokens to mint.
     * @return The new floor position.
     */
    function _shiftFloorPosition(
        LiquidityPosition memory floorPosition,
        ProtocolAddresses memory addresses,
        uint256 newFloorPrice,
        uint256 floorToken1Balance,
        uint256 toMint
    ) internal returns (LiquidityPosition memory) {
        uint8 decimals = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).decimals();
        uint256 price = Conversions.sqrtPriceX96ToPrice(
            Conversions.tickToSqrtPriceX96(floorPosition.upperTick),
            decimals
        );

        return IDeployer(addresses.deployer).shiftFloor(
            addresses.pool,
            address(this),
            price,
            newFloorPrice,
            floorToken1Balance + toMint,
            floorToken1Balance,
            floorPosition
        );
    }

    /**
     * @notice Deploys a new anchor position.
     * @param upperTick The upper tick of the floor position.
     * @param tickSpacing The tick spacing of the pool.
     * @param addresses The protocol addresses.
     * @param anchorToken1Balance The balance of token1 in the anchor position.
     * @param discoveryToken1Balance The balance of token1 in the discovery position.
     * @param toMint The amount of tokens to mint.
     * @param sqrtRatioX96 The current sqrt price of the pool.
     * @return The new anchor position.
     */
    function _deployAnchorPosition(
        int24 upperTick,
        int24 tickSpacing,
        ProtocolAddresses memory addresses,
        uint256 anchorToken1Balance,
        uint256 discoveryToken1Balance,
        uint256 toMint,
        uint160 sqrtRatioX96
    ) internal returns (LiquidityPosition memory) {
        return LiquidityOps.reDeploy(
            addresses,
            LiquidityInternalPars({
                lowerTick: upperTick,
                upperTick: Utils.nearestUsableTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96),
                    tickSpacing
                ),
                amount1ToDeploy: (anchorToken1Balance + discoveryToken1Balance) - toMint,
                liquidityType: LiquidityType.Anchor
            }),
            true
        );
    }

    /**
     * @notice Deploys a new discovery position.
     * @param anchorUpperTick The upper tick of the anchor position.
     * @param tickSpacing The tick spacing of the pool.
     * @param addresses The protocol addresses.
     * @param discoveryToken1Balance The balance of token1 in the discovery position.
     * @param sqrtRatioX96 The current sqrt price of the pool.
     * @return The new discovery position.
     */
    function _deployDiscoveryPosition(
        int24 anchorUpperTick,
        int24 tickSpacing,
        ProtocolAddresses memory addresses,
        uint256 discoveryToken1Balance,
        uint160 sqrtRatioX96
    ) internal returns (LiquidityPosition memory) {
        uint8 decimals = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).decimals();
        int24 discoveryLowerTick = Utils.nearestUsableTick(
            Utils.addBipsToTick(
                anchorUpperTick,
                IVault(address(this)).getProtocolParameters().discoveryBips,
                decimals,
                tickSpacing
            ),
            tickSpacing
        );

        return LiquidityOps.reDeploy(
            addresses,
            LiquidityInternalPars({
                lowerTick: discoveryLowerTick,
                upperTick: Utils.nearestUsableTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96) * 
                    int8(IVault(address(this)).getProtocolParameters().idoPriceMultiplier),
                    tickSpacing
                ),
                amount1ToDeploy: discoveryToken1Balance,
                liquidityType: LiquidityType.Discovery
            }),
            true
        );
    }

    /**
     * @notice Retrieves the address of the rewards calculator.
     * @return The address of the rewards calculator.
     */
    function rewardsCalculator() public view returns (address) {
        return _v.resolver
        .requireAndGetAddress("RewardsCalculator", "No rewards calculator");
    }

    /**
     * @notice Sets the staking contract address.
     * @param _stakingContract The address of the staking contract.
     */
    function setStakingContract(address _stakingContract) external onlyManager {
        _v.stakingContract = _stakingContract;
    }

    /**
     * @notice Retrieves the staking contract address.
     * @return The address of the staking contract.
     */
    function getStakingContract() external view returns (address) {
        return _v.stakingContract;
    }

    /**
     * @notice Checks if staking is enabled.
     * @return True if staking is enabled, false otherwise.
     */
    function stakingEnabled() external view returns (bool) {
        return _v.stakingEnabled;
    }

    /**
     * @notice Modifier to restrict access to the manager.
     */
    modifier onlyManager() {
        if (msg.sender != _v.manager) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
    function getFunctionSelectors() external pure  override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = bytes4(keccak256(bytes("mintAndDistributeRewards((address,address,address,address,address))"))); 
        selectors[1] = bytes4(keccak256(bytes("setStakingContract(address)")));
        selectors[2] = bytes4(keccak256(bytes("getStakingContract()")));
        selectors[3] = bytes4(keccak256(bytes("stakingEnabled()")));
        return selectors;
    }
}