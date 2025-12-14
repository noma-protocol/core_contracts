// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { VaultStorage } from "../libraries/LibAppStorage.sol";
import { LoanPosition } from "../types/Types.sol";
import { Utils } from "../libraries/Utils.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "../interfaces/IVault.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ITokenRepo } from "../TokenRepo.sol";

error NotAuthorized();
error OnlyInternalCalls();

/**
 * @title AuxVault
 * @notice A contract for vault auxiliary public functions.
 * @dev n/a.
 */
contract LiquidationVault {
    using SafeERC20 for IERC20;

    VaultStorage internal _v;

    /**
     * @notice Defaults all expired loans and seizes the collateral.
     * @dev [M-01 FIX] Uses while loop to handle swap-and-pop correctly.
     *      When a loan is removed, the last element is swapped into position i,
     *      so we must NOT increment i to re-check the swapped element.
     */
    function vaultDefaultLoans() public onlyInternalCalls returns (uint256 totalBurned, uint256 loansDefaulted) {
        totalBurned = 0;
        loansDefaulted = 0;

        uint256 i = 0;
        while (i < _v.loanAddresses.length) {
            address who = _v.loanAddresses[i];
            LoanPosition storage loan = _v.loanPositions[who];

            if (block.timestamp > loan.expiry && loan.borrowAmount > 0) {
                loansDefaulted++;
                uint256 seized = _seizeCollateral(who);
                totalBurned += seized;
                delete _v.loanPositions[who];
                _removeLoanAddress(who);
                // Do NOT increment i - re-check the swapped-in entry at position i
            } else {
                unchecked { i++; }
            }
        }
    }

    function vaultDefaultLoansRange(uint256 start, uint256 limit)
        public
        onlyInternalCalls
        returns (uint256 totalBurned, uint256 loansDefaulted, uint256 nextIndex)
    {
        totalBurned = 0;
        loansDefaulted = 0;

        uint256 n = _v.loanAddresses.length;
        if (n == 0 || start >= n || limit == 0) {
            nextIndex = start;
            return (totalBurned, loansDefaulted, nextIndex);
        }

        uint256 i = start;
        uint256 processed = 0;

        while (processed < limit && i < _v.loanAddresses.length) {
            address who = _v.loanAddresses[i];
            LoanPosition storage loan = _v.loanPositions[who];

            if (block.timestamp > loan.expiry && loan.borrowAmount > 0) {
                loansDefaulted++;
                uint256 seized = _seizeCollateral(who);
                totalBurned += seized;

                delete _v.loanPositions[who];
                _removeLoanAddress(who);
                // do not increment i; re-check the swapped-in entry
            } else {
                unchecked { i++; }
            }

            processed++;
        }

        nextIndex = i;
    }

    /**
     * @notice Seizes the collateral of a borrower.
     * @param who The address of the borrower.
     */
    function _seizeCollateral(address who) internal returns (uint256) {
        LoanPosition storage loan = _v.loanPositions[who];
        _v.collateralAmount -= loan.collateralAmount;
        ITokenRepo(_v.tokenRepo).transferToRecipient(_v.pool.token0(), address(this), loan.collateralAmount);
        
        IVault(address(this))
        .burnTokens(
            loan.collateralAmount
        );

        return loan.collateralAmount;
    }

    /**
     * @notice Removes a borrower's address from the list of loan addresses.
     * @param who The address of the borrower.
     */
    function _removeLoanAddress(address who) internal {
        for (uint256 i = 0; i < _v.loanAddresses.length; i++) {
            if (_v.loanAddresses[i] == who) {
                _v.loanAddresses[i] = _v.loanAddresses[_v.loanAddresses.length - 1];
                _v.loanAddresses.pop();
                break;
            }
        }
    }

    /**
     * @notice Modifier to restrict access to internal calls.
     */
    modifier onlyInternalCalls() {
        if (msg.sender != _v.factory && msg.sender != address(this)) revert OnlyInternalCalls();
        _;        
    }

    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
    function getFunctionSelectors() external pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256(bytes("vaultDefaultLoans()")));
        selectors[1] = bytes4(keccak256(bytes("vaultDefaultLoansRange(uint256,uint256)")));
        return selectors;
    }
}        
