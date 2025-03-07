// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IAddressResolver} from "../interfaces/IAddressResolver.sol";
import {Utils} from "../libraries/Utils.sol";

/**
 * @title OikosToken
 * @notice Noma token contract.
 * @dev This contract is upgradeable and uses the UUPS proxy pattern.
 */
contract OikosToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {

    // State variables
    IAddressResolver public resolver; // The address resolver contract.

    // Custom errors
    error OnlyFactory();
    error CannotInitializeLogicContract();

    /**
     * @notice Constructor to disable initializers for the logic contract.
     */
    constructor() {
        // Disable initializers to prevent the logic contract from being initialized
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract.
     * @param _deployer The address of the deployer.
     * @param _totalSupply The total supply of the token.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @param _resolver The address of the resolver contract.
     */
    function initialize(
        address _deployer,
        uint256 _totalSupply, 
        string memory _name, 
        string memory _symbol,
        address _resolver
    ) external initializer {
        if (msg.sender == address(this)) revert CannotInitializeLogicContract();
        __ERC20_init(_name, _symbol);
        __Ownable_init(_deployer);
        __UUPSUpgradeable_init();
        _mint(_deployer, _totalSupply);
        resolver = IAddressResolver(_resolver);
    }

    /**
     * @notice Mints new tokens to the specified recipient.
     * @param _recipient The address to receive the minted tokens.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _recipient, uint256 _amount) public onlyFactory {
        _mint(_recipient, _amount);
    }
    
    /**
     * @notice Burns tokens from the specified account.
     * @param account The address from which to burn tokens.
     * @param amount The amount of tokens to burn.
     */
    function burn(address account, uint256 amount) public onlyFactory {
        _burn(account, amount);
    }

    /**
     * @notice Authorizes an upgrade to a new implementation.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Returns the version of the contract.
     * @return The version of the contract.
     */
    function version() public pure returns (string memory) {
        return "1";
    }

    /**
     * @notice Returns the UUID for the proxy implementation slot.
     * @return The UUID for the proxy implementation slot.
     */
    function proxiableUUID() public pure override returns (bytes32) {
        bytes32 hash = keccak256("eip1967.proxy.implementation");
        bytes32 slot = bytes32(uint256(hash) - 1);
        return slot;
    }

    /**
     * @notice Transfers ownership of the contract to a new owner.
     * @param _owner The address of the new owner.
     */
    function setOwner(address _owner) external onlyOwner {
        super.transferOwnership(_owner);
    }

    /**
     * @notice Renounces ownership of the contract.
     */
    function renounceOwnership() public override onlyOwner {
        renounceOwnership();
    }

    /**
     * @notice Returns the address of the OikosFactory contract.
     * @return The address of the OikosFactory contract.
     */
    function nomaFactory() public view returns (address) {
        return resolver
        .requireAndGetAddress(
            Utils.stringToBytes32("OikosFactory"), 
            "no nomaFactory"
        );
    }    

    /**
     * @notice Modifier to restrict access to the OikosFactory contract.
     */
    modifier onlyFactory() {
        if (msg.sender != nomaFactory()) revert OnlyFactory();
        _;
    }
}