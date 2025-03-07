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
        // Deploy the Oikos token
        (
            OikosToken nomaToken, 
            ERC1967Proxy proxy, 
            bytes32 tokenHash
        ) = _deployOikosToken(
            vaultDeployParams.name,
            vaultDeployParams.symbol,
            vaultDeployParams.token1,
            vaultDeployParams.totalSupply
        );

        return (nomaToken, proxy, tokenHash);
    }

    /**
    * @notice Deploys a new Oikos token with the specified parameters.
    * @param name The name of the token.
    * @param symbol The symbol of the token.
    * @param _token1 The address of the paired token (token1).
    * @param totalSupply The total supply of the token.
    * @return nomaToken The address of the newly deployed OikosToken.
    * @dev This internal function ensures the token does not already exist, generates a unique address using a salt, and initializes the token.
    * It reverts if the token address is invalid or if the token already exists.
    */
    function _deployOikosToken(
        string memory name,
        string memory symbol,
        address _token1,
        uint256 totalSupply
    ) internal returns  (OikosToken, ERC1967Proxy, bytes32) {
        bytes32 tokenHash = keccak256(abi.encodePacked(name, symbol));

        uint256 nonce = uint256(tokenHash);

        OikosToken _nomaToken;
        ERC1967Proxy proxy ;

        // Encode the initialize function call
        bytes memory data = abi.encodeWithSelector(
            _nomaToken.initialize.selector,
            msg.sender,       // Deployer address
            totalSupply,     // Initial supply
            name,            // Token name
            symbol,          // Token symbol
            address(resolver) // Resolver address
        );

        do {
            _nomaToken = new OikosToken{salt: bytes32(nonce)}();
            // Deploy the proxy contract
            proxy = new ERC1967Proxy{salt: bytes32(nonce)}(
                address(_nomaToken),
                data
            );
            nonce++;
        } while (address(proxy) >= _token1);

        if (address(proxy) >= _token1) revert InvalidTokenAddressError();

        uint256 totalSupplyFromContract = IERC20(address(proxy)).totalSupply();
        require(totalSupplyFromContract == totalSupply, "wrong parameters");

        require(address(proxy) != address(0), "Token deploy failed");
        return (_nomaToken, proxy, tokenHash);
    }

    function factory() public view returns (address) {
        return resolver.requireAndGetAddress(
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