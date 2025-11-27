// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { VaultUpgradeLendingOps } from "../../../src/vault/upgrade/VaultUpgradeLendingOps.sol";
import { IDiamondCut } from "../../../src/interfaces/IDiamondCut.sol";
import { IFacet } from "../../../src/interfaces/IFacet.sol";


interface IDiamondInterface {
    function initialize() external;
    function transferOwnership(address) external;
}

contract VaultUpgradeLendingOpsExec {

    address private owner;
    address private factory;
    address private upgradeStep1;
    address private upgradeFinalize;
    
    constructor(address _owner, address _factory) {
        owner = _owner;
        factory = _factory;
    }

    function doUpgradeStart(address diamond) public onlyOwner {

        address[] memory newFacets = new address[](1);
        IDiamondCut.FacetCutAction[] memory actions = new IDiamondCut.FacetCutAction[](1);
        bytes4[][] memory functionSelectors = new bytes4[][](1);

        newFacets[0] = address(new VaultUpgradeLendingOps());
        actions[0] = IDiamondCut.FacetCutAction.Replace;
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
        IDiamondInterface(diamond).transferOwnership(factory);
    }     

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

}
