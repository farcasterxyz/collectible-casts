// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "../../src/interfaces/IAuction.sol";
import {ICollectibleCasts} from "../../src/interfaces/ICollectibleCasts.sol";
import {CollectibleCasts} from "../../src/CollectibleCasts.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {AuctionTestBase} from "./AuctionTestBase.sol";
import {Auction} from "../../src/Auction.sol";

contract AuctionTest is AuctionTestBase {
    event AuthorizerAllowed(address indexed authorizer);
    event AuthorizerDenied(address indexed authorizer);
    event TreasurySet(address indexed oldTreasury, address indexed newTreasury);

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 public constant BID_AUTHORIZATION_TYPEHASH = keccak256(
        "BidAuthorization(bytes32 castHash,address bidder,uint96 bidderFid,uint256 amount,bytes32 nonce,uint256 deadline)"
    );

    function test_Constructor_SetsConfiguration() public view {
        assertEq(address(auction.collectible()), address(collectibleCast));
        assertEq(address(auction.usdc()), address(usdc));
        assertEq(auction.treasury(), treasury);

        (uint32 minBidAmount, uint32 minAuctionDuration, uint32 maxAuctionDuration, uint32 maxExtension) =
            auction.config();
        assertEq(minBidAmount, 1e6);
        assertEq(minAuctionDuration, 1 hours);
        assertEq(maxAuctionDuration, 30 days);
        assertEq(maxExtension, 24 hours);
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(auction.owner(), owner);
    }

    function test_Constructor_RevertsIfCollectibleCastsIsZero() public {
        vm.expectRevert(IAuction.InvalidAddress.selector);
        new Auction(address(0), address(usdc), treasury, owner);
    }

    function test_Constructor_RevertsIfUSDCIsZero() public {
        vm.expectRevert(IAuction.InvalidAddress.selector);
        new Auction(address(collectibleCast), address(0), treasury, owner);
    }

    function test_Constructor_RevertsIfTreasuryIsZero() public {
        vm.expectRevert(IAuction.InvalidAddress.selector);
        new Auction(address(collectibleCast), address(usdc), address(0), owner);
    }

    function testFuzz_AllowAuthorizer_OnlyOwner(address authorizer, address notOwner) public {
        vm.assume(authorizer != address(0));
        vm.assume(notOwner != auction.owner());
        vm.assume(notOwner != address(0));

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        auction.allowAuthorizer(authorizer);
    }

    function testFuzz_AllowAuthorizer_EmitsEvent(address authorizer) public {
        vm.assume(authorizer != address(0));

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

    function testFuzz_DenyAuthorizer_OnlyOwner(address authorizer, address notOwner) public {
        vm.assume(authorizer != address(0));
        vm.assume(notOwner != auction.owner());
        vm.assume(notOwner != address(0));

        // First allow the authorizer
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        // Try to deny as non-owner
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        auction.denyAuthorizer(authorizer);
    }

    function testFuzz_DenyAuthorizer_EmitsEvent(address authorizer) public {
        vm.assume(authorizer != address(0));

        // First allow the authorizer
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        // Then deny with event check
        vm.expectEmit(true, false, false, false);
        emit AuthorizerDenied(authorizer);

        vm.prank(auction.owner());
        auction.denyAuthorizer(authorizer);
    }

    function testFuzz_SetTreasury_OnlyOwner(address newTreasury, address notOwner) public {
        vm.assume(newTreasury != address(0));
        vm.assume(notOwner != auction.owner());
        vm.assume(notOwner != address(0));

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        auction.setTreasury(newTreasury);
    }

    function testFuzz_SetTreasury_EmitsEvent(address newTreasury) public {
        vm.assume(newTreasury != address(0));

        vm.expectEmit(true, true, false, false);
        emit TreasurySet(treasury, newTreasury);

        vm.prank(auction.owner());
        auction.setTreasury(newTreasury);
    }

    function test_SetTreasury_RevertsIfZeroAddress() public {
        vm.prank(auction.owner());
        vm.expectRevert(IAuction.InvalidAddress.selector);
        auction.setTreasury(address(0));
    }

    function testFuzz_AllowAuthorizer_UpdatesAllowlist(address authorizer) public {
        vm.assume(authorizer != address(0));

        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        assertTrue(auction.authorizers(authorizer));
    }

    function testFuzz_DenyAuthorizer_UpdatesAllowlist(address authorizer) public {
        vm.assume(authorizer != address(0));

        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
        assertTrue(auction.authorizers(authorizer));

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

    function testFuzz_DenyAuthorizer_NotPreviouslyAllowed(address authorizerToDeny) public {
        vm.assume(authorizerToDeny != address(0));
        vm.assume(authorizerToDeny != authorizer); // Not the already-allowed authorizer from base setup

        assertFalse(auction.authorizers(authorizerToDeny));

        // Deny without allowing first
        vm.expectEmit(true, false, false, false);
        emit AuthorizerDenied(authorizerToDeny);

        vm.prank(auction.owner());
        auction.denyAuthorizer(authorizerToDeny);

        // Still false
        assertFalse(auction.authorizers(authorizerToDeny));
    }

    function testFuzz_SetAuctionConfig_OnlyOwner(address notOwner) public {
        vm.assume(notOwner != owner);
        IAuction.AuctionConfig memory newConfig = IAuction.AuctionConfig({
            minBidAmount: uint32(2e6),
            minAuctionDuration: uint32(2 hours),
            maxAuctionDuration: uint32(14 days),
            maxExtension: uint32(12 hours)
        });

        // Non-owner should fail
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        auction.setAuctionConfig(newConfig);

        // Owner should succeed
        vm.prank(auction.owner());
        auction.setAuctionConfig(newConfig);

        // Verify config was updated
        (uint32 minBidAmount, uint32 minAuctionDuration, uint32 maxAuctionDuration, uint32 maxExtension) =
            auction.config();
        assertEq(minBidAmount, 2e6);
        assertEq(minAuctionDuration, 2 hours);
        assertEq(maxAuctionDuration, 14 days);
        assertEq(maxExtension, 12 hours);
    }

    function test_SetAuctionConfig_EmitsEvent() public {
        IAuction.AuctionConfig memory newConfig = IAuction.AuctionConfig({
            minBidAmount: uint32(2e6),
            minAuctionDuration: uint32(2 hours),
            maxAuctionDuration: uint32(14 days),
            maxExtension: uint32(12 hours)
        });

        vm.expectEmit(true, true, true, true);
        emit IAuction.AuctionConfigSet(newConfig);

        vm.prank(auction.owner());
        auction.setAuctionConfig(newConfig);
    }

    function test_SetAuctionConfig_ValidatesInput() public {
        IAuction.AuctionConfig memory invalidConfig = IAuction.AuctionConfig({
            minBidAmount: 0,
            minAuctionDuration: 1 hours,
            maxAuctionDuration: 30 days,
            maxExtension: 24 hours
        });

        vm.prank(auction.owner());
        vm.expectRevert(abi.encodeWithSelector(IAuction.InvalidAuctionParams.selector));
        auction.setAuctionConfig(invalidConfig);

        // Test maxAuctionDuration <= minAuctionDuration
        invalidConfig.minBidAmount = 1e6;
        invalidConfig.maxAuctionDuration = 1 hours;

        vm.prank(auction.owner());
        vm.expectRevert(abi.encodeWithSelector(IAuction.InvalidAuctionParams.selector));
        auction.setAuctionConfig(invalidConfig);

        // Test minAuctionDuration == 0
        invalidConfig = IAuction.AuctionConfig({
            minBidAmount: 1e6,
            minAuctionDuration: 0,
            maxAuctionDuration: 30 days,
            maxExtension: 24 hours
        });

        vm.prank(auction.owner());
        vm.expectRevert(abi.encodeWithSelector(IAuction.InvalidAuctionParams.selector));
        auction.setAuctionConfig(invalidConfig);

        // Test maxExtension == 0
        invalidConfig = IAuction.AuctionConfig({
            minBidAmount: 1e6,
            minAuctionDuration: 1 hours,
            maxAuctionDuration: 30 days,
            maxExtension: 0
        });

        vm.prank(auction.owner());
        vm.expectRevert(abi.encodeWithSelector(IAuction.InvalidAuctionParams.selector));
        auction.setAuctionConfig(invalidConfig);
    }

    function testFuzz_TransferOwnership_TwoStep(address newOwner) public {
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != auction.owner());

        // Start transfer
        vm.prank(auction.owner());
        auction.transferOwnership(newOwner);

        // Ownership not transferred yet
        assertEq(auction.owner(), owner);
        assertEq(auction.pendingOwner(), newOwner);

        // Accept ownership
        vm.prank(newOwner);
        auction.acceptOwnership();

        // Now ownership is transferred
        assertEq(auction.owner(), newOwner);
        assertEq(auction.pendingOwner(), address(0));
    }

    function testFuzz_AcceptOwnership_RevertsIfNotPendingOwner(address notPendingOwner) public {
        vm.assume(notPendingOwner != address(0));
        vm.assume(notPendingOwner != auction.pendingOwner());

        vm.prank(notPendingOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notPendingOwner));
        auction.acceptOwnership();
    }

    // EIP-712 tests
    function test_DomainSeparator_ComputesCorrectly() public view {
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256("CollectibleCastsAuction"), keccak256("1"), block.chainid, address(auction)
            )
        );

        assertEq(auction.DOMAIN_SEPARATOR(), expectedDomainSeparator);
    }

    function test_Constructor_SetsDomainSeparator() public {
        CollectibleCasts newCollectibleCasts = new CollectibleCasts(address(this), "https://example.com");
        Auction newAuction = new Auction(address(newCollectibleCasts), USDC, treasury, owner);

        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256("CollectibleCastsAuction"),
                keccak256("1"),
                block.chainid,
                address(newAuction)
            )
        );

        assertEq(newAuction.DOMAIN_SEPARATOR(), expectedDomainSeparator);
    }

    // Bid Authorization tests
    function testFuzz_BidAuthorizationHash_ComputesCorrectly(
        bytes32 castHash,
        address bidder,
        uint96 bidderFid,
        uint256 amount,
        bytes32 nonce,
        uint256 deadline
    ) public view {
        bytes32 structHash =
            keccak256(abi.encode(BID_AUTHORIZATION_TYPEHASH, castHash, bidder, bidderFid, amount, nonce, deadline));

        bytes32 domainSeparator = auction.DOMAIN_SEPARATOR();
        bytes32 expectedHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        assertEq(auction.hashBidAuthorization(castHash, bidder, bidderFid, amount, nonce, deadline), expectedHash);
    }

    function testFuzz_UsedNonces_PublicMapping(bytes32 testNonce) public view {
        assertFalse(auction.usedNonces(testNonce));
    }
}
