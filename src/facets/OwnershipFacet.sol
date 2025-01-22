// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IERC173} from "../interfaces/IERC173.sol";

/**
 * @title OwnershipFacet
 * @dev This contract provides ownership management functionalities for the Diamond Standard.
 * It allows for transferring ownership and retrieving the current owner's address.
 */
contract OwnershipFacet is IERC173 {
    /**
     * @notice Transfers ownership of the contract to a new address.
     * @dev Calls the internal function to enforce that the caller is the current contract owner,
     *      and then sets the new owner address.
     * @param _newOwner The address of the new owner.
     */
    function transferOwnership(address _newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setContractOwner(_newOwner);
    }

    /**
     * @notice Retrieves the address of the current contract owner.
     * @return owner_ The address of the current owner.
     */
    function owner() external view override returns (address owner_) {
        owner_ = LibDiamond.contractOwner();
    }

    /**
     * @notice Provides the function selectors associated with ownership management.
     * @dev This function returns an array of function selectors for the `owner` and `transferOwnership` functions.
     * @return selectors An array of bytes4 function selectors.
     */
    function getFunctionSelectors() external pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("owner()"));
        selectors[1] = bytes4(keccak256("transferOwnership(address)"));
        // Add more selectors if there are additional functions.
    }
}
