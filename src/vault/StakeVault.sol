// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {BaseVault} from "./BaseVault.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {IDeployer} from "../interfaces/IDeployer.sol";
import {LiquidityOps} from "../libraries/LiquidityOps.sol";

import "../libraries/Conversions.sol";
import "../libraries/DecimalMath.sol";
import "../libraries/Utils.sol";
import "../libraries/Uniswap.sol";

import {
    LiquidityPosition, 
    LiquidityType,
    ProtocolAddresses
} from "../Types.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function mint(address receiver, uint256 amount) external;
    function approve(address spender, uint256 amount) external;
}

interface IStakingRewards {
    function notifyRewardAmount(uint256 reward) external;
}

interface IVault {
    function updatePositions(LiquidityPosition[3] memory newPositions) external;
    function setFees(uint256 _feesAccumulatedToken0, uint256 _feesAccumulatedToken1) external;
}

contract StakeVault is BaseVault {

    function mintAndDistributeRewards(ProtocolAddresses memory addresses) public {

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

        uint256 currentLiquidityRatio = IModelHelper(_v.modelHelper)
        .getLiquidityRatio(address(_v.pool), addresses.vault);
        
        uint256 minAmountToMint = excessReservesToken1 * 0.1e18;

        uint256 toMint = (
            excessReservesToken1 * 
            (100e18 - currentLiquidityRatio) / 1000
        ) + minAmountToMint;

        uint256 intrinsicMinimumValue = IModelHelper(_v.modelHelper)
        .getIntrinsicMinimumValue(addresses.vault) * 1e18;

        uint256 toMintScaled = DecimalMath.divideDecimal(toMint, intrinsicMinimumValue);
        
        IERC20(_v.tokenInfo.token0).mint(address(this), toMintScaled);
        IERC20(_v.tokenInfo.token0).approve(_v.stakingContract, toMintScaled);

        // if (
        //     Conversions.sqrtPriceX96ToPrice(
        //         Conversions.tickToSqrtPriceX96(positions[0].lowerTick),
        //         18
        //     ) > 1e18
        // ) {
        //     revert(
        //         string(
        //             abi.encodePacked(
        //                     "mintAndDistributeRewards: ", 
        //                     Utils._uint2str(uint256(toMint)
        //                 )
        //             )
        //         )
        //     );   
        // }

        // Call notifyRewardAmount 
        IStakingRewards(_v.stakingContract).notifyRewardAmount(toMintScaled);  

        // Send tokens to Floor
        _sendToken1ToFloor(positions, addresses, toMintScaled, intrinsicMinimumValue);
    }

    function _sendToken1ToFloor(
        LiquidityPosition[3] memory positions, 
        ProtocolAddresses memory addresses,
        uint256 toMint,
        uint256 intrinsicMinimumValue
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
                uint256 circulatingSupply,, 
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

            // Bump floor if necessary
            if (newFloorPrice > 102e16) {
                _shiftPositions(
                    positions, 
                    addresses, 
                    newFloorPrice, 
                    toMint, 
                    floorToken1Balance
                );
                // newPositions[1] = positions[1];
                // newPositions[2] = positions[2];
            } else {
                
            }
        }        
    }

    function _shiftPositions(
        LiquidityPosition[3] memory positions, 
        ProtocolAddresses memory addresses,
        uint256 newFloorPrice,
        uint256 toMint,
        uint256 floorToken1Balance
    ) internal {
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(addresses.pool).slot0();
        
        (
            ,
            uint256 anchorToken1Balance, 
            uint256 discoveryToken1Balance
        ) = LiquidityOps.getVaulData(addresses);

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

        if (floorToken1Balance + toMint > floorToken1Balance) {
            ERC20(IUniswapV3Pool(addresses.pool).token1()).transfer(
                addresses.deployer, 
                floorToken1Balance + toMint
            );
        }

        {
            positions[0] = IDeployer(addresses.deployer) 
            .shiftFloor(
                addresses.pool, 
                addresses.vault, 
                Conversions
                .sqrtPriceX96ToPrice(
                    Conversions
                    .tickToSqrtPriceX96(
                        positions[0].upperTick
                    ), 
                18), 
                newFloorPrice,
                floorToken1Balance + toMint,
                floorToken1Balance,
                positions[0]
            );   

            // Deploy new anchor position
            positions[1] = LiquidityOps
            .reDeploy(
                addresses.pool,
                addresses.deployer,
                positions[0].upperTick,                
                Utils.nearestUsableTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96)      
                ),
                (anchorToken1Balance + discoveryToken1Balance) - toMint, 
                LiquidityType.Anchor
            );

            positions[2] = LiquidityOps
            .reDeploy(
                addresses.pool,
                addresses.deployer, 
                Utils.nearestUsableTick(
                    Utils.addBipsToTick(positions[1].upperTick, 150)
                ),
                Utils.nearestUsableTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96) * 3     
                ),                
                0,
                LiquidityType.Discovery 
            ); 

            IVault(addresses.vault).updatePositions(positions);  

        }
      
    }



    function getFunctionSelectors() external pure  override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256(bytes("mintAndDistributeRewards((address,address,address,address))")));      
        return selectors;
    }
}