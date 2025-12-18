// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    LiquidityPosition, 
    ProtocolAddresses
} from "../types/Types.sol";

import { IVault } from "../interfaces/IVault.sol";
import { IAddressResolver } from "../interfaces/IAddressResolver.sol";
import { VaultStorage } from "../libraries/LibAppStorage.sol";
import { LiquidityOps } from "../libraries/LiquidityOps.sol";
import "../errors/Errors.sol";

interface IStakingVault {
    function mintAndDistributeRewards(address caller, ProtocolAddresses memory addresses) external;
}

interface ILendingVault {
    function borrowFromFloor(address who, uint256 borrowAmount, uint256 duration) external;
    function paybackLoan(address who, uint256 amount, bool isSelfRepaying) external;
    function rollLoan(address who, uint256 newDuration) external returns (uint256 amount);
    function addCollateral(address who, uint256 amount) external;
    function vaultSelfRepayLoans(uint256 fundsToPull,uint256 start,uint256 limit) external returns (uint256 totalLoans, uint256 collateralToReturn);
}

interface ILiquidationVault {
    function vaultDefaultLoans() external returns (uint256 totalBurned, uint256 loansDefaulted);
    function vaultDefaultLoansRange(uint256 start, uint256 limit) external returns (uint256 totalBurned, uint256 loansDefaulted);
}

// Events
event Borrow(address indexed who, uint256 borrowAmount, uint256 duration);
event Payback(address indexed who, uint256 amount);
event RollLoan(address indexed who, uint256 amount, uint256 newDuration);
event DefaultLoans(uint256 totalBurned, uint256 loansDefaulted);

event Shift();
event Slide();

/**
 * @title ExtVault
 * @notice A contract for vault external facing functions. // TODO MAKE public?
 * @dev n/a.
 */
contract ExtVault {
    VaultStorage internal _v;

    /**
     * @notice Allows a user to borrow tokens from the vault's floor liquidity.
     * @param borrowAmount The amount of tokens to borrow.
     * @param duration The duration of the loan.
     */
    function borrow(
        uint256 borrowAmount,
        uint256 duration
    ) public {

        ILendingVault(address(this))
        .borrowFromFloor(
            msg.sender,
            borrowAmount,
            duration
        );

        emit Borrow(msg.sender, borrowAmount, duration);
    }

    /**
     * @notice Allows a user to pay back a loan.
     */
    function payback(uint256 amount) public  {

        ILendingVault(address(this))
        .paybackLoan(msg.sender, amount, false);

        emit Payback(msg.sender, amount);
    }

    /**
     * @notice Allows a user to roll over a loan.
     */
    function roll(
        uint256 newDuration
    ) public  {
        
        uint256 amount = 
        ILendingVault(address(this))
        .rollLoan(
            msg.sender,
            newDuration
        );

        emit RollLoan(msg.sender, amount, newDuration);
    }

    /**
     * @notice Allows a user to add collateral to their loan.
     * @param amount The amount of collateral to add.
     */
    function addCollateral(
        uint256 amount
    ) public  {

        ILendingVault(address(this))
        .addCollateral(msg.sender, amount);
    }

    /**
     * @notice Shifts the liquidity positions in the vault.
     * @dev This function adjusts the liquidity positions and distributes staking rewards.
     * @dev It also pays rewards to the caller.
     */
    function shift() public {

        LiquidityPosition[3] memory positions = 
        IVault(address(this))
        .getPositions();

        ProtocolAddresses memory addresses = 
        IVault(address(this))
        .getProtocolAddresses();

        LiquidityOps.shift(
            addresses,
            positions
        );

        if (_v.isStakingSetup) {
            IStakingVault(address(this))
            .mintAndDistributeRewards(msg.sender, addresses);
        }
        
        emit Shift();
    }    

    /**
     * @notice Slides the liquidity positions in the vault.
     * @dev This function adjusts the liquidity positions without distributing staking rewards.
     */
    function slide() public {

        LiquidityPosition[3] memory positions = 
        IVault(address(this))
        .getPositions();

        ProtocolAddresses memory addresses = 
        IVault(address(this))
        .getProtocolAddresses();

        LiquidityOps.slide(
            addresses,
            positions
        );

        emit Slide();
    }

    /**
     * @notice Allows anybody to default expired loans.
     */
    function defaultLoans(uint256 start, uint256 limit) public {
        uint256 totalBurned = 0;
        uint256 loansDefaulted = 0;

        if (start == 0 && limit == 0) {
            (totalBurned, loansDefaulted) = 
            ILiquidationVault(address(this))
            .vaultDefaultLoans();
        } else {
            (totalBurned, loansDefaulted) = 
            ILiquidationVault(address(this))
            .vaultDefaultLoansRange(start, limit);            
        }

        emit DefaultLoans(totalBurned, loansDefaulted);
    }

    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
    function getFunctionSelectors() external pure  returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = bytes4(keccak256(bytes("shift()")));
        selectors[1] = bytes4(keccak256(bytes("slide()")));  
        selectors[2] = bytes4(keccak256(bytes("borrow(uint256,uint256)")));  
        selectors[3] = bytes4(keccak256(bytes("payback(uint256)")));
        selectors[4] = bytes4(keccak256(bytes("roll(uint256)")));  
        selectors[5] = bytes4(keccak256(bytes("addCollateral(uint256)")));      
        selectors[6] = bytes4(keccak256(bytes("defaultLoans()")));      
        selectors[7] = bytes4(keccak256(bytes("defaultLoans(uint256,uint256)"))); 
        selectors[8] = bytes4(keccak256(bytes("selfRepayLoans(uint256,uint256,uint256)"))); 
        return selectors;
    }
}