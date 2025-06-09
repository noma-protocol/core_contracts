// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { OikosToken } from "../token/OikosToken.sol";
import { IAddressResolver } from "../interfaces/IAddressResolver.sol";

import {
    VaultDeployParams
} from "../types/Types.sol";

/**
 * @title IERC20
 * @notice Interface for the ERC20 standard token, including a mint function.
 */
interface IERC20 {
    /**
     * @notice Mints new tokens to a specified address.
     * @param to The address to receive the newly minted tokens.
     * @param amount The amount of tokens to be minted.
     */
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function totalSupply() external view returns (uint256);
}

error InvalidTokenAddressError();

contract TokenFactory {
    
    IAddressResolver public resolver;
    
    constructor(address _resolver) {
        resolver = IAddressResolver(_resolver);
    }

    function deployOikosToken(VaultDeployParams memory vaultDeployParams) public onlyFactory 
    returns (OikosToken, ERC1967Proxy, bytes32) {
        // Deploy the Noma token
        (
            OikosToken oikosToken, 
            ERC1967Proxy proxy, 
            bytes32 tokenHash
        ) = _deployOikosToken(
            vaultDeployParams.name,
            vaultDeployParams.symbol,
            vaultDeployParams.token1,
            vaultDeployParams.initialSupply,
            vaultDeployParams.maxTotalSupply
        );

        return (oikosToken, proxy, tokenHash);
    }

    /**
    * @notice Deploys a new Noma token with the specified parameters.
    * @param name The name of the token.
    * @param symbol The symbol of the token.
    * @param _token1 The address of the paired token (token1).
    * @param initialSupply The initial supply of the token.
    * @param maxTotalSupply The max total supply of the token.
    * @return oikosImpl The address of the newly deployed OikosToken.
    * @return proxy The address of the ERC1967Proxy for the OikosToken.
    * @return tokenHash The hash of the token, used for uniqueness.
    * @dev This internal function ensures the token does not already exist, generates a unique address using a salt, and initializes the token.
    * It reverts if the token address is invalid or if the token already exists.
    */
    function _deployOikosToken(
        string memory name,
        string memory symbol,
        address _token1,
        uint256 initialSupply,
        uint256 maxTotalSupply
    )
        internal
        returns (
            OikosToken oikosImpl,
            ERC1967Proxy proxy,
            bytes32 tokenHash
        )
    {
        // compute these once
        tokenHash = keccak256(abi.encodePacked(name, symbol));
        uint256 nonce = uint256(tokenHash);

        // deploy implementation
        oikosImpl = new OikosToken{salt: bytes32(nonce)}();

        do {
            // deploy proxy, with inline data encoding (no `data` local)
            proxy = new ERC1967Proxy{salt: bytes32(nonce)}(
                address(oikosImpl),
                abi.encodeWithSelector(
                    OikosToken.initialize.selector,
                    msg.sender,
                    initialSupply,
                    maxTotalSupply,
                    name,
                    symbol,
                    address(resolver)
                )
            );
            nonce++;
        } while (address(proxy) >= _token1);

        // address check
        if (address(proxy) >= _token1) revert InvalidTokenAddressError();

        // sanity checks
        require(
           IERC20(address(proxy)).totalSupply() == initialSupply,
           "wrong parameters"
        );
        require(address(proxy) != address(0), "Token deploy failed");
    }

    function factory() public view returns (address) {
        return resolver.requireAndGetAddress(
            "NomaFactory",
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