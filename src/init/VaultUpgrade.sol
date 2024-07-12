// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseVault} from "../vault/BaseVault.sol";
import {ExtVault} from "../vault/ExtVault.sol"; 
import {StakingVault} from "../vault/StakingVault.sol"; 
import {LendingVault} from "../vault/LendingVault.sol"; 

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {IDiamond} from "../interfaces/IDiamond.sol";
import "../libraries/Utils.sol";

interface IVaultUpgrader {
    function doUpgradeStart(address diamond, address _vaultUpgradeFinalize) external;
    function doUpgradeStep1(address diamond) external;
    function doUpgradeStep2(address diamond) external;
    // function doUpgradeStep3(address diamond) external;
    function doUpgradeFinalize(address diamond) external;
}

interface IDiamondInterface {
    function initialize() external;
    function transferOwnership(address) external;
}

contract VaultUpgrade {
    address public owner;
    address public someContract;
    address public factory;
    address public upgradeStep1;
    address public upgradeFinalize;

    constructor(address _owner, address _factory) {
        owner = _owner;
        factory = _factory;
    }

    function init(address _someContract, address _upgradeStep1) onlyOwner public {
        require(_upgradeStep1 != address(0), "Invalid address");
        someContract = _someContract;
        upgradeStep1 = _upgradeStep1;
    }

    function doUpgradeStart(address diamond, address _vaultUpgradeFinalize) public onlyFactory {
        require(_vaultUpgradeFinalize != address(0), "Invalid upgrade address");

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

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyFactory() {
        // require(msg.sender == someContract, "Only factory");
        if (msg.sender != factory) {
            revert(
                string(
                    abi.encodePacked(
                        "onlyFactory : ", 
                        Utils.addressToString(someContract)
                    )
                )
            );
        }
        _;
    }
}
contract VaultUpgradeStep1  {
    address public owner;
    address public upgradePreviousStep;
    address public upgradeNextStep;
    constructor(address _owner) {
        owner = _owner;
    }

    function init(address _upgradeNextStep, address _upgradePreviousStep) onlyOwner public {
        require(_upgradePreviousStep != address(0), "Invalid address");
        upgradePreviousStep = _upgradePreviousStep;
        upgradeNextStep = _upgradeNextStep;
    }

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

        address lastOwner = IDiamond(diamond).owner();

        IDiamondCut(diamond).diamondCut(cuts, address(0), "");
        IDiamondInterface(diamond).transferOwnership(upgradeNextStep);
        IVaultUpgrader(upgradeNextStep).doUpgradeStep2(diamond);
    }  

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier authorized() {
        require(msg.sender == upgradePreviousStep, "Only UpgradePreviousStep");
        _;
    }

}

contract VaultUpgradeStep2  {
    address public owner;
    address public upgradePreviousStep;
    address public upgradeNextStep;
    constructor(address _owner) {
        owner = _owner;
    }

    function init(address _upgradeNextStep, address _upgradePreviousStep) onlyOwner public {
        require(_upgradePreviousStep != address(0), "Invalid address");
        upgradePreviousStep = _upgradePreviousStep;
        upgradeNextStep = _upgradeNextStep;
        
    }

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

        address lastOwner = IDiamond(diamond).owner();

        IDiamondCut(diamond).diamondCut(cuts, address(0), "");
        IDiamondInterface(diamond).transferOwnership(upgradeNextStep);
        IVaultUpgrader(upgradeNextStep).doUpgradeFinalize(diamond);
    }  

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier authorized() {
        require(msg.sender == upgradePreviousStep, "Only UpgradePreviousStep");
        _;
    }

}

contract VaultUpgradeFinalize  {
    address public owner;
    address public someContract;
    address public upgradePreviousStep;
    constructor(address _owner) {
        owner = _owner;
    }

    function init(address _someContract, address _upgradePreviousStep) onlyOwner public {
        require(_upgradePreviousStep != address(0), "Invalid address");
        someContract = _someContract;
        upgradePreviousStep = _upgradePreviousStep;
    }

    function doUpgradeFinalize(address diamond) public  {
 
        address[] memory newFacets = new address[](1);
        IDiamondCut.FacetCutAction[] memory actions = new IDiamondCut.FacetCutAction[](1);
        bytes4[][] memory functionSelectors = new bytes4[][](1);

        newFacets[0] = address(new ExtVault());
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

        address lastOwner = IDiamond(diamond).owner();

        IDiamondCut(diamond).diamondCut(cuts, address(0), "");
        IDiamondInterface(diamond).transferOwnership(someContract);
    }  

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier authorized() {
        require(msg.sender == upgradePreviousStep, "Only UpgradePreviousStep");
        _;
    }

}