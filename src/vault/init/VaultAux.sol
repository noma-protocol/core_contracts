// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AuxVault } from "../AuxVault.sol";

import { IDiamondCut } from "../../interfaces/IDiamondCut.sol";
import { IFacet } from "../../interfaces/IFacet.sol";

interface IDiamondInterface {
    function initialize() external;
    function transferOwnership(address) external;
}

/**
 * @title IVaultUpgrader
 * @notice Interface for the VaultUpgrader contract.
 */
interface IVaultUpgrader {
    function doUpgradeStart(address diamond, address _vaultUpgradeFinalize) external;
    function doUpgradeStep1(address diamond) external;
    function doUpgradeStep2(address diamond) external;
    function doUpgradeFinalize(address diamond) external;
}

/**
 * @title VaultFinalize
 * @notice A contract for finalizing the upgrade of a Diamond proxy vault.
 * @dev This contract is responsible for adding new facets to the Diamond proxy and transferring ownership to the final authority.
 */
contract VaultAux  {
    // State variables
    address private owner; // The address of the contract owner.
    address private finalAuthority; // The address of the final authority.
    address private upgradePreviousStep; // The address of the previous upgrade step contract.
    address private upgradeNextStep; // The address of the previous upgrade step contract.

    /**
     * @notice Constructor to initialize the VaultFinalize contract.
     * @param _owner The address of the contract owner.
     */
    constructor(address _owner) {
        owner = _owner;
    }

    /**
     * @notice Initializes the contract with the final authority and the previous upgrade step contract.
     * @param _someContract The address of the final authority.
     * @param _upgradePreviousStep The address of the previous upgrade step contract.
     */
    function init(
        address _someContract, 
        address _upgradePreviousStep,
        address _upgradeNextStep
        ) onlyOwner public {
        require(_upgradePreviousStep != address(0), "Invalid address");
        finalAuthority = _someContract;
        upgradePreviousStep = _upgradePreviousStep;
        upgradeNextStep = _upgradeNextStep;
    }
 
    /**
     * @notice Finalizes the upgrade of the Diamond proxy by adding new facets and transferring ownership.
     * @param diamond The address of the Diamond proxy contract.
     */
    function doUpgradeFinalize(address diamond) public authorized {
 
        address[] memory newFacets = new address[](1);
        IDiamondCut.FacetCutAction[] memory actions = new IDiamondCut.FacetCutAction[](1);
        bytes4[][] memory functionSelectors = new bytes4[][](1);

        newFacets[0] = address(new AuxVault());
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
        IDiamondInterface(diamond).transferOwnership(upgradeNextStep);
        IVaultUpgrader(upgradeNextStep).doUpgradeFinalize(diamond);
    }  

    /**
     * @notice Modifier to restrict access to the contract owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    /**
     * @notice Modifier to restrict access to the previous upgrade step contract.
     */
    modifier authorized() {
        require(msg.sender == upgradePreviousStep, "Only UpgradePreviousStep");
        _;
    }
}