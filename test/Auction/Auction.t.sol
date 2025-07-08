// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";
import {IMinter} from "../../src/interfaces/IMinter.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";

contract AuctionTest is Test, AuctionTestHelper {
    Auction public auction;

    address public constant MINTER = address(0x2);
    address public constant USDC = address(0x3);
    address public constant TREASURY = address(0x4);

    // Helper struct to avoid stack too deep errors
    struct BidParams {
        bytes32 castHash;
        address bidder;
        uint256 bidderFid;
        uint256 amount;
        bytes32 nonce;
        uint256 deadline;
    }

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 public constant BID_AUTHORIZATION_TYPEHASH = keccak256(
        "BidAuthorization(bytes32 castHash,address bidder,uint256 bidderFid,uint256 amount,bytes32 nonce,uint256 deadline)"
    );

    function setUp() public {
        auction = new Auction(MINTER, USDC, TREASURY, address(this));
    }

    function test_Constructor_SetsConfiguration() public view {
        assertEq(auction.minter(), MINTER);
        assertEq(auction.usdc(), USDC);
        assertEq(auction.treasury(), TREASURY);
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(auction.owner(), address(this));
    }

    function test_Constructor_RevertsIfMinterIsZero() public {
        vm.expectRevert(IAuction.InvalidAddress.selector);
        new Auction(address(0), USDC, TREASURY, address(this));
    }

    function test_Constructor_RevertsIfUSDCIsZero() public {
        vm.expectRevert(IAuction.InvalidAddress.selector);
        new Auction(MINTER, address(0), TREASURY, address(this));
    }

    function test_Constructor_RevertsIfTreasuryIsZero() public {
        vm.expectRevert(IAuction.InvalidAddress.selector);
        new Auction(MINTER, USDC, address(0), address(this));
    }

    function test_AllowAuthorizer_OnlyOwner() public {
        address authorizer = address(0x456);
        address notOwner = address(0x123);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        auction.allowAuthorizer(authorizer);
    }

    function test_AllowAuthorizer_UpdatesAllowlist() public {
        address authorizer = address(0x456);

        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        assertTrue(auction.authorizers(authorizer));
    }

    function test_AllowAuthorizer_EmitsEvent() public {
        address authorizer = address(0x456);

        vm.expectEmit(true, false, false, false);
        emit AuthorizerAllowed(authorizer);

        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
    }

    function test_AllowAuthorizer_RevertsIfZeroAddress() public {
        vm.prank(auction.owner());
        vm.expectRevert(IAuction.InvalidAddress.selector);
        auction.allowAuthorizer(address(0));
    }

    function test_DenyAuthorizer_OnlyOwner() public {
        address authorizer = address(0x456);
        address notOwner = address(0x123);

        // First allow the authorizer
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        // Try to deny as non-owner
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        auction.denyAuthorizer(authorizer);
    }

    function test_DenyAuthorizer_UpdatesAllowlist() public {
        address authorizer = address(0x456);

        // First allow the authorizer
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
        assertTrue(auction.authorizers(authorizer));

        // Then deny the authorizer
        vm.prank(auction.owner());
        auction.denyAuthorizer(authorizer);
        assertFalse(auction.authorizers(authorizer));
    }

    function test_DenyAuthorizer_EmitsEvent() public {
        address authorizer = address(0x456);

        // First allow the authorizer
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        // Then deny with event check
        vm.expectEmit(true, false, false, false);
        emit AuthorizerDenied(authorizer);

        vm.prank(auction.owner());
        auction.denyAuthorizer(authorizer);
    }

    event AuthorizerAllowed(address indexed authorizer);
    event AuthorizerDenied(address indexed authorizer);

    function test_SetTreasury_OnlyOwner() public {
        address newTreasury = address(0x789);
        address notOwner = address(0x123);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        auction.setTreasury(newTreasury);
    }

    function test_SetTreasury_UpdatesTreasury() public {
        address newTreasury = address(0x789);

        vm.prank(auction.owner());
        auction.setTreasury(newTreasury);

        assertEq(auction.treasury(), newTreasury);
    }

    function test_SetTreasury_EmitsEvent() public {
        address newTreasury = address(0x789);

        vm.expectEmit(true, true, false, false);
        emit TreasurySet(TREASURY, newTreasury);

        vm.prank(auction.owner());
        auction.setTreasury(newTreasury);
    }

    function test_SetTreasury_RevertsIfZeroAddress() public {
        vm.prank(auction.owner());
        vm.expectRevert(IAuction.InvalidAddress.selector);
        auction.setTreasury(address(0));
    }

    event TreasurySet(address indexed oldTreasury, address indexed newTreasury);

    // Fuzz tests

    function testFuzz_AllowAuthorizer_UpdatesAllowlist(address authorizer) public {
        vm.assume(authorizer != address(0));

        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        assertTrue(auction.authorizers(authorizer));
    }

    function testFuzz_DenyAuthorizer_UpdatesAllowlist(address authorizer) public {
        vm.assume(authorizer != address(0));

        // First allow the authorizer
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
        assertTrue(auction.authorizers(authorizer));

        // Then deny the authorizer
        vm.prank(auction.owner());
        auction.denyAuthorizer(authorizer);
        assertFalse(auction.authorizers(authorizer));
    }

    function testFuzz_SetTreasury_UpdatesTreasury(address newTreasury) public {
        vm.assume(newTreasury != address(0));

        vm.prank(auction.owner());
        auction.setTreasury(newTreasury);

        assertEq(auction.treasury(), newTreasury);
    }

    // Edge case tests

    // Test denying an authorizer that was never allowed
    function test_DenyAuthorizer_NotPreviouslyAllowed() public {
        address authorizer = address(0x456);

        // Verify not allowed initially
        assertFalse(auction.authorizers(authorizer));

        // Deny without allowing first
        vm.expectEmit(true, false, false, false);
        emit AuthorizerDenied(authorizer);

        vm.prank(auction.owner());
        auction.denyAuthorizer(authorizer);

        // Still false
        assertFalse(auction.authorizers(authorizer));
    }

    // Test Ownable2Step functionality
    function test_TransferOwnership_TwoStep() public {
        address newOwner = address(0x999);

        // Start transfer
        vm.prank(auction.owner());
        auction.transferOwnership(newOwner);

        // Ownership not transferred yet
        assertEq(auction.owner(), address(this));
        assertEq(auction.pendingOwner(), newOwner);

        // Accept ownership
        vm.prank(newOwner);
        auction.acceptOwnership();

        // Now ownership is transferred
        assertEq(auction.owner(), newOwner);
        assertEq(auction.pendingOwner(), address(0));
    }

    function test_AcceptOwnership_RevertsIfNotPendingOwner() public {
        address notPendingOwner = address(0x999);

        vm.prank(notPendingOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notPendingOwner));
        auction.acceptOwnership();
    }

    // EIP-712 tests
    function test_DomainSeparator_ComputesCorrectly() public view {
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256("CollectibleCastAuction"), keccak256("1"), block.chainid, address(auction)
            )
        );

        assertEq(auction.DOMAIN_SEPARATOR(), expectedDomainSeparator);
    }

    function test_Constructor_SetsDomainSeparator() public {
        // Deploy new auction to test domain separator is set in constructor
        Auction newAuction = new Auction(MINTER, USDC, TREASURY, address(this));

        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256("CollectibleCastAuction"), keccak256("1"), block.chainid, address(newAuction)
            )
        );

        assertEq(newAuction.DOMAIN_SEPARATOR(), expectedDomainSeparator);
    }

    function testFuzz_DomainSeparator_DifferentChainIds(uint256 chainId) public {
        vm.assume(chainId > 0 && chainId < type(uint64).max);
        vm.chainId(chainId);

        Auction newAuction = new Auction(MINTER, USDC, TREASURY, address(this));

        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256("CollectibleCastAuction"), keccak256("1"), chainId, address(newAuction)
            )
        );

        assertEq(newAuction.DOMAIN_SEPARATOR(), expectedDomainSeparator);
    }

    // Bid Authorization tests
    function test_BidAuthorizationHash_ComputesCorrectly() public view {
        bytes32 castHash = keccak256("test-cast");
        address bidder = address(0x123);
        uint256 bidderFid = 12345; // Example FID
        uint256 amount = 1e6; // 1 USDC
        bytes32 nonce = keccak256("test-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 structHash =
            keccak256(abi.encode(BID_AUTHORIZATION_TYPEHASH, castHash, bidder, bidderFid, amount, nonce, deadline));

        // Compute expected hash manually
        bytes32 domainSeparator = auction.DOMAIN_SEPARATOR();
        bytes32 expectedHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        assertEq(auction.hashBidAuthorization(castHash, bidder, bidderFid, amount, nonce, deadline), expectedHash);
    }

    function testFuzz_BidAuthorizationHash_DifferentInputs(
        bytes32 castHash,
        address bidder,
        uint256 bidderFid,
        uint256 amount,
        bytes32 nonce,
        uint256 deadline
    ) public view {
        bytes32 structHash =
            keccak256(abi.encode(BID_AUTHORIZATION_TYPEHASH, castHash, bidder, bidderFid, amount, nonce, deadline));

        // Compute expected hash manually
        bytes32 domainSeparator = auction.DOMAIN_SEPARATOR();
        bytes32 expectedHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        assertEq(auction.hashBidAuthorization(castHash, bidder, bidderFid, amount, nonce, deadline), expectedHash);
    }

    function test_VerifyBidAuthorization_ValidSignature() public {
        // Setup test values
        bytes32 castHash = keccak256("test-cast");
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6; // 1 USDC
        bytes32 nonce = keccak256("test-nonce-1");
        uint256 deadline = block.timestamp + 1 hours;

        // Generate authorizer key
        (address authorizer, uint256 authorizerKey) = makeAddrAndKey("authorizer");

        // Allow the authorizer
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        // Create the message hash
        bytes32 messageHash = auction.hashBidAuthorization(castHash, bidder, bidderFid, amount, nonce, deadline);

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify the signature
        assertTrue(auction.verifyBidAuthorization(castHash, bidder, bidderFid, amount, nonce, deadline, signature));
    }

    function test_VerifyBidAuthorization_InvalidSignature() public {
        // Setup test values
        bytes32 castHash = keccak256("test-cast");
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("test-nonce-2");
        uint256 deadline = block.timestamp + 1 hours;

        // Generate authorizer key (but don't allow it)
        (, uint256 authorizerKey) = makeAddrAndKey("authorizer");

        // Create the message hash
        bytes32 messageHash = auction.hashBidAuthorization(castHash, bidder, bidderFid, amount, nonce, deadline);

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify should fail since authorizer is not allowed
        assertFalse(auction.verifyBidAuthorization(castHash, bidder, bidderFid, amount, nonce, deadline, signature));
    }

    function test_VerifyBidAuthorization_ExpiredDeadline() public {
        // Setup test values
        bytes32 castHash = keccak256("test-cast");
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("test-nonce-3");
        uint256 deadline = block.timestamp - 1; // Already expired

        // Generate authorizer key
        (address authorizer, uint256 authorizerKey) = makeAddrAndKey("authorizer");

        // Allow the authorizer
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        // Create the message hash
        bytes32 messageHash = auction.hashBidAuthorization(castHash, bidder, bidderFid, amount, nonce, deadline);

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify should fail due to expired deadline
        assertFalse(auction.verifyBidAuthorization(castHash, bidder, bidderFid, amount, nonce, deadline, signature));
    }

    function test_UsedNonces_PublicMapping() public view {
        // Test that usedNonces mapping is accessible
        bytes32 testNonce = keccak256("test-nonce");
        assertFalse(auction.usedNonces(testNonce));
    }

    function test_BidAuthorizationHash_DifferentFids() public view {
        // Test that different FIDs produce different hashes
        bytes32 castHash = keccak256("test-cast");
        address bidder = address(0x123);
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("test-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        // Get hash with FID 12345
        bytes32 hash1 = auction.hashBidAuthorization(castHash, bidder, 12345, amount, nonce, deadline);

        // Get hash with FID 67890
        bytes32 hash2 = auction.hashBidAuthorization(castHash, bidder, 67890, amount, nonce, deadline);

        // Hashes should be different
        assertTrue(hash1 != hash2);
    }

    function test_VerifyBidAuthorization_WrongChainId() public {
        // Setup test values
        BidParams memory params = BidParams({
            castHash: keccak256("test-cast"),
            bidder: address(0x123),
            bidderFid: 12345,
            amount: 1e6,
            nonce: keccak256("test-nonce-4"),
            deadline: block.timestamp + 1 hours
        });

        // Generate authorizer key
        (address authorizer, uint256 authorizerKey) = makeAddrAndKey("authorizer");

        // Deploy auction on different chain
        vm.chainId(999);
        Auction wrongChainAuction = new Auction(MINTER, USDC, TREASURY, address(this));

        // Allow the authorizer on wrong chain auction
        vm.prank(wrongChainAuction.owner());
        wrongChainAuction.allowAuthorizer(authorizer);

        // Create the message hash for wrong chain
        bytes32 messageHash = wrongChainAuction.hashBidAuthorization(
            params.castHash, params.bidder, params.bidderFid, params.amount, params.nonce, params.deadline
        );

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Reset chain id
        vm.chainId(31337);

        // Allow authorizer on correct chain
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        // Verify should fail due to different chain id
        bool result = auction.verifyBidAuthorization(
            params.castHash, params.bidder, params.bidderFid, params.amount, params.nonce, params.deadline, signature
        );
        assertFalse(result);
    }
}
