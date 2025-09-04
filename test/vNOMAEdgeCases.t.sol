// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {VNoma} from "../src/token/vNOMA/vNOMA.sol";
import {VNomaVoucherMinter} from "../src/token/vNOMA/VoucherMinter.sol";
import {VNomaRedeemer} from "../src/token/vNOMA/Redeemer.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock NOMA token for testing
contract MockNoma is ERC20 {
    constructor(uint256 initialSupply) ERC20("NOMA", "NOMA") {
        _mint(msg.sender, initialSupply);
    }
}

contract VNomaEdgeCasesTest is Test {
    VNoma public vNoma;
    VNomaVoucherMinter public minter;
    VNomaRedeemer public redeemer;
    MockNoma public noma;
    
    address public admin = address(0x1);
    address public signer;
    address public batcher = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);
    address public manager = address(0x6);
    address public attacker = address(0x666);
    
    uint256 public signerPrivateKey = 0xA11CE;
    uint256 public attackerPrivateKey = 0xBADF00D;
    
    function setUp() public {
        // Derive signer address from private key
        signer = vm.addr(signerPrivateKey);
        
        // Deploy vNOMA token
        vNoma = new VNoma("Voucher NOMA", "vNOMA");
        vNoma.grantRole(vNoma.DEFAULT_ADMIN_ROLE(), admin);
        
        // Deploy voucher minter
        minter = new VNomaVoucherMinter(address(vNoma), admin);
        
        // Deploy mock NOMA token
        noma = new MockNoma(1000000e18);
        
        // Deploy redeemer
        redeemer = new VNomaRedeemer(
            address(noma),
            address(vNoma),
            1e18,
            manager,
            admin
        );
        
        // Grant roles
        vm.startPrank(admin);
        vNoma.grantRole(vNoma.MINTER_ROLE(), address(minter));
        vNoma.grantRole(vNoma.MINTER_ROLE(), address(redeemer)); // For burn functionality
        minter.grantRole(minter.SIGNER_ROLE(), signer);
        minter.grantRole(minter.BATCHER_ROLE(), batcher);
        vm.stopPrank();
        
        // Fund redeemer (from test contract which owns the tokens)
        noma.transfer(address(redeemer), 100000e18);
    }
    
    // ============= Reentrancy Tests =============
    
    function testMinter_NoReentrancy() public {
        // Deploy malicious contract that tries reentrancy
        ReentrancyAttacker attackContract = new ReentrancyAttacker(minter);
        
        VNomaVoucherMinter.Claim memory claim = VNomaVoucherMinter.Claim({
            recipient: address(attackContract),
            authorizer: signer,
            cumulative: 1000e18,
            roundId: 202501,
            validAfter: uint64(block.timestamp - 1),
            validBefore: uint64(block.timestamp + 1 hours)
        });
        
        bytes32 digest = getClaimDigest(claim);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Should revert due to reentrancy guard
        vm.expectRevert("ReentrancyGuard: reentrant call");
        attackContract.attack(claim, signature);
    }
    
    function testRedeemer_NoReentrancy() public {
        // Mint vNOMA to attacker
        vm.prank(address(minter));
        vNoma.mint(attacker, 1000e18);
        
        // Deploy malicious contract
        RedeemerReentrancyAttacker attackContract = new RedeemerReentrancyAttacker(redeemer, vNoma);
        
        // Mint vNOMA directly to attack contract (since transfers are disabled)
        vm.prank(address(minter));
        vNoma.mint(address(attackContract), 1000e18);
        
        // Try reentrancy attack
        vm.expectRevert("ReentrancyGuard: reentrant call");
        attackContract.attack();
    }
    
    // ============= Overflow/Underflow Tests =============
    
    function testMinter_LargeCumulativeAmount() public {
        // Test with maximum uint256
        uint256 maxAmount = type(uint256).max;
        
        VNomaVoucherMinter.Claim memory claim = VNomaVoucherMinter.Claim({
            recipient: user1,
            authorizer: signer,
            cumulative: maxAmount,
            roundId: 202501,
            validAfter: uint64(block.timestamp - 1),
            validBefore: uint64(block.timestamp + 1 hours)
        });
        
        bytes32 digest = getClaimDigest(claim);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Should handle large numbers properly
        vm.prank(user1);
        minter.claim(claim, signature);
        assertEq(vNoma.balanceOf(user1), maxAmount);
    }
    
    function testRedeemer_ExtremeRates() public {
        // Test with very small rate
        vm.prank(manager);
        redeemer.setRate(1); // Smallest possible rate
        
        vm.prank(address(minter));
        vNoma.mint(user1, 1e18);
        
        vm.prank(user1);
        vNoma.approve(address(redeemer), 1e18);
        
        // Should get minimal NOMA
        uint256 preview = redeemer.previewRedeem(1e18);
        assertEq(preview, 1); // 1e18 * 1 / 1e18 = 1
        
        // Test with maximum rate
        vm.prank(manager);
        redeemer.setRate(type(uint256).max);
        
        // Preview should handle overflow
        vm.expectRevert(); // Arithmetic overflow
        redeemer.previewRedeem(2);
    }
    
    // ============= Signature Replay Tests =============
    
    function testMinter_NoSignatureReplay() public {
        VNomaVoucherMinter.Claim memory claim = VNomaVoucherMinter.Claim({
            recipient: user1,
            authorizer: signer,
            cumulative: 1000e18,
            roundId: 202501,
            validAfter: uint64(block.timestamp - 1),
            validBefore: uint64(block.timestamp + 1 hours)
        });
        
        bytes32 digest = getClaimDigest(claim);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // First claim succeeds
        vm.prank(user1);
        minter.claim(claim, signature);
        
        // Try to replay the same signature
        vm.prank(user1);
        vm.expectRevert("nothing to mint"); // Already claimed this cumulative amount
        minter.claim(claim, signature);
    }
    
    function testMinter_DifferentRoundsSameSignature() public {
        // Claim for round 1
        VNomaVoucherMinter.Claim memory claim1 = VNomaVoucherMinter.Claim({
            recipient: user1,
            authorizer: signer,
            cumulative: 1000e18,
            roundId: 202501,
            validAfter: uint64(block.timestamp - 1),
            validBefore: uint64(block.timestamp + 1 hours)
        });
        
        bytes32 digest1 = getClaimDigest(claim1);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signerPrivateKey, digest1);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);
        
        vm.prank(user1);
        minter.claim(claim1, signature1);
        
        // Different round, same cumulative amount - should work
        VNomaVoucherMinter.Claim memory claim2 = VNomaVoucherMinter.Claim({
            recipient: user1,
            authorizer: signer,
            cumulative: 1000e18,
            roundId: 202502, // Different round
            validAfter: uint64(block.timestamp - 1),
            validBefore: uint64(block.timestamp + 1 hours)
        });
        
        bytes32 digest2 = getClaimDigest(claim2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signerPrivateKey, digest2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);
        
        vm.prank(user1);
        minter.claim(claim2, signature2);
        
        // Should have 2000e18 total (1000 from each round)
        assertEq(vNoma.balanceOf(user1), 2000e18);
    }
    
    // ============= Access Control Tests =============
    
    function testMinter_RoleManagement() public {
        address newSigner = address(0x999);
        address nonAdmin = address(0x888);
        
        // Non-admin cannot grant roles
        vm.prank(nonAdmin);
        vm.expectRevert();
        minter.grantRole(minter.SIGNER_ROLE(), newSigner);
        
        // Admin can grant roles
        vm.prank(admin);
        minter.grantRole(minter.SIGNER_ROLE(), newSigner);
        
        // New signer can sign vouchers
        VNomaVoucherMinter.Claim memory claim = VNomaVoucherMinter.Claim({
            recipient: user1,
            authorizer: newSigner,
            cumulative: 500e18,
            roundId: 202503,
            validAfter: uint64(block.timestamp - 1),
            validBefore: uint64(block.timestamp + 1 hours)
        });
        
        bytes32 digest = getClaimDigest(claim);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x999999, digest); // Different private key
        bytes memory signature = abi.encodePacked(r, s, v);
        
        vm.prank(user1);
        minter.claim(claim, signature);
        assertEq(vNoma.balanceOf(user1), 500e18);
    }
    
    // ============= Edge Case: Multiple Users Same Block =============
    
    function testMinter_MultipleUsersSimultaneous() public {
        address[] memory users = new address[](10);
        for (uint i = 0; i < 10; i++) {
            users[i] = address(uint160(0x1000 + i));
        }
        
        VNomaVoucherMinter.Claim[] memory claims = new VNomaVoucherMinter.Claim[](10);
        bytes[] memory signatures = new bytes[](10);
        
        for (uint i = 0; i < 10; i++) {
            claims[i] = VNomaVoucherMinter.Claim({
                recipient: users[i],
                authorizer: signer,
                cumulative: (i + 1) * 100e18,
                roundId: 202501,
                validAfter: uint64(block.timestamp - 1),
                validBefore: uint64(block.timestamp + 1 hours)
            });
            
            bytes32 digest = getClaimDigest(claims[i]);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
            signatures[i] = abi.encodePacked(r, s, v);
        }
        
        // Batch claim all at once
        vm.prank(batcher);
        minter.claimBatch(claims, signatures);
        
        // Verify all balances
        for (uint i = 0; i < 10; i++) {
            assertEq(vNoma.balanceOf(users[i]), (i + 1) * 100e18);
        }
    }
    
    // ============= Helper Functions =============
    
    function getClaimDigest(VNomaVoucherMinter.Claim memory claim) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Claim(address recipient,address authorizer,uint256 cumulative,uint256 roundId,uint64 validAfter,uint64 validBefore)"),
            claim.recipient,
            claim.authorizer,
            claim.cumulative,
            claim.roundId,
            claim.validAfter,
            claim.validBefore
        ));
        
        // Get the domain separator by computing it the same way the minter does
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("vNOMA Voucher")),
                keccak256(bytes("1")),
                block.chainid,
                address(minter)
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

// Attack contracts for testing
contract ReentrancyAttacker {
    VNomaVoucherMinter public minter;
    bool public attacking;
    
    constructor(VNomaVoucherMinter _minter) {
        minter = _minter;
    }
    
    function attack(VNomaVoucherMinter.Claim memory claim, bytes memory signature) external {
        attacking = true;
        minter.claim(claim, signature);
    }
    
    // ERC20 callback hook (if vNOMA had transfers enabled)
    function onERC20Received() external {
        if (attacking) {
            attacking = false;
            // Try to claim again
            VNomaVoucherMinter.Claim memory claim = VNomaVoucherMinter.Claim({
                recipient: address(this),
                authorizer: address(0x2),
                cumulative: 2000e18,
                roundId: 202501,
                validAfter: uint64(block.timestamp - 1),
                validBefore: uint64(block.timestamp + 1 hours)
            });
            minter.claim(claim, "");
        }
    }
}

contract RedeemerReentrancyAttacker {
    VNomaRedeemer public redeemer;
    VNoma public vNoma;
    bool public attacking;
    
    constructor(VNomaRedeemer _redeemer, VNoma _vNoma) {
        redeemer = _redeemer;
        vNoma = _vNoma;
    }
    
    function attack() external {
        attacking = true;
        vNoma.approve(address(redeemer), 1000e18);
        redeemer.redeem(500e18, address(this));
    }
    
    // Fallback to receive NOMA
    receive() external payable {
        if (attacking) {
            attacking = false;
            // Try to redeem again during the first redeem
            redeemer.redeem(500e18, address(this));
        }
    }
}