// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IAddressResolver} from "../interfaces/IAddressResolver.sol";
import {Utils} from "../libraries/Utils.sol";

contract MockNomaToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {

    IAddressResolver public resolver;

    error OnlyFactory();
    error CannotInitializeLogicContract();

    constructor() {
        // Disable initializers to prevent the logic contract from being initialized
        _disableInitializers();
    }

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

    function mint(address _recipient, uint256 _amount) public onlyFactory {
        _mint(_recipient, _amount);
    }
    
    function burn(address account, uint256 amount) public onlyFactory {
        _burn(account, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function version() public pure returns (string memory) {
        return "1";
    }

    function proxiableUUID() public pure override returns (bytes32) {
        bytes32 hash = keccak256("eip1967.proxy.implementation");
        bytes32 slot = bytes32(uint256(hash) - 1);
        return slot;
    }

    function setOwner(address _owner) external onlyOwner {
        super.transferOwnership(_owner);
    }

    function renounceOwnership() public override onlyOwner {
        renounceOwnership();
    }

    function nomaFactory() public view returns (address) {
        return resolver
        .requireAndGetAddress(
            Utils.stringToBytes32("NomaFactory"), 
            "no nomaFactory"
        );
    }    

    modifier onlyFactory() {
        if (msg.sender != nomaFactory()) revert OnlyFactory();
        _;
    }
}
