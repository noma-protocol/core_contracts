// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {BaseVault} from "./BaseVault.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";

import {
    LiquidityPosition
} from "../Types.sol";

import "../libraries/Conversions.sol";
import "../libraries/DecimalMath.sol";
import "../libraries/Utils.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function mint(address receiver, uint256 amount) external;
    function approve(address spender, uint256 amount) external;
}

interface IStakingRewards {
    function notifyRewardAmount(uint256 reward) external;
}

contract ExtVault is BaseVault {

    function mintAndDistributeRewards(address _vault) public {

        LiquidityPosition[3] memory positions = [
            _v.floorPosition, 
            _v.anchorPosition, 
            _v.discoveryPosition
        ];

        uint256 excessReservesToken1 = IModelHelper(_v.modelHelper)
        .getExcessReserveBalance(
            address(_v.pool),
            _vault,
            false
        );

        uint256 currentLiquidityRatio = IModelHelper(_v.modelHelper)
        .getLiquidityRatio(address(_v.pool), _vault);
        
        uint256 minMintAmount = excessReservesToken1 * 0.1e18;

        uint256 toMint = (
            excessReservesToken1 * 
            (100e18 - currentLiquidityRatio) / 1000
        ) + minMintAmount;

        uint256 intrinsicMinimumValue = IModelHelper(_v.modelHelper)
        .getIntrinsicMinimumValue(_vault);

        toMint = DecimalMath.divideDecimal(toMint, intrinsicMinimumValue * 1e18);
        
        IERC20(_v.tokenInfo.token1).mint(address(this), toMint);
        IERC20(_v.tokenInfo.token1).approve(_v.stakingContract, toMint);

        if (
            Conversions.sqrtPriceX96ToPrice(
                Conversions.tickToSqrtPriceX96(positions[0].lowerTick),
                18
            ) > 1e18
        ) {
            revert(
                string(
                    abi.encodePacked(
                            "shift: ", 
                            Utils._uint2str(uint256(toMint)
                        )
                    )
                )
            );   
        }

        // Call notifyRewardAmount 
        IStakingRewards(_v.stakingContract).notifyRewardAmount(toMint);        
    }

    function getFunctionSelectors() external pure  override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256(bytes("mintAndDistributeRewards(address)")));
        return selectors;
    }
}