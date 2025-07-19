// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "../../src/interfaces/IAuction.sol";
import {AuctionTestBase} from "./AuctionTestBase.sol";

contract AuctionValidationTest is AuctionTestBase {
    function testFuzz_Start_RevertsWithZeroCastHash(address bidder, uint96 bidderFid, uint256 amount, bytes32 nonce)
        public
    {
        vm.assume(bidder != address(0));
        vm.assume(bidder != address(auction));
        vm.assume(bidderFid != 0);
        amount = _bound(amount, 1e6, 10000e6); // 1 to 10,000 USDC
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 zeroCastHash = bytes32(0);
        IAuction.CastData memory castData = createCastData(zeroCastHash, DEFAULT_CREATOR, DEFAULT_CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            amount, // minBid matches first bid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        bytes32 messageHash = auction.hashStartAuthorization(
            zeroCastHash, DEFAULT_CREATOR, DEFAULT_CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidCastHash.selector);
        auction.start(castData, bidData, params, auth);
    }

    function testFuzz_Start_RevertsWithZeroCreator(
        bytes32 castHash,
        address bidder,
        uint96 bidderFid,
        uint256 amount,
        bytes32 nonce
    ) public {
        vm.assume(castHash != bytes32(0));
        vm.assume(bidder != address(0));
        vm.assume(bidderFid != 0);
        amount = _bound(amount, 1e6, 10000e6);
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(castHash, address(0), DEFAULT_CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            amount, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        bytes32 messageHash = auction.hashStartAuthorization(
            castHash, address(0), DEFAULT_CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidAddress.selector);
        auction.start(castData, bidData, params, auth);
    }

    function testFuzz_Start_RevertsWithZeroCreatorFid(
        bytes32 castHash,
        address creator,
        address bidder,
        uint96 bidderFid,
        uint256 amount,
        bytes32 nonce
    ) public {
        vm.assume(castHash != bytes32(0));
        vm.assume(creator != address(0));
        vm.assume(bidder != address(0));
        vm.assume(bidderFid != 0);
        amount = _bound(amount, 1e6, 10000e6);
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(castHash, creator, 0);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            amount, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        bytes32 messageHash =
            auction.hashStartAuthorization(castHash, creator, 0, bidder, bidderFid, amount, params, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidCreatorFid.selector);
        auction.start(castData, bidData, params, auth);
    }

    function testFuzz_Start_AllowsSelfBidding(
        bytes32 castHash,
        address creator,
        uint96 creatorFid,
        uint96 bidderFid,
        uint256 amount,
        bytes32 nonce
    ) public {
        vm.assume(castHash != bytes32(0));
        vm.assume(creator != address(0));
        vm.assume(creatorFid != 0);
        vm.assume(bidderFid != 0);
        amount = _bound(amount, 1e6, 10000e6);
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(castHash, creator, creatorFid);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            amount, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        bytes32 messageHash = auction.hashStartAuthorization(
            castHash, creator, creatorFid, creator, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(creator, amount);
        vm.prank(creator);
        usdc.approve(address(auction), amount);

        // Should succeed - self-bidding is now allowed
        vm.prank(creator);
        auction.start(castData, bidData, params, auth);

        // Verify auction was created with creator as bidder
        (address auctionCreator,, address highestBidder,,,,,,,) = auction.auctions(castHash);
        assertEq(auctionCreator, creator);
        assertEq(highestBidder, creator);
    }

    function testFuzz_Start_RevertsWithShortDuration(
        address bidder,
        uint96 bidderFid,
        uint256 amount,
        bytes32 nonce,
        uint256 shortDuration
    ) public {
        vm.assume(bidder != address(0));
        vm.assume(bidderFid != 0);
        amount = _bound(amount, 1e6, 10000e6);
        shortDuration = _bound(shortDuration, 1, 59 minutes); // Less than MIN_AUCTION_DURATION (1 hour)
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.AuctionParams memory params = IAuction.AuctionParams({
            minBid: uint64(amount),
            minBidIncrementBps: uint16(1000),
            duration: uint32(shortDuration),
            extension: uint32(15 minutes),
            extensionThreshold: uint32(15 minutes),
            protocolFeeBps: uint16(1000)
        });

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        auction.start(castData, bidData, params, auth);
    }

    function test_Start_RevertsWithLongDuration() public {
        address bidder = address(0x123);
        uint96 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.AuctionParams memory params = IAuction.AuctionParams({
            minBid: uint64(1e6),
            minBidIncrementBps: uint16(1000),
            duration: uint32(31 days), // More than MAX_AUCTION_DURATION
            extension: uint32(15 minutes),
            extensionThreshold: uint32(15 minutes),
            protocolFeeBps: uint16(1000)
        });

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        auction.start(castData, bidData, params, auth);
    }

    function test_Start_RevertsWithExtensionGreaterThanDuration() public {
        address bidder = address(0x123);
        uint96 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.AuctionParams memory params = IAuction.AuctionParams({
            minBid: uint64(1e6),
            minBidIncrementBps: uint16(1000),
            duration: uint32(2 hours),
            extension: uint32(3 hours), // Greater than duration
            extensionThreshold: uint32(15 minutes),
            protocolFeeBps: uint16(1000)
        });

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        auction.start(castData, bidData, params, auth);
    }

    function test_Start_RevertsWithHighMinBidIncrement() public {
        address bidder = address(0x123);
        uint96 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.AuctionParams memory params = IAuction.AuctionParams({
            minBid: uint64(1e6),
            minBidIncrementBps: uint16(10001), // More than 100%
            duration: uint32(24 hours),
            extension: uint32(15 minutes),
            extensionThreshold: uint32(15 minutes),
            protocolFeeBps: uint16(1000)
        });

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        auction.start(castData, bidData, params, auth);
    }
}
