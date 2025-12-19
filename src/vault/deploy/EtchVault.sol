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
import "../../errors/Errors.sol";

/**
 * @title EtchVault
 * @notice A contract for deploying and initializing a Diamond proxy vault.
 * @dev This contract is responsible for deploying the Diamond proxy, adding facets, and initializing the vault.
 */
contract EtchVault {

    // State variables
    Diamond diamond; // The Diamond proxy contract.
    DiamondCutFacet dCutFacet; // The DiamondCutFacet contract.
    OwnershipFacet ownerF; // The OwnershipFacet contract.
    DiamondInit dInit; // The DiamondInit contract.
    
    address private immutable factory; // The address of the factory contract.
    IAddressResolver private resolver; // The address resolver contract.

    /**
     * @notice Constructor to initialize the EtchVault contract.
     * @param _factory The address of the factory contract.
     * @param _resolver The address of the resolver contract.
     */
    constructor(
        address _factory,
        address _resolver 
    ) {
        factory = _factory;
        resolver = IAddressResolver(_resolver);
    }

    /**
     * @notice Pre-deploys a vault by deploying the Diamond proxy, adding facets, and initializing it.
     * @param _resolver The address of the resolver contract.
     * @return vault The address of the deployed Diamond proxy.
     * @return vaultUpgrade The address of the vault upgrade contract.
     */
    function preDeployVault(
        address _resolver
    )
        public
        onlyFactory
        returns (address vault, address vaultUpgrade)
    {
        // Deploy facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(dCutFacet));
        ownerF = new OwnershipFacet();
        dInit = new DiamondInit();

        // Build cut struct
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
            Utils.stringToBytes32("VaultStep1"), 
            "no VaultUpgrade"
        );

        // Upgrade diamond
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");
        IDiamond(address(diamond)).transferOwnership(vaultUpgrade);
            
        // Initialization
        DiamondInit(address(diamond)).init(_resolver);
        vault = address(diamond);

        return (vault, vaultUpgrade);
    }
    
    /**
     * @notice Modifier to restrict access to the factory contract.
     */
    modifier onlyFactory() {
        if (msg.sender != factory) revert OnlyFactory();
        _;
    }
}