// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { NomaToken } from "../token/NomaToken.sol";
import { IAddressResolver } from "../interfaces/IAddressResolver.sol";
import { VaultDeployParams } from "../types/Types.sol";
import "../libraries/Utils.sol";

/**
 * @title IERC20
 * @notice Minimal interface used for sanity checks after deployment.
 */
interface IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function totalSupply() external view returns (uint256);
}

error InvalidTokenAddressError();
error PredictionNotFoundWithinLimit();

contract TokenFactory {
    IAddressResolver public resolver;

    // Upper bound to avoid unbounded work in prediction loops.
    uint256 private constant MAX_TRIES = 10_000;

    constructor(address _resolver) {
        resolver = IAddressResolver(_resolver);
    }

    // ===========
    //  PREDICTOR
    // ===========

    /**
     * @notice Pure prediction (no deploy): compute the implementation & proxy addresses and salts.
     * @dev IMPORTANT: The deployer assumed in CREATE2 is this contract (address(this)).
     *      The `initialOwner` must match the value you will pass to initialize() at deploy time
     *      (you used msg.sender before; pass the same when calling the deploy function).
     */
    function predictNomaToken(
        VaultDeployParams memory p,
        address initialOwner
    )
        public
        view
        returns (
            address implAddr,
            address proxyAddr,
            bytes32 tokenHash,
            bytes32 implSalt,
            bytes32 proxySalt
        )
    {
        // 1) Implementation salt & predicted address
        tokenHash = keccak256(abi.encodePacked(p.name, p.symbol));
        implSalt = bytes32(uint256(tokenHash));
        implAddr = Utils.getAddress(type(NomaToken).creationCode, uint256(implSalt));

        // 2) Proxy creation code (constructor(impl, data))
        bytes memory initCalldata = abi.encodeWithSelector(
            NomaToken.initialize.selector,
            initialOwner,
            p.initialSupply,
            p.maxTotalSupply,
            p.name,
            p.symbol,
            address(resolver)
        );

        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implAddr, initCalldata)
        );

        // 3) Find salt such that predicted proxy < p.token1
        uint256 nonce = uint256(implSalt);
        address candidate;

        for (uint256 i = 0; i < MAX_TRIES; i++) {
            candidate = Utils.getAddress(proxyBytecode, nonce);
            if (candidate != address(0) && candidate < p.token1) {
                proxyAddr = candidate;
                proxySalt = bytes32(nonce);
                break;
            }
            unchecked { nonce++; }
        }

        if (proxyAddr == address(0)) {
            revert PredictionNotFoundWithinLimit();
        }
    }

    // =========
    //  DEPLOY
    // =========

    /**
     * @notice Deploy NomaToken implementation and its ERC1967Proxy using salts chosen by the same prediction loop.
     * @dev Uses CREATE2 and verifies deployed addresses match the predictions.
     *      Owner passed to initialize() is msg.sender (the factory) to mirror your original code.
     */
    function deployNomaToken(
        VaultDeployParams memory p
    )
        external
        onlyFactory
        returns (NomaToken nomaImpl, ERC1967Proxy proxy, bytes32 tokenHash)
    {
        // 1) Predict the addresses & salts (using msg.sender as initialize() owner)
        (
            address predictedImpl,
            address predictedProxy,
            bytes32 _tokenHash,
            bytes32 implSalt,
            bytes32 proxySalt
        ) = predictNomaToken(p, msg.sender);

        tokenHash = _tokenHash;

        // 2) Deploy the implementation at predictedImpl
        //    (init code: type(NomaToken).creationCode, no constructor args)
        {
            bytes memory implCode = type(NomaToken).creationCode;
            address implAddr = _doDeploy(implCode, uint256(implSalt));
            require(implAddr == predictedImpl, "Impl address mismatch");
            nomaImpl = NomaToken(implAddr);
        }

        // 3) Build proxy bytecode with the *actual* impl address (should equal predictedImpl)
        bytes memory initCalldata = abi.encodeWithSelector(
            NomaToken.initialize.selector,
            msg.sender,                // owner (same as used in prediction)
            p.initialSupply,
            p.maxTotalSupply,
            p.name,
            p.symbol,
            address(resolver)
        );

        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(address(nomaImpl), initCalldata)
        );

        // 4) Deploy proxy at predictedProxy using proxySalt
        {
            address proxyAddr = _doDeploy(proxyBytecode, uint256(proxySalt));
            require(proxyAddr == predictedProxy, "Proxy address mismatch");
            require(proxyAddr < p.token1, "Proxy address fails token1 constraint");
            proxy = ERC1967Proxy(payable(proxyAddr));
        }

        // 5) Sanity checks
        require(IERC20(address(proxy)).totalSupply() == p.initialSupply, "wrong parameters");
        require(address(proxy) != address(0), "Token deploy failed");
    }

    // Low-level CREATE2 deployer
    function _doDeploy(bytes memory bytecode, uint256 salt) internal returns (address addr) {
        assembly {
            addr := create2(
                callvalue(),              // pass through any ETH (usually 0)
                add(bytecode, 0x20),      // code start
                mload(bytecode),          // code length
                salt
            )
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
    }

    // =========
    //  ACCESS
    // =========

    function factory() public view returns (address) {
        return resolver.requireAndGetAddress("NomaFactory", "No factory");
    }

    modifier onlyFactory() {
        require(msg.sender == factory(), "Only factory allowed");
        _;
    }
}
