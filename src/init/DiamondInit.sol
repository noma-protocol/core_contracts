// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * \
 * Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
 * EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
 *
 * Implementation of a diamond.
 * /*****************************************************************************
 */
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IDiamondLoupe} from "../interfaces/IDiamondLoupe.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {IERC173} from "../interfaces/IERC173.sol";
import {IERC165} from "../interfaces/IERC165.sol";
import { Utils } from "../libraries/Utils.sol";
import { IAddressResolver } from "../interfaces/IAddressResolver.sol";

error AlreadyInitialized();
error InvalidResolver();
error NotAuthorized();

contract DiamondInit {

    address public owner;
    address public factory;
    bool public initialized;

    function init(address _resolver) external notInitialized {
        if (_resolver == address(0)) {
            revert InvalidResolver();
        }

        // adding ERC165 data
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;

        // Set resolver
        ds.resolver = _resolver;

        // Initialize flag
        initialized = true;
    }
    
    modifier notInitialized() {
        if (initialized == true) {
            revert AlreadyInitialized();
        }
        _;
    }

    function getFunctionSelectors() external pure virtual returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256(bytes("init(address)")));
        return selectors;
    }
}
