// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { BaseVault } from "../BaseVault.sol";
import { StakingVault } from "../StakingVault.sol"; 
import { LendingVault } from "../LendingVault.sol"; 
import { LiquidationVault } from "../LiquidationVault.sol";
import { LendingOpsVault } from "../LendingOpsVault.sol";
import { IDiamondCut } from "../../interfaces/IDiamondCut.sol";
import { IFacet } from "../../interfaces/IFacet.sol";
import { Utils } from "../../libraries/Utils.sol";

/**
 * @title IVaultUpgrader
 * @notice Interface for the VaultUpgrader contract.
 */
interface IVaultUpgrader {
    function doUpgradeStart(address diamond, address _vaultUpgradeFinalize) external;
    function doUpgradeStep1(address diamond) external;
    function doUpgradeStep2(address diamond) external;
    function doUpgradeStep3(address diamond) external;
    function doUpgradeStep4(address diamond) external;
    function doUpgradeFinalize(address diamond) external;
}

/**
 * @title IDiamondInterface
 * @notice Interface for the Diamond proxy contract.
 */
interface IDiamondInterface {
    function initialize() external;
    function transferOwnership(address) external;
}

error OnlyFactory();
error OnlyOwner();
error InvalidAddress();
error NotAuthorized();

/**
 * @title VaultUpgrade
 * @notice A contract for starting the upgrade process of a Diamond proxy vault.
 * @dev This contract is responsible for adding the BaseVault facet and initiating the upgrade process.
 */
contract VaultUpgrade {
    address private owner; // The address of the contract owner.
    address private factory; // The address of the factory contract.
    address private upgradeStep1; // The address of the first upgrade step contract.
    address private upgradeFinalize; // The address of the final upgrade step contract.


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
     * @notice Initializes the contract with the someContract and the first upgrade step contract.
     * @param _upgradeStep1 The address of the first upgrade step contract.
     */
    function init(address _upgradeStep1) onlyOwner public {
        if (_upgradeStep1 == address(0)) {
            revert InvalidAddress();
        }
        upgradeStep1 = _upgradeStep1;
    }

    /**
     * @notice Starts the upgrade process by adding the BaseVault facet and initiating the next upgrade step.
     * @param diamond The address of the Diamond proxy contract.
     * @param _vaultUpgradeFinalize The address of the final upgrade step contract.
     */
    function doUpgradeStart(address diamond, address _vaultUpgradeFinalize) public onlyFactory {
        if (diamond == address(0) || _vaultUpgradeFinalize == address(0)) {
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
        IDiamondInterface(diamond).transferOwnership(upgradeStep1);
        IVaultUpgrader(upgradeStep1).doUpgradeStep1(diamond);
    }     

    /**
     * @notice Modifier to restrict access to the contract owner.
     */
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
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

/**
 * @title VaultUpgradeStep1
 * @notice A contract for the first step of the upgrade process of a Diamond proxy vault.
 * @dev This contract is responsible for adding the StakingVault facet and initiating the next upgrade step.
 */
contract VaultUpgradeStep1  {
    address private owner; // The address of the contract owner.
    address private upgradePreviousStep; // The address of the previous upgrade step contract.
    address private upgradeNextStep; // The address of the next upgrade step contract.

    /**
     * @notice Constructor to initialize the VaultUpgradeStep1 contract.
     * @param _owner The address of the contract owner.
     */
    constructor(address _owner) {
        owner = _owner;
    }

    /**
     * @notice Initializes the contract with the next upgrade step contract and the previous upgrade step contract.
     * @param _upgradeNextStep The address of the next upgrade step contract.
     * @param _upgradePreviousStep The address of the previous upgrade step contract.
     */
    function init(address _upgradeNextStep, address _upgradePreviousStep) onlyOwner public {
        if (_upgradePreviousStep == address(0)) {
            revert InvalidAddress();
        }
        upgradePreviousStep = _upgradePreviousStep;
        upgradeNextStep = _upgradeNextStep;
    }

    /**
     * @notice Executes the first step of the upgrade process by adding the StakingVault facet and initiating the next upgrade step.
     * @param diamond The address of the Diamond proxy contract.
     */
    function doUpgradeStep1(address diamond) public authorized {
 
        address[] memory newFacets = new address[](1);
        IDiamondCut.FacetCutAction[] memory actions = new IDiamondCut.FacetCutAction[](1);
        bytes4[][] memory functionSelectors = new bytes4[][](1);

        newFacets[0] = address(new StakingVault());
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
        IVaultUpgrader(upgradeNextStep).doUpgradeStep2(diamond);
    }  

    /**
     * @notice Modifier to restrict access to the contract owner.
     */
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
    }

    /**
     * @notice Modifier to restrict access to the previous upgrade step contract.
     */
    modifier authorized() {
        if (msg.sender != upgradePreviousStep) {
            revert NotAuthorized();
        }
        _;
    }
}

/**
 * @title VaultUpgradeStep2
 * @notice A contract for the second step of the upgrade process of a Diamond proxy vault.
 * @dev This contract is responsible for adding the LendingVault facet and initiating the final upgrade step.
 */
contract VaultUpgradeStep2  {
    address private owner; // The address of the contract owner.
    address private upgradePreviousStep; // The address of the previous upgrade step contract.
    address private upgradeNextStep; // The address of the next upgrade step contract.
    
    /**
     * @notice Constructor to initialize the VaultUpgradeStep2 contract.
     * @param _owner The address of the contract owner.
     */
    constructor(address _owner) {
        owner = _owner;
    }

    /**
     * @notice Initializes the contract with the next upgrade step contract and the previous upgrade step contract.
     * @param _upgradeNextStep The address of the next upgrade step contract.
     * @param _upgradePreviousStep The address of the previous upgrade step contract.
     */
    function init(address _upgradeNextStep, address _upgradePreviousStep) onlyOwner public {
        require(_upgradePreviousStep != address(0), "Invalid address");
        upgradePreviousStep = _upgradePreviousStep;
        upgradeNextStep = _upgradeNextStep;
    }

    /**
     * @notice Executes the second step of the upgrade process by adding the LendingVault facet and initiating the final upgrade step.
     * @param diamond The address of the Diamond proxy contract.
     */
    function doUpgradeStep2(address diamond) public authorized  {
 
        address[] memory newFacets = new address[](1);
        IDiamondCut.FacetCutAction[] memory actions = new IDiamondCut.FacetCutAction[](1);
        bytes4[][] memory functionSelectors = new bytes4[][](1);

        newFacets[0] = address(new LendingVault());
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
        IVaultUpgrader(upgradeNextStep).doUpgradeStep3(diamond);
    }  

    /**
     * @notice Modifier to restrict access to the contract owner.
     */
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
    }

    /**
     * @notice Modifier to restrict access to the previous upgrade step contract.
     */
    modifier authorized() {
        if (msg.sender != upgradePreviousStep) {
            revert NotAuthorized();
        }
        _;
    }
}

/**
 * @title VaultUpgradeStep3
 * @notice A contract for the second step of the upgrade process of a Diamond proxy vault.
 * @dev This contract is responsible for adding the LendingVault facet and initiating the final upgrade step.
 */
contract VaultUpgradeStep3  {
    address private owner; // The address of the contract owner.
    address private upgradePreviousStep; // The address of the previous upgrade step contract.
    address private upgradeNextStep; // The address of the next upgrade step contract.
    
    /**
     * @notice Constructor to initialize the VaultUpgradeStep2 contract.
     * @param _owner The address of the contract owner.
     */
    constructor(address _owner) {
        owner = _owner;
    }

    /**
     * @notice Initializes the contract with the next upgrade step contract and the previous upgrade step contract.
     * @param _upgradeNextStep The address of the next upgrade step contract.
     * @param _upgradePreviousStep The address of the previous upgrade step contract.
     */
    function init(address _upgradeNextStep, address _upgradePreviousStep) onlyOwner public {
        require(_upgradePreviousStep != address(0), "Invalid address");
        upgradePreviousStep = _upgradePreviousStep;
        upgradeNextStep = _upgradeNextStep;
    }

    /**
     * @notice Executes the second step of the upgrade process by adding the LendingVault facet and initiating the final upgrade step.
     * @param diamond The address of the Diamond proxy contract.
     */
    function doUpgradeStep3(address diamond) public authorized  {
 
        address[] memory newFacets = new address[](1);
        IDiamondCut.FacetCutAction[] memory actions = new IDiamondCut.FacetCutAction[](1);
        bytes4[][] memory functionSelectors = new bytes4[][](1);

        newFacets[0] = address(new LiquidationVault());
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
        IVaultUpgrader(upgradeNextStep).doUpgradeStep4(diamond);

    }  

    /**
     * @notice Modifier to restrict access to the contract owner.
     */
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
    }

    /**
     * @notice Modifier to restrict access to the previous upgrade step contract.
     */
    modifier authorized() {
        if (msg.sender != upgradePreviousStep) {
            revert NotAuthorized();
        }
        _;
    }
}

/**
 * @title VaultUpgradeStep4
 * @notice A contract for the second step of the upgrade process of a Diamond proxy vault.
 * @dev This contract is responsible for adding the LendingVault facet and initiating the final upgrade step.
 */
contract VaultUpgradeStep4  {
    address private owner; // The address of the contract owner.
    address private upgradePreviousStep; // The address of the previous upgrade step contract.
    address private upgradeNextStep; // The address of the next upgrade step contract.
    
    /**
     * @notice Constructor to initialize the VaultUpgradeStep2 contract.
     * @param _owner The address of the contract owner.
     */
    constructor(address _owner) {
        owner = _owner;
    }

    /**
     * @notice Initializes the contract with the next upgrade step contract and the previous upgrade step contract.
     * @param _upgradeNextStep The address of the next upgrade step contract.
     * @param _upgradePreviousStep The address of the previous upgrade step contract.
     */
    function init(address _upgradeNextStep, address _upgradePreviousStep) onlyOwner public {
        require(_upgradePreviousStep != address(0), "Invalid address");
        upgradePreviousStep = _upgradePreviousStep;
        upgradeNextStep = _upgradeNextStep;
    }

    /**
     * @notice Executes the second step of the upgrade process by adding the LendingVault facet and initiating the final upgrade step.
     * @param diamond The address of the Diamond proxy contract.
     */
    function doUpgradeStep4(address diamond) public authorized  {
 
        address[] memory newFacets = new address[](1);
        IDiamondCut.FacetCutAction[] memory actions = new IDiamondCut.FacetCutAction[](1);
        bytes4[][] memory functionSelectors = new bytes4[][](1);

        newFacets[0] = address(new LendingOpsVault());
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
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
    }

    /**
     * @notice Modifier to restrict access to the previous upgrade step contract.
     */
    modifier authorized() {
        if (msg.sender != upgradePreviousStep) {
            revert NotAuthorized();
        }
        _;
    }
}