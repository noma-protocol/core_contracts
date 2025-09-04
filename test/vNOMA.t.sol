// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {VNoma} from "../src/token/vNOMA/vNOMA.sol";
import {VNomaVoucherMinter} from "../src/token/vNOMA/VoucherMinter.sol";
import {VNomaRedeemer} from "../src/token/vNOMA/Redeemer.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// Mock NOMA token for testing
contract MockNoma is ERC20 {
    constructor(uint256 initialSupply) ERC20("NOMA", "NOMA") {
        _mint(msg.sender, initialSupply);
    }
}

contract VNomaTest is Test {
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
    
    uint256 public signerPrivateKey = 0xA11CE;
    
    function setUp() public {
        // Derive signer address from private key
        signer = vm.addr(signerPrivateKey);
        
        // Deploy vNOMA token
        vNoma = new VNoma("Voucher NOMA", "vNOMA");
        vNoma.grantRole(vNoma.DEFAULT_ADMIN_ROLE(), admin);
        
        // Deploy voucher minter
        minter = new VNomaVoucherMinter(address(vNoma), admin);
        
        // Deploy mock NOMA token (for redeemer testing)
        noma = new MockNoma(1000000e18);
        
        // Deploy redeemer with 1:1 initial rate
        redeemer = new VNomaRedeemer(
            address(noma),
            address(vNoma),
            1e18, // 1:1 rate
            manager,
            admin
        );
        
        // Grant roles
        vm.startPrank(admin);
        vNoma.grantRole(vNoma.MINTER_ROLE(), address(minter));
        vNoma.grantRole(vNoma.MINTER_ROLE(), address(redeemer)); // Redeemer needs MINTER_ROLE to burn
        minter.grantRole(minter.SIGNER_ROLE(), signer);
        minter.grantRole(minter.BATCHER_ROLE(), batcher);
        vm.stopPrank();
        
        // Fund redeemer with NOMA (from test contract which owns the tokens)
        noma.transfer(address(redeemer), 100000e18);
    }
    
    // ============= vNOMA Token Tests =============
    
    function testVNoma_NonTransferable() public {
        // Mint some vNOMA to user1
        vm.prank(address(minter));
        vNoma.mint(user1, 100e18);
        
        // Try to transfer - should fail
        vm.prank(user1);
        vm.expectRevert("vNOMA: non-transferable");
        vNoma.transfer(user2, 50e18);
    }
    
    function testVNoma_MintOnlyByMinter() public {
        // Non-minter tries to mint
        vm.prank(user1);
        vm.expectRevert();
        vNoma.mint(user2, 100e18);
        
        // Minter can mint
        vm.prank(address(minter));
        vNoma.mint(user2, 100e18);
        assertEq(vNoma.balanceOf(user2), 100e18);
    }
    
    function testVNoma_BurnOnlyByMinter() public {
        // Mint first
        vm.prank(address(minter));
        vNoma.mint(user1, 100e18);
        
        // Non-minter tries to burn
        vm.prank(user2);
        vm.expectRevert();
        vNoma.burn(user1, 50e18);
        
        // Minter can burn
        vm.prank(address(minter));
        vNoma.burn(user1, 50e18);
        assertEq(vNoma.balanceOf(user1), 50e18);
    }
    
    // ============= Voucher Minter Tests =============
    
    function testMinter_ValidClaim() public {
        // Create claim data
        VNomaVoucherMinter.Claim memory claim = VNomaVoucherMinter.Claim({
            recipient: user1,
            authorizer: signer,
            cumulative: 1000e18,
            roundId: 202501,
            validAfter: uint64(block.timestamp - 1),
            validBefore: uint64(block.timestamp + 1 hours)
        });
        
        // Create signature
        bytes32 digest = getClaimDigest(claim);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Claim voucher
        vm.prank(user1);
        minter.claim(claim, signature);
        
        // Check balance
        assertEq(vNoma.balanceOf(user1), 1000e18);
        assertEq(minter.claimed(user1, 202501), 1000e18);
    }
    
    function testMinter_CumulativeClaim() public {
        // First claim for 500
        VNomaVoucherMinter.Claim memory claim1 = VNomaVoucherMinter.Claim({
            recipient: user1,
            authorizer: signer,
            cumulative: 500e18,
            roundId: 202501,
            validAfter: uint64(block.timestamp - 1),
            validBefore: uint64(block.timestamp + 1 hours)
        });
        
        bytes32 digest1 = getClaimDigest(claim1);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signerPrivateKey, digest1);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);
        
        vm.prank(user1);
        minter.claim(claim1, signature1);
        assertEq(vNoma.balanceOf(user1), 500e18);
        
        // Second claim for cumulative 1500
        VNomaVoucherMinter.Claim memory claim2 = VNomaVoucherMinter.Claim({
            recipient: user1,
            authorizer: signer,
            cumulative: 1500e18,
            roundId: 202501,
            validAfter: uint64(block.timestamp - 1),
            validBefore: uint64(block.timestamp + 1 hours)
        });
        
        bytes32 digest2 = getClaimDigest(claim2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signerPrivateKey, digest2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);
        
        vm.prank(user1);
        minter.claim(claim2, signature2);
        assertEq(vNoma.balanceOf(user1), 1500e18); // Total cumulative
        assertEq(minter.claimed(user1, 202501), 1500e18);
    }
    
    function testMinter_ExpiredVoucher() public {
        vm.warp(1000); // Set block.timestamp to 1000 to avoid underflow
        
        VNomaVoucherMinter.Claim memory claim = VNomaVoucherMinter.Claim({
            recipient: user1,
            authorizer: signer,
            cumulative: 1000e18,
            roundId: 202501,
            validAfter: uint64(100),
            validBefore: uint64(500) // Already expired (current time is 1000)
        });
        
        bytes32 digest = getClaimDigest(claim);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        vm.prank(user1);
        vm.expectRevert("voucher expired/not yet valid");
        minter.claim(claim, signature);
    }
    
    function testMinter_UnauthorizedSigner() public {
        // Use non-authorized signer
        address fakeSigner = address(0x999);
        uint256 fakeSignerKey = 0xFAFE;
        
        VNomaVoucherMinter.Claim memory claim = VNomaVoucherMinter.Claim({
            recipient: user1,
            authorizer: fakeSigner,
            cumulative: 1000e18,
            roundId: 202501,
            validAfter: uint64(block.timestamp - 1),
            validBefore: uint64(block.timestamp + 1 hours)
        });
        
        bytes32 digest = getClaimDigest(claim);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(fakeSignerKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        vm.prank(user1);
        vm.expectRevert("unauthorized authorizer");
        minter.claim(claim, signature);
    }
    
    function testMinter_BatchClaim() public {
        VNomaVoucherMinter.Claim[] memory claims = new VNomaVoucherMinter.Claim[](2);
        bytes[] memory signatures = new bytes[](2);
        
        // Claim 1
        claims[0] = VNomaVoucherMinter.Claim({
            recipient: user1,
            authorizer: signer,
            cumulative: 1000e18,
            roundId: 202501,
            validAfter: uint64(block.timestamp - 1),
            validBefore: uint64(block.timestamp + 1 hours)
        });
        
        bytes32 digest1 = getClaimDigest(claims[0]);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signerPrivateKey, digest1);
        signatures[0] = abi.encodePacked(r1, s1, v1);
        
        // Claim 2
        claims[1] = VNomaVoucherMinter.Claim({
            recipient: user2,
            authorizer: signer,
            cumulative: 2000e18,
            roundId: 202501,
            validAfter: uint64(block.timestamp - 1),
            validBefore: uint64(block.timestamp + 1 hours)
        });
        
        bytes32 digest2 = getClaimDigest(claims[1]);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signerPrivateKey, digest2);
        signatures[1] = abi.encodePacked(r2, s2, v2);
        
        // Batch claim
        vm.prank(batcher);
        minter.claimBatch(claims, signatures);
        
        assertEq(vNoma.balanceOf(user1), 1000e18);
        assertEq(vNoma.balanceOf(user2), 2000e18);
    }
    
    function testMinter_PauseUnpause() public {
        vm.prank(admin);
        minter.pause();
        
        // Create valid claim
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
        
        // Try to claim while paused
        vm.prank(user1);
        vm.expectRevert();
        minter.claim(claim, signature);
        
        // Unpause and try again
        vm.prank(admin);
        minter.unpause();
        
        vm.prank(user1);
        minter.claim(claim, signature);
        assertEq(vNoma.balanceOf(user1), 1000e18);
    }
    
    // ============= Redeemer Tests =============
    
    function testRedeemer_BasicRedeem() public {
        // Mint vNOMA to user
        vm.prank(address(minter));
        vNoma.mint(user1, 100e18);
        
        // Approve redeemer to burn vNOMA
        vm.prank(user1);
        vNoma.approve(address(redeemer), 100e18);
        
        uint256 nomaBalanceBefore = noma.balanceOf(user1);
        
        // Redeem
        vm.prank(user1);
        redeemer.redeem(100e18, user1);
        
        // Check balances
        assertEq(vNoma.balanceOf(user1), 0);
        assertEq(noma.balanceOf(user1), nomaBalanceBefore + 100e18); // 1:1 rate
    }
    
    function testRedeemer_DifferentRates() public {
        // Set rate to 2:1 (2 NOMA per 1 vNOMA)
        vm.prank(manager);
        redeemer.setRate(2e18);
        
        // Mint vNOMA
        vm.prank(address(minter));
        vNoma.mint(user1, 100e18);
        
        // Approve and redeem
        vm.prank(user1);
        vNoma.approve(address(redeemer), 100e18);
        
        uint256 nomaBalanceBefore = noma.balanceOf(user1);
        
        vm.prank(user1);
        redeemer.redeem(100e18, user1);
        
        assertEq(noma.balanceOf(user1), nomaBalanceBefore + 200e18); // 2:1 rate
    }
    
    function testRedeemer_InsufficientLiquidity() public {
        // Withdraw most NOMA from redeemer
        vm.prank(admin);
        redeemer.ownerWithdraw(99999e18, admin);
        
        // Mint vNOMA
        vm.prank(address(minter));
        vNoma.mint(user1, 1000e18);
        
        // Try to redeem more than available
        vm.prank(user1);
        vNoma.approve(address(redeemer), 1000e18);
        
        vm.prank(user1);
        vm.expectRevert(VNomaRedeemer.InsufficientLiquidity.selector);
        redeemer.redeem(1000e18, user1);
    }
    
    function testRedeemer_PreviewRedeem() public {
        // Test preview with different rates
        assertEq(redeemer.previewRedeem(100e18), 100e18); // 1:1 rate
        
        vm.prank(manager);
        redeemer.setRate(15e17); // 1.5:1
        assertEq(redeemer.previewRedeem(100e18), 150e18);
        
        vm.prank(manager);
        redeemer.setRate(5e17); // 0.5:1
        assertEq(redeemer.previewRedeem(100e18), 50e18);
    }
    
    function testRedeemer_OnlyManagerCanSetRate() public {
        vm.prank(user1);
        vm.expectRevert(VNomaRedeemer.NotManager.selector);
        redeemer.setRate(2e18);
        
        vm.prank(manager);
        redeemer.setRate(2e18);
        assertEq(redeemer.rate(), 2e18);
    }
    
    function testRedeemer_ManagerChange() public {
        address newManager = address(0x999);
        
        // Only owner can change manager
        vm.prank(user1);
        vm.expectRevert();
        redeemer.setManager(newManager);
        
        vm.prank(admin);
        redeemer.setManager(newManager);
        assertEq(redeemer.manager(), newManager);
        
        // New manager can set rate
        vm.prank(newManager);
        redeemer.setRate(3e18);
        assertEq(redeemer.rate(), 3e18);
    }
    
    function testRedeemer_ZeroAmountReverts() public {
        vm.prank(user1);
        vm.expectRevert(VNomaRedeemer.ZeroAmount.selector);
        redeemer.redeem(0, user1);
    }
    
    function testRedeemer_ZeroAddressReverts() public {
        // Mint vNOMA
        vm.prank(address(minter));
        vNoma.mint(user1, 100e18);
        
        vm.prank(user1);
        vNoma.approve(address(redeemer), 100e18);
        
        vm.prank(user1);
        vm.expectRevert(VNomaRedeemer.ZeroAddress.selector);
        redeemer.redeem(100e18, address(0));
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