// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

interface IVNoma {
    function mint(address to, uint256 amount) external;
}

contract VNomaVoucherMinter is AccessControl, Pausable, ReentrancyGuard, EIP712 {
    bytes32 public constant SIGNER_ROLE  = keccak256("SIGNER_ROLE");   // Who can sign vouchers
    bytes32 public constant BATCHER_ROLE = keccak256("BATCHER_ROLE");  // Who can call claimBatch

    IVNoma public immutable vNOMA;

    // cumulative claimed per user per round
    mapping(address => mapping(uint256 => uint256)) public claimed; // recipient => roundId => cumulative claimed

    // EIP-712 typed data
    // Note: 'authorizer' lets us support EOAs (recover) *and* EIP-1271 contract signers cleanly.
    struct Claim {
        address recipient;      // who receives vNOMA
        address authorizer;     // expected signer address (EOA or 1271 contract)
        uint256 cumulative;     // cumulative allocation up to this voucher
        uint256 roundId;        // epoch/round identifier (e.g., 2025_09_01)
        uint64  validAfter;     // not before
        uint64  validBefore;    // not after
    }

    bytes32 private constant _CLAIM_TYPEHASH =
        keccak256("Claim(address recipient,address authorizer,uint256 cumulative,uint256 roundId,uint64 validAfter,uint64 validBefore)");

    event Claimed(address indexed recipient, uint256 roundId, uint256 minted, uint256 newCumulative, address indexed relayer, address indexed authorizer);

    constructor(address vNomaToken, address admin)
        EIP712("vNOMA Voucher", "1")
    {
        require(vNomaToken != address(0) && admin != address(0), "zero addr");
        vNOMA = IVNoma(vNomaToken);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ---- User (or any relayer) can submit a single claim ----
    function claim(Claim calldata c, bytes calldata signature) external whenNotPaused nonReentrant {
        _processClaim(c, signature);
    }

    // ---- Managers can submit batches (gas efficient) ----
    function claimBatch(Claim[] calldata cs, bytes[] calldata sigs)
        external
        whenNotPaused
        nonReentrant
        onlyRole(BATCHER_ROLE)
    {
        require(cs.length == sigs.length, "length mismatch");
        for (uint256 i = 0; i < cs.length; i++) {
            _processClaim(cs[i], sigs[i]);
        }
    }

    // ---- Admin maintenance ----
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }

    // ---- Internal verification & mint ----
    function _processClaim(Claim calldata c, bytes calldata sig) internal {
        // time window
        uint256 t = block.timestamp;
        require(t >= c.validAfter && t <= c.validBefore, "voucher expired/not yet valid");

        // signer authorization
        require(hasRole(SIGNER_ROLE, c.authorizer), "unauthorized authorizer");

        // digest
        bytes32 structHash = keccak256(abi.encode(
            _CLAIM_TYPEHASH,
            c.recipient,
            c.authorizer,
            c.cumulative,
            c.roundId,
            c.validAfter,
            c.validBefore
        ));
        bytes32 digest = _hashTypedDataV4(structHash);

        // EOA or EIP-1271 contract signer
        require(SignatureChecker.isValidSignatureNow(c.authorizer, digest, sig), "bad signature");

        // mint delta (cumulative pattern)
        uint256 already = claimed[c.recipient][c.roundId];
        require(c.cumulative > already, "nothing to mint");
        uint256 toMint = c.cumulative - already;

        // effects
        claimed[c.recipient][c.roundId] = c.cumulative;

        // interactions
        vNOMA.mint(c.recipient, toMint);

        emit Claimed(c.recipient, c.roundId, toMint, c.cumulative, msg.sender, c.authorizer);
    }
}
