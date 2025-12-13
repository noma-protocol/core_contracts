// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { BaseVault } from "../BaseVault.sol";

import { IDiamondCut } from "../../interfaces/IDiamondCut.sol";
import { IFacet } from "../../interfaces/IFacet.sol";
import { Utils } from "../../libraries/Utils.sol";

/**
 * @title IDiamondInterface
 * @notice Interface for the Diamond proxy contract.
 */
interface IDiamondInterface {
    function initialize() external;
    function transferOwnership(address) external;
}

/**
 * @title IVaultUpgrader
 * @notice Interface for the VaultUpgrader contract.
 */
interface IVaultUpgrader {
    function doUpgradeStart(address diamond) external;
    function doUpgradeStep1(address diamond) external;
    function doUpgradeStep2(address diamond) external;
    function doUpgradeStep3(address diamond) external;
    function doUpgradeStep4(address diamond) external;
    function doUpgradeFinalize(address diamond) external;
    function doUpgradeFinish(address diamond) external;
}

contract VaultInit {
    address private owner; // The address of the contract owner.
    address private factory; // The address of the factory contract.

    error OnlyFactory();
    error InvalidAddress();

    /**
     * @notice Constructor to initialize the VaultUpgrade contract.
     * @param _owner The address of the contract owner.
     * @param _factory The address of the factory contract.
     */
    constructor(address _owner, address _factory) {
        owner = _owner;
        factory = _factory;
    }

    /**
     * @notice Starts the upgrade process by adding the BaseVault facet and initiating the next upgrade step.
     * @param diamond The address of the Diamond proxy contract.
     */
    function doUpgradeStart(address diamond) public onlyFactory {
        if (diamond == address(0) ) {
            revert InvalidAddress();
        }

        address[] memory newFacets = new address[](1);
        IDiamondCut.FacetCutAction[] memory actions = new IDiamondCut.FacetCutAction[](1);
        bytes4[][] memory functionSelectors = new bytes4[][](1);

        newFacets[0] = address(new BaseVault());
        actions[0] = IDiamondCut.FacetCutAction.Add;
        functionSelectors[0] = IFacet(newFacets[0]).getFunctionSelectors();

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](newFacets.length);
        for (uint256 i = 0; i < newFacets.length; i++) {
            cuts[i] = IDiamondCut.FacetCut({
                facetAddress: newFacets[i],
                action: actions[i],
                functionSelectors: functionSelectors[i]
            });
        }

        IDiamondCut(diamond).diamondCut(cuts, address(0), "");

        // Pass the ownership to factory for further upgrade operations
        IDiamondInterface(diamond).transferOwnership(factory);

    }  

    /**
     * @notice Modifier to restrict access to the factory contract.
     */
    modifier onlyFactory() {
        if (msg.sender != factory) {
            revert OnlyFactory();
        }
        _;
    }
}