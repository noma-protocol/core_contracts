// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseVault} from "./BaseVault.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";

import {DecimalMath} from "../libraries/DecimalMath.sol";
import {Uniswap} from "../libraries/Uniswap.sol";
import {LiquidityDeployer} from "../libraries/LiquidityDeployer.sol";

import {IVault} from "../interfaces/IVault.sol";

import {
    LiquidityPosition, 
    LiquidityType,
    LoanPosition,
    LiquidityStructureParameters
} from "../types/Types.sol";

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

interface INomaFactory {
    function mintTokens(address to, uint256 amount) external;
    function burnFor(address from, uint256 amount) external;
    function teamMultiSig() external view returns (address);
}

error NotInitialized();
error InsufficientLoanAmount();
error InsufficientFloorBalance();
error NoActiveLoan();
error LoanExpired();
error InsufficientCollateral();
error CantRollLoan();
error NoLiquidity();
error OnlyVault();

contract LendingVault is BaseVault {
    
    uint256 public constant SECONDS_IN_DAY = 86400;

    function _getTotalCollateral(uint256 borrowAmount) internal view returns (uint256, uint256) {
        uint256 intrinsicMinimumValue = IModelHelper(_v.modelHelper).getIntrinsicMinimumValue(address(this));
        return (DecimalMath.divideDecimal(borrowAmount, intrinsicMinimumValue), intrinsicMinimumValue);
    }

    function calculateLoanFees(uint256 borrowAmount, uint256 duration) public pure returns (uint256 fees) {
        uint256 percentage = 27; // 0.027% 
        uint256 scaledPercentage = percentage * 10**12; 
        fees = (borrowAmount * scaledPercentage * (duration / SECONDS_IN_DAY)) / (100 * 10**18);
    }    

    function borrowFromFloor(address who, uint256 borrowAmount, uint256 duration) public onlyVault {
        if (borrowAmount == 0) revert InsufficientLoanAmount(); 
        
        (uint256 collateralAmount,) = _getTotalCollateral(borrowAmount);
        if (collateralAmount == 0) revert InsufficientCollateral();

        (,,, uint256 floorToken1Balance) = IModelHelper(_v.modelHelper)
        .getUnderlyingBalances(address(_v.pool), address(this), LiquidityType.Floor);

        if (floorToken1Balance < borrowAmount) revert InsufficientFloorBalance();

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
        
        IModelHelper(_v.modelHelper)
        .enforceSolvencyInvariant(address(this));           
    }

    function paybackLoan(address who) public onlyVault {
        LoanPosition storage loan = _v.loanPositions[who];

        if (loan.borrowAmount == 0) revert NoActiveLoan();

        IERC20(_v.pool.token1()).transferFrom(who, address(this), loan.borrowAmount);
        IERC20(_v.pool.token0()).transfer(who, loan.collateralAmount);

        delete _v.loanPositions[who];
        _removeLoanAddress(who);
    }

    function rollLoan(address who) public onlyVault {
        LoanPosition storage loan = _v.loanPositions[who];

        if (loan.borrowAmount == 0) revert NoActiveLoan();
        if (block.timestamp > loan.expiry) revert LoanExpired();

        uint256 newCollateralValue = DecimalMath.multiplyDecimal(
            loan.collateralAmount, 
            IModelHelper(_v.modelHelper).getIntrinsicMinimumValue(address(this))
        );

        if (newCollateralValue <= loan.borrowAmount) revert CantRollLoan();

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
        IVault(address(this)).updatePositions([_v.floorPosition, _v.anchorPosition, _v.discoveryPosition]);

        // enforce insolvency invariant
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

    function updatePositions(LiquidityPosition[3] memory _positions) public onlyInternalCalls {
        if (!_v.initialized) revert NotInitialized();             
        if (_positions[0].liquidity == 0 || _positions[1].liquidity == 0 || _positions[2].liquidity == 0) revert NoLiquidity();
        
        _updatePositions(_positions);
    }
    
    function _updatePositions(LiquidityPosition[3] memory _positions) internal {   
        _v.floorPosition = _positions[0];
        _v.anchorPosition = _positions[1];
        _v.discoveryPosition = _positions[2];
    }

    function getPositions() public view
    returns (LiquidityPosition[3] memory positions) {
        positions = [
            _v.floorPosition, 
            _v.anchorPosition, 
            _v.discoveryPosition
        ];
    }

    function teamMultiSig() public view returns (address) {
        return INomaFactory(_v.factory).teamMultiSig();
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

    modifier onlyVault() {
        if (msg.sender != address(this)) revert OnlyVault();
        _;
    }

    function getFunctionSelectors() external pure override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = bytes4(keccak256(bytes("borrowFromFloor(address,uint256,uint256)")));    
        selectors[1] = bytes4(keccak256(bytes("paybackLoan(address)")));
        selectors[2] = bytes4(keccak256(bytes("rollLoan(address)")));
        selectors[3] = bytes4(keccak256(bytes("defaultLoans()")));
        selectors[4] = bytes4(keccak256(bytes("updatePositions((int24,int24,uint128,uint256)[3])")));
        selectors[5] = bytes4(keccak256(bytes("getPositions()")));
        selectors[6] = bytes4(keccak256(bytes("teamMultiSig()")));
        selectors[7] = bytes4(keccak256(bytes("getLiquidityStructureParameters()")));  
        selectors[8] = bytes4(keccak256(bytes("setFees(uint256,uint256)")));
        return selectors;
    }
}
