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
import "../types/Errors.sol";

contract DiamondInit {
    bytes32 private constant DIAMOND_INIT_STORAGE_POSITION = keccak256("noma.money.diamond.init.storage");

    struct DiamondInitStorage {
        bool initialized;
    }

    function _diamondInitStorage() private pure returns (DiamondInitStorage storage ds) {
        bytes32 position = DIAMOND_INIT_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

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
        _diamondInitStorage().initialized = true;
    }
    
    modifier notInitialized() {
        if (_diamondInitStorage().initialized) {
            revert InitError(0); // already initialized
        }
        _;
    }

    function getFunctionSelectors() external pure virtual returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256(bytes("init(address)")));
        return selectors;
    }
}
