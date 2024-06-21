// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {BaseVault} from "./BaseVault.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {LiquidityOps} from "../libraries/LiquidityOps.sol";

import "../libraries/Conversions.sol";
import "../libraries/DecimalMath.sol";
import "../libraries/Utils.sol";
import "../libraries/Uniswap.sol";
import "../libraries/LiquidityDeployer.sol";
import "../libraries/Underlying.sol";

import {
    LiquidityPosition, 
    LiquidityType,
    ProtocolAddresses,
    LoanPosition
} from "../Types.sol";

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external;
    function mint(address receiver, uint256 amount) external;
}

interface IStakingRewards {
    function notifyRewardAmount(uint256 reward) external;
}

interface IVault {
    function updatePositions(LiquidityPosition[3] memory newPositions) external;
    function setFees(uint256 _feesAccumulatedToken0, uint256 _feesAccumulatedToken1) external;
}

contract BorrowVault is BaseVault {

    function _getCollateralValue(
        uint256 amount
    ) internal view returns (uint256) {

        uint256 intrinsicMinimumValue = IModelHelper(_v.modelHelper)
        .getIntrinsicMinimumValue(address(this)) * 1e18;

        return intrinsicMinimumValue * amount;
    }
    
    function borrowFromFloor(
        address who,
        uint256 collateralAmount,
        uint256 borrowAmount,
        int256 duration
    ) public onlyVault {

        require(borrowAmount > 0 && collateralAmount > 0, "Amounts must be greater than 0");
        uint256 collateralValue = _getCollateralValue(collateralAmount);

        require(collateralValue >= borrowAmount, "Insufficient collateral");

        (,,, uint256 floorToken1Balance)  = IModelHelper(_v.modelHelper)
        .getUnderlyingBalances(
            address(_v.pool),
            address(this),
            LiquidityType.Floor
        );

        require(floorToken1Balance >= borrowAmount, "Insufficient floor balance");
        
        // Requires approval
        IERC20(_v.pool.token0()).transferFrom(who, address(this), collateralAmount);
        
        uint256 fees = Utils.calculateLoanFees(borrowAmount);

        // Requires approval
        IERC20(_v.pool.token1()).transferFrom(who, address(this), fees);

        _v.collateralAmount += collateralAmount;

        IERC20(_v.pool.token0()).transfer(_v.escrowContract, collateralAmount);

        // Collect floor liquidity
        Uniswap.collect(
            address(_v.pool), 
            address(this), 
            _v.floorPosition.lowerTick, 
            _v.floorPosition.upperTick
        );         

        LiquidityPosition memory newPosition = LiquidityDeployer
        .reDeployFloor(
            address(_v.pool),
            address(this),
            floorToken1Balance - borrowAmount,
            _v.floorPosition
        );

        IERC20(_v.pool.token0()).transfer(who, borrowAmount);

        uint256 totalLoans = _v.totalLoansPerUser[who];

        LoanPosition memory loanPosition = LoanPosition({
            borrowAmount: borrowAmount,
            collateralAmount: collateralAmount,
            fees: fees,
            expiry: block.timestamp + 30 days,
            duration: duration
        });

        _v.loanPositions[who] = loanPosition;
        _v.totalLoansPerUser[who] = totalLoans++;

        IVault(address(this)).updatePositions([
            _v.floorPosition,
            _v.anchorPosition,
            _v.discoveryPosition
        ]);
    }

    modifier onlyVault() {
        require(msg.sender == address(this), "BorrowVault: only vault");
        _;
    }

    function getFunctionSelectors() external pure  override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256(bytes("borrowFromFloor(address,uint256,uint256)")));      
        return selectors;
    }
}