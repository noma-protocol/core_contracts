
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Diamond } from "../../Diamond.sol";
import { DiamondInit } from "../../init/DiamondInit.sol";
import { OwnershipFacet } from "../../facets/OwnershipFacet.sol";
import { DiamondCutFacet } from "../../facets/DiamondCutFacet.sol";
import { IDiamondCut } from "../../interfaces/IDiamondCut.sol";
import { IFacet } from "../../interfaces/IFacet.sol";
import { IDiamond } from "../../interfaces/IDiamond.sol";
import { Utils } from "../../libraries/Utils.sol";
import { IAddressResolver } from "../../interfaces/IAddressResolver.sol";

contract EtchVault {

    Diamond diamond;
    DiamondCutFacet dCutFacet;
    OwnershipFacet ownerF;
    DiamondInit dInit;
    
    address private immutable factory;
    IAddressResolver private resolver;

    constructor(
        address _factory,
        address _resolver 
    ) {
        factory = _factory;
        resolver = IAddressResolver(_resolver);
    }

    function preDeployVault(
        address _resolver
    )
        public
        onlyFactory
        returns (address vault, address vaultUpgrade)
    {
        //deploy facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(dCutFacet));
        ownerF = new OwnershipFacet();
        dInit = new DiamondInit();

        //build cut struct
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](3);

        cut[0] = (
            IDiamondCut.FacetCut({
                facetAddress: address(ownerF),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: IFacet(
                    address(ownerF)
                ).getFunctionSelectors()
            })
        );

        cut[1] = (
            IDiamondCut.FacetCut({
                facetAddress: address(dInit),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: IFacet(address(dInit)).getFunctionSelectors()
            })
        );

        cut[2] = (
            IDiamondCut.FacetCut({
                facetAddress: address(dCutFacet),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: IFacet(address(dCutFacet)).getFunctionSelectors()
            })
        );

        vaultUpgrade = resolver
        .requireAndGetAddress(
            Utils.stringToBytes32("VaultUpgrade"), 
            "no VaultUpgrade"
        );

        //upgrade diamond
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");
        IDiamond(address(diamond)).transferOwnership(vaultUpgrade);
            
        //Initialization
        DiamondInit(address(diamond)).init(_resolver);
        vault = address(diamond);

        return (vault, vaultUpgrade);
    }
    

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

}