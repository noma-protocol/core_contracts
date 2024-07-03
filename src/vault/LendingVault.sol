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

contract LendingVault is BaseVault {
    
    uint256 constant PER_DIEM_FEE = 27; // 0.027%
    uint256 constant FEE_DIVISOR = 100000;

    function _getCollateralAmount(uint256 borrowAmount) internal view returns (uint256) {
        uint256 intrinsicMinimumValue = IModelHelper(_v.modelHelper).getIntrinsicMinimumValue(address(this));
        return DecimalMath.divideDecimal(borrowAmount, intrinsicMinimumValue);
    }
    
    function borrowFromFloor(address who, uint256 borrowAmount, int256 duration) public onlyVault {
        require(borrowAmount > 0, "Amounts must be greater than 0");
        require(_v.loanPositions[who].borrowAmount == 0, "Existing loan found");
        
        uint256 collateralAmount = _getCollateralAmount(borrowAmount);
        require(collateralAmount > 0, "Collateral must be greater than 0");

        (,,, uint256 floorToken1Balance) = IModelHelper(_v.modelHelper).getUnderlyingBalances(address(_v.pool), address(this), LiquidityType.Floor);
        require(floorToken1Balance >= borrowAmount, "Insufficient floor balance");

        IERC20(_v.pool.token0()).transferFrom(who, address(this), collateralAmount);  
        uint256 loanFees = calculateLoanFees(borrowAmount, duration);
        IERC20(_v.pool.token1()).transferFrom(who, address(this), loanFees);

        _v.collateralAmount += collateralAmount;
        IERC20(_v.pool.token0()).transfer(_v.escrowContract, collateralAmount);

        Uniswap.collect(address(_v.pool), address(this), _v.floorPosition.lowerTick, _v.floorPosition.upperTick);         
        LiquidityPosition memory newPosition = LiquidityDeployer.reDeployFloor(address(_v.pool), address(this), floorToken1Balance - borrowAmount, _v.floorPosition);

        IERC20(_v.pool.token1()).transfer(who, borrowAmount);

        uint256 totalLoans = _v.totalLoansPerUser[who];
        LoanPosition memory loanPosition = LoanPosition({
            borrowAmount: borrowAmount,
            collateralAmount: collateralAmount,
            fees: loanFees,
            expiry: block.timestamp + (duration * 1 days),
            duration: duration
        });

        _v.loanPositions[who] = loanPosition;
        _v.totalLoansPerUser[who] = totalLoans++;

        IVault(address(this)).updatePositions([_v.floorPosition, _v.anchorPosition, _v.discoveryPosition]);
    }

    function calculateLoanFees(uint256 borrowAmount, int256 duration) internal pure returns (uint256) {
        return (borrowAmount * PER_DIEM_FEE * uint256(duration)) / FEE_DIVISOR;
    }

    function paybackLoan(address who, uint256 paybackAmount) public onlyVault {
        LoanPosition storage loan = _v.loanPositions[who];
        require(loan.borrowAmount > 0, "No active loan");
        require(paybackAmount > 0, "Payback amount must be greater than 0");

        if (paybackAmount >= loan.borrowAmount) {
            uint256 excess = paybackAmount - loan.borrowAmount;
            if (excess > 0) {
                IERC20(_v.pool.token0()).transfer(who, excess);
            }
            delete _v.loanPositions[who];
        } else {
            loan.borrowAmount -= paybackAmount;
        }
        IERC20(_v.pool.token0()).transferFrom(who, address(this), paybackAmount);
    }

    function rollLoan(address who) public onlyVault {
        LoanPosition storage loan = _v.loanPositions[who];
        require(loan.borrowAmount > 0, "No active loan");
        require(block.timestamp < loan.expiry, "Loan expired");

        uint256 newBorrowAmount = loan.borrowAmount;
        uint256 newFees = calculateLoanFees(newBorrowAmount, loan.duration);
        
        IERC20(_v.pool.token1()).transferFrom(who, address(this), newFees);
        loan.fees += newFees;
        loan.expiry = block.timestamp + 30 days;
    }

    function defaultLoans() public onlyVault {
        // Iterate over all loans and default the expired ones
        for (uint256 i = 0; i < _v.loanPositions.length; i++) {
            address who = _v.loanPositions[i].who;
            LoanPosition storage loan = _v.loanPositions[who];
            if (block.timestamp > loan.expiry) {
                _seizeCollateral(who);
                delete _v.loanPositions[who];
            }
        }
    }

    function _seizeCollateral(address who) internal {
        LoanPosition storage loan = _v.loanPositions[who];
        uint256 collateralAmount = loan.collateralAmount;
        IERC20(_v.pool.token0()).transfer(address(this), collateralAmount);
        _v.collateralAmount -= collateralAmount;
    }

    modifier onlyVault() {
        require(msg.sender == address(this), "BorrowVault: only vault");
        _;
    }

    function getFunctionSelectors() external pure override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256(bytes("borrowFromFloor(address,uint256,int256)")));    
        selectors[1] = bytes4(kekkak256(butes("paybackLoan(address,uint256)")));
        selectors[2] = bytes4(kekkak256(butes("rollLoan(address)")));
        selectors[3] = bytes4(kekkak256(butes("defaultLoans()")));
        return selectors;
    }
}
