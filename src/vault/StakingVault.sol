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
    function calculateRewards(RewardParams memory params, uint256 timeElapsed) external pure returns (uint256);
}

error NotInitialized();
error LiquidityRatioOutOfRange();
error StakingContractNotSet();
error Unauthorized();
error NoStakingRewards();
error StakingNotEnabled();

contract StakingVault is BaseVault {

    function mintAndDistributeRewards(ProtocolAddresses memory addresses) public {
        if (msg.sender != address(this)) {
            revert Unauthorized();
        }

        if (_v.stakingContract == address(0)) {
            revert StakingContractNotSet();
        }

        if (!_v.stakingEnabled) {
            // revert StakingNotEnabled();
            return;
        }

        LiquidityPosition[3] memory positions = [
            _v.floorPosition, 
            _v.anchorPosition, 
            _v.discoveryPosition
        ];

        uint256 excessReservesToken1 = IModelHelper(_v.modelHelper)
        .getExcessReserveBalance(
            address(_v.pool),
            addresses.vault,
            false
        );

        uint256 intrinsicMinimumValue = IModelHelper(_v.modelHelper)
        .getIntrinsicMinimumValue(addresses.vault);

        uint256 circulatingSupply = IModelHelper(_v.modelHelper).getCirculatingSupply(addresses.pool, addresses.vault);
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
            block.timestamp - _v.timeLastMinted
        );
                
        if (toMint > 0) {        
            IERC20Metadata(_v.tokenInfo.token0).approve(_v.stakingContract, toMint);
            mintTokens(_v.stakingContract, toMint);
            // Update total minted (NOMA)
            _v.totalMinted += toMint;

            // Call notifyRewardAmount 
            IStakingRewards(_v.stakingContract).notifyRewardAmount(toMint);  

            // Send tokens to Floor
            _sendToken1ToFloor(positions, addresses, toMint);
        } else {
            revert(
                string(
                    abi.encodePacked(
                        "mintAndDistributeRewards: toMint is 0 : ", 
                        Utils._uint2str(uint256(toMint))
                    )
                )
            );
            // revert NoStakingRewards();
        }
    }

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

        {
            uint256 anchorCapacity = IModelHelper(addresses.modelHelper)
            .getPositionCapacity(
                addresses.pool, 
                addresses.vault, 
                positions[1],
                LiquidityType.Anchor
            );

            (
                uint256 circulatingSupply,,,
            ) = LiquidityOps.getVaulData(addresses);

            uint256 newFloorPrice = IDeployer(addresses.deployer)
            .computeNewFloorPrice(
                addresses.pool,
                toMint,
                floorToken1Balance,
                circulatingSupply,
                anchorCapacity,
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
    }

    function collectLiquidity(
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
        ) = LiquidityOps.getVaulData(addresses);

        // Collect all liquidity
        collectLiquidity(positions, addresses);

        if (floorToken1Balance + toMint > floorToken1Balance) {
            transferExcessBalance(addresses, floorToken1Balance + toMint);
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

        IModelHelper(_v.modelHelper)
            .enforceSolvencyInvariant(address(this));   
    }

    function transferExcessBalance(ProtocolAddresses memory addresses, uint256 totalAmount) internal {
        IERC20Metadata token1 = IERC20Metadata(IUniswapV3Pool(addresses.pool).token1());
        token1.transfer(addresses.deployer, totalAmount);
    }

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
            addresses,
            anchorToken1Balance,
            discoveryToken1Balance,
            toMint,
            sqrtRatioX96
        );

        positions[2] = _deployDiscoveryPosition(
            positions[1].upperTick,
            addresses,
            discoveryToken1Balance,
            sqrtRatioX96
        );

        IVault(addresses.vault).updatePositions(positions);  
    }

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
            addresses.vault,
            price,
            newFloorPrice,
            floorToken1Balance + toMint,
            floorToken1Balance,
            floorPosition
        );
    }

    function _deployAnchorPosition(
        int24 upperTick,
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
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96)
                ),
                amount1ToDeploy: (anchorToken1Balance + discoveryToken1Balance) - toMint,
                liquidityType: LiquidityType.Anchor
            }),
            true
        );
    }

    function _deployDiscoveryPosition(
        int24 anchorUpperTick,
        ProtocolAddresses memory addresses,
        uint256 discoveryToken1Balance,
        uint160 sqrtRatioX96
    ) internal returns (LiquidityPosition memory) {
        uint8 decimals = IERC20Metadata(IUniswapV3Pool(addresses.pool).token0()).decimals();
        int24 discoveryLowerTick = Utils.nearestUsableTick(
            Utils.addBipsToTick(
                anchorUpperTick,
                IVault(address(this)).getLiquidityStructureParameters().discoveryBips,
                decimals
            )
        );

        return LiquidityOps.reDeploy(
            addresses,
            LiquidityInternalPars({
                lowerTick: discoveryLowerTick,
                upperTick: Utils.nearestUsableTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96) * 
                    int8(IVault(address(this)).getLiquidityStructureParameters().idoPriceMultiplier)
                ),
                amount1ToDeploy: discoveryToken1Balance,
                liquidityType: LiquidityType.Discovery
            }),
            true
        );
    }

    function rewardsCalculator() public view returns (address) {
        return _v.resolver
        .requireAndGetAddress("RewardsCalculator", "No rewards calculator");
    }

    function setStakingContract(address _stakingContract) external onlyManager {
        _v.stakingContract = _stakingContract;
    }

    function getStakingContract() external view returns (address) {
        return _v.stakingContract;
    }

    function stakingEnabled() external view returns (bool) {
        return _v.stakingEnabled;
    }

    function getFunctionSelectors() external pure  override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = bytes4(keccak256(bytes("mintAndDistributeRewards((address,address,address,address,address))"))); 
        selectors[1] = bytes4(keccak256(bytes("setStakingContract(address)")));
        selectors[2] = bytes4(keccak256(bytes("getStakingContract()")));
        selectors[3] = bytes4(keccak256(bytes("stakingEnabled()")));
        return selectors;
    }
}