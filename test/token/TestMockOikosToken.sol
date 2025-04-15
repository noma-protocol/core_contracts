// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IAddressResolver } from "../../src/interfaces/IAddressResolver.sol";
import { Utils } from "../../src/libraries/Utils.sol";

contract TestMockOikosToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {

    IAddressResolver public resolver;
    uint256 public maxTotalSupply; // The maximum total supply of the token.

    error MaxSupplyReached();

    function initialize(
        address _deployer,
        uint256 _initialSupply,
        uint256 _maxTotalSupply, 
        string memory _name, 
        string memory _symbol,
        address _resolver
    ) initializer public {
        __ERC20_init(_name, _symbol);
        __Ownable_init(_deployer);
        __UUPSUpgradeable_init();
        _mint(msg.sender, _initialSupply);
        maxTotalSupply = _maxTotalSupply;
        resolver = IAddressResolver(_resolver);
    }

    function mintTest(address to, uint256 amount) public {
        if (totalSupply() + amount > maxTotalSupply) revert MaxSupplyReached();
        _mint(to, amount);
    }
    
    function mintTo(address to, uint256 amount) public onlyFactory  {
        if (totalSupply() + amount > maxTotalSupply) revert MaxSupplyReached();
        _mint(to, amount);
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
        require(msg.sender == nomaFactory(), "Only factory");
        _;
    }
}
