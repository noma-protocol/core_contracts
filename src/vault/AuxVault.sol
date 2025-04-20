// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { VaultStorage } from "../libraries/LibAppStorage.sol";
import { ProtocolParameters, LiquidityPosition } from "../types/Types.sol";
import { Utils } from "../libraries/Utils.sol";

interface IOikosFactory {
    function deferredDeploy(address deployer) external;
    function mintTokens(address to, uint256 amount) external;
    function burnFor(address from, uint256 amount) external;
    function teamMultiSig() external view returns (address);
}

error NotAuthorized();

/**
 * @title AuxVault
 * @notice A contract for vault auxiliary public functions.
 * @dev n/a.
 */
contract AuxVault {
    VaultStorage internal _v;

    /**
     * @notice Handles the post-presale actions.
     */
    function afterPresale() public  {
        if (msg.sender != _v.presaleContract) revert NotAuthorized();
        address deployer = _v.resolver.requireAndGetAddress(
            Utils.stringToBytes32("Deployer"), 
            "no Deployer"
        );
        IOikosFactory(
            _v.factory
        ).deferredDeploy(
            deployer
        );
    }

    function setProtocolParameters(
        ProtocolParameters memory protocolParameters
    ) public onlyManagerOrMultiSig {
        _v.protocolParameters = protocolParameters;
    }

    function setManager(address manager) public onlyManagerOrMultiSig {
        _v.manager = manager;
    }

    /**
     * @notice Retrieves the current liquidity positions.
     * @return positions The current liquidity positions.
     */
    function getPositions() public view
    returns (LiquidityPosition[3] memory positions) {
        positions = [
            _v.floorPosition, 
            _v.anchorPosition, 
            _v.discoveryPosition
        ];
    }

    /**
     * @notice Retrieves the time since the last mint operation.
     * @return The time since the last mint operation.
     */
    function getTimeSinceLastMint() public view returns (uint256) {
        return block.timestamp - _v.timeLastMinted;
    }

    /**
     * @notice Retrieves the address of the team multisig.
     * @return The address of the team multisig.
     */
    function teamMultiSig() public view returns (address) {
        return IOikosFactory(_v.factory).teamMultiSig();
    }

    /**
     * @notice Retrieves the protocol parameters.
     * @return The protocol parameters.
     */
    function getProtocolParameters() public view returns 
    (ProtocolParameters memory ) {
        return _v.protocolParameters;
    }

    /**
     * @notice Retrieves the Uniswap V3 pool contract.
     * @return The Uniswap V3 pool contract.
     */
    function pool() public view returns (IUniswapV3Pool) {
        return _v.pool;
    }

    /**
     * @notice Retrieves the accumulated fees.
     * @return The accumulated fees for token0 and token1.
     */
    function getAccumulatedFees() public view returns (uint256, uint256) {
        return (_v.feesAccumulatorToken0, _v.feesAccumulatorToken1);
    }

    /**
     * @notice Modifier to restrict access to the authorized manager.`
     */
    modifier authorized() {
        if (msg.sender != _v.manager) revert NotAuthorized();
        _;
    }

    modifier onlyManagerOrMultiSig() {
        if (msg.sender != _v.manager && msg.sender != IOikosFactory(_v.factory).teamMultiSig()) {
            revert NotAuthorized();
        }
        _;
    }

    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
    function getFunctionSelectors() external pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](9);

        selectors[0] = bytes4(keccak256(bytes("teamMultiSig()")));
        selectors[1] = bytes4(keccak256(bytes("getProtocolParameters()")));  
        selectors[2] = bytes4(keccak256(bytes("getTimeSinceLastMint()")));
        selectors[3] = bytes4(keccak256(bytes("getAccumulatedFees()")));
        selectors[4] = bytes4(keccak256(bytes("pool()")));
        selectors[5] = bytes4(keccak256(bytes("getPositions()")));
        selectors[6] = bytes4(keccak256(bytes("afterPresale()")));
        selectors[7] = bytes4(keccak256(bytes("setProtocolParameters((uint256,uint256,uint256,uint256,uint256,uint256))")));
        selectors[8] = bytes4(keccak256(bytes("setManager(address)")));

        return selectors;
    }
}