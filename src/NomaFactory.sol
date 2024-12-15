
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ResolverStorage } from "./libraries/LibAppStorage.sol";
import { IAddressResolver } from "./interfaces/IAddressResolver.sol";

contract NomaFactory {
    ResolverStorage internal _r;


    /**
     * @notice Performs checks before deploying a new contract.
     * @param token Address of the token to be checked.
     */
    function _beforeDeploy(address token) internal view {
        bytes32 result;
        string memory symbol = IERC20Metadata(token).symbol();
        bytes memory symbol32 = bytes(symbol);

        if (symbol32.length == 0) {
            revert("IT");
        }

        assembly {
            result := mload(add(symbol, 32))
        }
        IAddressResolver(_r.resolver).requireAndGetAddress(result, "not a reserve token");
    }

}