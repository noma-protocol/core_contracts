// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
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
    ProtocolParameters
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
error InvalidDuration();
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
        uint256 intrinsicMinimumValue = IModelHelper(modelHelper()).getIntrinsicMinimumValue(address(this));
        return (DecimalMath.divideDecimal(borrowAmount, intrinsicMinimumValue), intrinsicMinimumValue);
    }

    function _calculateLoanFees(uint256 borrowAmount, uint256 duration) internal view returns (uint256 fees) {
        uint256 percentage = _v.loanFee; // e.g. 27 --> 0.027% 
        uint256 scaledPercentage = percentage * 10**12; 
        fees = (borrowAmount * scaledPercentage * (duration / SECONDS_IN_DAY)) / (100 * 10**18);
    }    

    function borrowFromFloor(address who, uint256 borrowAmount, uint256 duration) public onlyInternalCalls {
        if (borrowAmount == 0) revert InsufficientLoanAmount();
        if (duration < 30 days || duration > 365 days) revert InvalidDuration();

        (uint256 collateralAmount,) = _getTotalCollateral(borrowAmount);
        if (collateralAmount == 0) revert InsufficientCollateral();

        (,,, uint256 floorToken1Balance) = IModelHelper(modelHelper())
        .getUnderlyingBalances(address(_v.pool), address(this), LiquidityType.Floor);

        if (floorToken1Balance < borrowAmount) revert InsufficientFloorBalance();

        IERC20(_v.pool.token0()).transferFrom(who, address(this), collateralAmount);  
        uint256 loanFees = _calculateLoanFees(borrowAmount, duration);

        _v.collateralAmount += collateralAmount;
        
        LiquidityPosition[3] memory positions = [_v.floorPosition, _v.anchorPosition, _v.discoveryPosition];

        Uniswap.collect(address(_v.pool), address(this), _v.floorPosition.lowerTick, _v.floorPosition.upperTick);         
        LiquidityDeployer.reDeployFloor(address(_v.pool), floorToken1Balance - borrowAmount, positions);
        
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
        
        IModelHelper(modelHelper())
        .enforceSolvencyInvariant(address(this));           
    }

    function paybackLoan(address who) public onlyInternalCalls {
        LoanPosition storage loan = _v.loanPositions[who];

        if (loan.borrowAmount == 0) revert NoActiveLoan();

        IERC20(_v.pool.token1()).transferFrom(who, address(this), loan.borrowAmount);
        IERC20(_v.pool.token0()).transfer(who, loan.collateralAmount);

        delete _v.loanPositions[who];
        _removeLoanAddress(who);
    }

    function rollLoan(address who) public onlyInternalCalls {
        LoanPosition storage loan = _v.loanPositions[who];

        if (loan.borrowAmount == 0) revert NoActiveLoan();
        if (block.timestamp > loan.expiry) revert LoanExpired();

        uint256 newCollateralValue = DecimalMath.multiplyDecimal(
            loan.collateralAmount, 
            IModelHelper(modelHelper()).getIntrinsicMinimumValue(address(this))
        );

        if (newCollateralValue <= loan.borrowAmount) revert CantRollLoan();

        uint256 newBorrowAmount = newCollateralValue - loan.borrowAmount;
        uint256 newFees = _calculateLoanFees(newBorrowAmount, loan.expiry - block.timestamp);

        (,,, uint256 floorToken1Balance) = IModelHelper(modelHelper())
        .getUnderlyingBalances(address(_v.pool), address(this), LiquidityType.Floor);

        LiquidityPosition[3] memory positions = [_v.floorPosition, _v.anchorPosition, _v.discoveryPosition];
        Uniswap.collect(address(_v.pool), address(this), _v.floorPosition.lowerTick, _v.floorPosition.upperTick);      
           
        LiquidityDeployer.reDeployFloor(
            address(_v.pool), 
            floorToken1Balance - newBorrowAmount, 
            positions
        );

        IERC20(_v.pool.token1()).transfer(who, newBorrowAmount - newFees);     
        IVault(address(this)).updatePositions([_v.floorPosition, _v.anchorPosition, _v.discoveryPosition]);

        // enforce insolvency invariant
    }

    function defaultLoans() public onlyInternalCalls {
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

    function mintTokens(
        address to,
        uint256 amount
    ) public onlyInternalCalls {
        
        _v.timeLastMinted = block.timestamp;

        INomaFactory(_v.factory)
        .mintTokens(
            to,
            amount
        );
    }

    function burnTokens(
        uint256 amount
    ) public onlyInternalCalls {

        IERC20(_v.pool.token0()).approve(address(_v.factory), amount);
        INomaFactory(_v.factory)
        .burnFor(
            address(this),
            amount
        );
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

    function getProtocolParameters() public view returns 
    (ProtocolParameters memory ) {
        return _v.protocolParameters;
    }

    function getTimeSinceLastMint() public view returns (uint256) {
        return block.timestamp - _v.timeLastMinted;
    }

    function getCollateralAmount() public view returns (uint256) {
        return _v.collateralAmount;
    }

    function pool() public view returns (IUniswapV3Pool) {
        return _v.pool;
    }

    function getAccumulatedFees() public view returns (uint256, uint256) {
        return (_v.feesAccumulatorToken0, _v.feesAccumulatorToken1);
    }

    modifier onlyVault() {
        if (msg.sender != address(this)) revert OnlyVault();
        _;
    }

    function getFunctionSelectors() external pure override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = bytes4(keccak256(bytes("borrowFromFloor(address,uint256,uint256)")));    
        selectors[1] = bytes4(keccak256(bytes("paybackLoan(address)")));
        selectors[2] = bytes4(keccak256(bytes("rollLoan(address)")));
        selectors[3] = bytes4(keccak256(bytes("defaultLoans()")));
        selectors[4] = bytes4(keccak256(bytes("updatePositions((int24,int24,uint128,uint256,int24)[3])")));
        selectors[5] = bytes4(keccak256(bytes("getPositions()")));
        selectors[6] = bytes4(keccak256(bytes("teamMultiSig()")));
        selectors[7] = bytes4(keccak256(bytes("getProtocolParameters()")));  
        selectors[8] = bytes4(keccak256(bytes("getTimeSinceLastMint()")));
        selectors[9] = bytes4(keccak256(bytes("getCollateralAmount()")));
        selectors[10] = bytes4(keccak256(bytes("mintTokens(address,uint256)")));
        selectors[11] = bytes4(keccak256(bytes("burnTokens(uint256)")));
        selectors[12] = bytes4(keccak256(bytes("pool()")));
        return selectors;
    }
}
