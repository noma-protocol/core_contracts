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

contract LendingVault is BaseVault {
    
    uint256 public constant SECONDS_IN_DAY = 86400;

    function _getCollateralAmount(uint256 borrowAmount) internal view returns (uint256, uint256) {
        uint256 intrinsicMinimumValue = IModelHelper(_v.modelHelper).getIntrinsicMinimumValue(address(this));
        return (DecimalMath.divideDecimal(borrowAmount, intrinsicMinimumValue), intrinsicMinimumValue);
    }

    function calculateLoanFees(uint256 borrowAmount, uint256 duration) internal pure returns (uint256 fees) {
        uint256 percentage = 27; // 0.027% 
        uint256 scaledPercentage = percentage * 10**12; 
        fees = (borrowAmount * scaledPercentage * (duration / SECONDS_IN_DAY)) / (100 * 10**18);
    }    

    function borrowFromFloor(address who, uint256 borrowAmount, uint256 duration) public onlyVault {
        require(borrowAmount > 0, "Amounts must be greater than 0");
        // require(_v.loanPositions[who].borrowAmount == 0, "Existing loan found");
        
        (uint256 collateralAmount,) = _getCollateralAmount(borrowAmount);
        require(collateralAmount > 0, "Collateral must be greater than 0");

        (,,, uint256 floorToken1Balance) = IModelHelper(_v.modelHelper)
        .getUnderlyingBalances(address(_v.pool), address(this), LiquidityType.Floor);

        require(floorToken1Balance >= borrowAmount, "Insufficient floor balance");

        IERC20(_v.pool.token0()).transferFrom(who, address(this), collateralAmount);  
        uint256 loanFees = calculateLoanFees(borrowAmount, duration);

        _v.collateralAmount += collateralAmount;
        
        LiquidityPosition[3] memory positions = [_v.floorPosition, _v.anchorPosition, _v.discoveryPosition];

        Uniswap.collect(address(_v.pool), address(this), _v.floorPosition.lowerTick, _v.floorPosition.upperTick);         
        LiquidityPosition memory newPosition = LiquidityDeployer.reDeployFloor(address(_v.pool), address(this), floorToken1Balance - borrowAmount, positions);
        
        IERC20(_v.pool.token1()).transfer(who, borrowAmount - loanFees);

        uint256 totalLoans = _v.totalLoansPerUser[who];
        LoanPosition memory loanPosition = LoanPosition({
            borrowAmount: borrowAmount,
            collateralAmount: collateralAmount,
            fees: loanFees,
            expiry: block.timestamp + uint256(duration),
            duration: duration
        });

        _v.loanPositions[who] = loanPosition;
        _v.totalLoansPerUser[who] = totalLoans++;
        _v.loanAddresses.push(who);

        IVault(address(this)).updatePositions([_v.floorPosition, _v.anchorPosition, _v.discoveryPosition]);
    }


    function paybackLoan(address who) public onlyVault {
        LoanPosition storage loan = _v.loanPositions[who];
        require(loan.borrowAmount > 0, "No active loan");

        IERC20(_v.pool.token1()).transferFrom(who, address(this), loan.borrowAmount);
        IERC20(_v.pool.token0()).transfer(who, loan.collateralAmount);

        delete _v.loanPositions[who];
        _removeLoanAddress(who);
    }

    function rollLoan(address who) public onlyVault {
        LoanPosition storage loan = _v.loanPositions[who];
        require(loan.borrowAmount > 0, "No active loan");
        require(block.timestamp < loan.expiry, "Loan expired");

        uint256 newCollateralValue = DecimalMath.multiplyDecimal(
            loan.collateralAmount, 
            IModelHelper(_v.modelHelper).getIntrinsicMinimumValue(address(this))
        );

        require(newCollateralValue > loan.borrowAmount, "Can't roll loan");
        uint256 newBorrowAmount = newCollateralValue - loan.borrowAmount;
        uint256 newFees = calculateLoanFees(newBorrowAmount, loan.expiry - block.timestamp);

        (,,, uint256 floorToken1Balance) = IModelHelper(_v.modelHelper)
        .getUnderlyingBalances(address(_v.pool), address(this), LiquidityType.Floor);

        LiquidityPosition[3] memory positions = [_v.floorPosition, _v.anchorPosition, _v.discoveryPosition];

        Uniswap.collect(address(_v.pool), address(this), _v.floorPosition.lowerTick, _v.floorPosition.upperTick);      
           
        LiquidityPosition memory newPosition = LiquidityDeployer.reDeployFloor(
            address(_v.pool), 
            address(this), 
            floorToken1Balance - newBorrowAmount, 
            positions
        );

        IERC20(_v.pool.token1()).transfer(who, newBorrowAmount - newFees);        
    }

    function defaultLoans() public onlyVault {
        for (uint256 i = 0; i < _v.loanAddresses.length; i++) {
            address who = _v.loanAddresses[i];
            LoanPosition storage loan = _v.loanPositions[who];
            if (block.timestamp > loan.expiry) {
                _seizeCollateral(who);
                delete _v.loanPositions[who];
                _removeLoanAddress(who);
            }
        }
    }

    function _seizeCollateral(address who) internal {
        LoanPosition storage loan = _v.loanPositions[who];
        uint256 collateralAmount = loan.collateralAmount;
        IERC20(_v.pool.token0()).transfer(address(this), collateralAmount);
        _v.collateralAmount -= collateralAmount;
    }

    function _removeLoanAddress(address who) internal {
        for (uint256 i = 0; i < _v.loanAddresses.length; i++) {
            if (_v.loanAddresses[i] == who) {
                _v.loanAddresses[i] = _v.loanAddresses[_v.loanAddresses.length - 1];
                _v.loanAddresses.pop();
                break;
            }
        }
    }

    modifier onlyVault() {
        require(msg.sender == address(this), "LendingVault: only vault");
        _;
    }

    function getFunctionSelectors() external pure override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = bytes4(keccak256(bytes("borrowFromFloor(address,uint256,uint256)")));    
        selectors[1] = bytes4(keccak256(bytes("paybackLoan(address)")));
        selectors[2] = bytes4(keccak256(bytes("rollLoan(address)")));
        selectors[3] = bytes4(keccak256(bytes("defaultLoans()")));
        return selectors;
    }
}
