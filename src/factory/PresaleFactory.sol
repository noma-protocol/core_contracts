// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Presale} from "../bootstrap/Presale.sol";
import {IAddressResolver} from "../interfaces/IAddressResolver.sol";
import {PresaleDeployParams, PresaleProtocolParams} from "../types/Types.sol";

contract PresaleFactory {

    IAddressResolver private resolver;

    constructor(address _resolver) {
        resolver = IAddressResolver(_resolver);
    }

    function createPresale(
        PresaleDeployParams memory params,
        PresaleProtocolParams memory protocolParams
        
    ) external onlyFactory returns (address) {

        Presale presale = new Presale(
            params,
            protocolParams
        );

        return address(presale);
    }

    function factory() public view returns (address) {
        return  resolver.requireAndGetAddress(
            "OikosFactory",
            "No factory"
        );
    }

    modifier onlyFactory() {
        require(
            msg.sender == factory(),
            "Only factory allowed"
        );
        _;
    }
}