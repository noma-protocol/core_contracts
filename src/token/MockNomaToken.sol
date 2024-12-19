// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract MockNomaToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {

    function initialize(address deployer, uint256 totalSupply, string memory _name, string memory _symbol) initializer public {
        __ERC20_init(_name, _symbol);
        __Ownable_init(deployer);
        __UUPSUpgradeable_init();
        _mint(deployer, totalSupply);
    }

    function mint(address _recipient, uint256 _amount) public /*onlyOwner*/ {
        _mint(_recipient, _amount);
    }
    
    function mintTo(address to, uint256 amount) external /*onlyOwner*/  {
        _mint(to, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override /*onlyOwner*/ {}

    function version() public pure returns (string memory) {
        return "1";
    }

    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("eip1967.proxy.implementation");
    }

    function setOwner(address _owner) external onlyOwner {
        super.transferOwnership(_owner);
    }

    function renounceOwnership() public override onlyOwner {
        renounceOwnership();
    }
}
