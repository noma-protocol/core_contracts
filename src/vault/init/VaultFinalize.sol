// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ExtVault } from "../ExtVault.sol"; 

import { IDiamondCut } from "../../interfaces/IDiamondCut.sol";
import { IFacet } from "../../interfaces/IFacet.sol";

interface IDiamondInterface {
    function initialize() external;
    function transferOwnership(address) external;
}

contract VaultFinalize  {
    address private owner;
    address private finalAuthority;
    address private upgradePreviousStep;
    
    constructor(address _owner) {
        owner = _owner;
    }

    function init(address _someContract, address _upgradePreviousStep) onlyOwner public {
        require(_upgradePreviousStep != address(0), "Invalid address");
        finalAuthority = _someContract;
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

        // address lastOwner = IDiamond(diamond).owner();

        IDiamondCut(diamond).diamondCut(cuts, address(0), "");
        IDiamondInterface(diamond).transferOwnership(finalAuthority);
    }  

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

}