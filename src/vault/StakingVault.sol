// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {BaseVault} from "./BaseVault.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {IDeployer} from "../interfaces/IDeployer.sol";
import {LiquidityOps} from "../libraries/LiquidityOps.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import "../libraries/Conversions.sol";
import "../libraries/DecimalMath.sol";
import "../libraries/Utils.sol";
import "../libraries/Uniswap.sol";
import "../libraries/LiquidityDeployer.sol";

import {
    LiquidityPosition, 
    LiquidityType,
    ProtocolAddresses,
    LiquidityStructureParameters,
    RewardParams,
    LiquidityInternalPars
} from "../types/Types.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function mint(address receiver, uint256 amount) external;
    function approve(address spender, uint256 amount) external;
    function totalSupply() external view returns (uint256);
}

interface IStakingRewards {
    function notifyRewardAmount(uint256 reward) external;
}

interface IRewardsCalculator {
    function calculateRewards(RewardParams memory params) external pure returns (uint256);
}

error NotInitialized();
error LiquidityRatioOutOfRange();
error StakingContractNotSet();
error Unauthorized();
error NoStakingRewards();

contract StakingVault is BaseVault {

    function mintAndDistributeRewards(ProtocolAddresses memory addresses) public {
        if (msg.sender != address(this)) {
            revert Unauthorized();
        }

        if (_v.stakingContract == address(0)) {
            revert StakingContractNotSet();
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
        uint256 totalSupply = IERC20(IUniswapV3Pool(addresses.pool).token0()).totalSupply();

        uint256 toMint = IRewardsCalculator(rewardsCalculator()).
        calculateRewards(
            RewardParams(
                excessReservesToken1,
                intrinsicMinimumValue,
                circulatingSupply,
                totalSupply,
                1e18, // volatility
                10e8, // sensitivity for r 
                1e18  // sensitivity for v
            )
        );
                
        if (toMint > 0) {        
            IERC20(_v.tokenInfo.token0).approve(_v.stakingContract, toMint);
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
            ERC20(address(IUniswapV3Pool(addresses.pool).token0())).decimals());
            
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
        ERC20 token1 = ERC20(IUniswapV3Pool(addresses.pool).token1());
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
        uint8 decimals = ERC20(IUniswapV3Pool(addresses.pool).token0()).decimals();
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
        uint8 decimals = ERC20(IUniswapV3Pool(addresses.pool).token0()).decimals();
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


    function setFees(
        uint256 _feesAccumulatedToken0, 
        uint256 _feesAccumulatedToken1
    ) public onlyInternalCalls {

        _v.feesAccumulatorToken0 += _feesAccumulatedToken0;
        _v.feesAccumulatorToken1 += _feesAccumulatedToken1;
    }

    function getLiquidityStructureParameters() public view returns 
    (LiquidityStructureParameters memory ) {
        return _v.liquidityStructureParameters;
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

    function getFunctionSelectors() external pure  override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = bytes4(keccak256(bytes("mintAndDistributeRewards((address,address,address,address,address))"))); 
        selectors[1] = bytes4(keccak256(bytes("getLiquidityStructureParameters()")));  
        selectors[2] = bytes4(keccak256(bytes("setStakingContract(address)")));
        selectors[3] = bytes4(keccak256(bytes("setFees(uint256,uint256)")));
        selectors[4] = bytes4(keccak256(bytes("getStakingContract()")));
        return selectors;
    }
}