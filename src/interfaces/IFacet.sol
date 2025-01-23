// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFacet
 * @notice Interface for retrieving function selectors from a facet in a modular contract system.
 */
interface IFacet {
    /**
     * @notice Retrieves the list of function selectors provided by this facet.
     * @return An array of bytes4 function selectors.
     * @dev This function is used to query which functions are supported by this facet.
     */
    function getFunctionSelectors() external returns (bytes4[] memory);
}
