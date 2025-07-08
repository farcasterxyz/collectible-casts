// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";

contract AuctionValidationTest is Test, AuctionTestHelper {
    Auction public auction;
    MockUSDC public usdc;

    address public constant MINTER = address(0x2);
    address public constant TREASURY = address(0x4);

    address public authorizer;
    uint256 public authorizerKey;

    bytes32 public constant TEST_CAST_HASH = keccak256("test-cast");
    address public constant CREATOR = address(0x789);
    uint256 public constant CREATOR_FID = 67890;

    function setUp() public {
        usdc = new MockUSDC();
        auction = new Auction(MINTER, address(usdc), TREASURY, address(this));

        (authorizer, authorizerKey) = makeAddrAndKey("authorizer");
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
    }

    function test_Start_RevertsWithZeroCastHash() public {
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 zeroCastHash = bytes32(0);
        IAuction.CastData memory castData = createCastData(zeroCastHash, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        bytes32 messageHash = auction.hashStartAuthorization(
            zeroCastHash, CREATOR, CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidCastHash.selector);
        auction.start(castData, bidData, params, auth);
    }

    function test_Start_RevertsWithZeroCreator() public {
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, address(0), CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, address(0), CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidAddress.selector);
        auction.start(castData, bidData, params, auth);
    }

    function test_Start_RevertsWithZeroCreatorFid() public {
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, 0);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, CREATOR, 0, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidCreatorFid.selector);
        auction.start(castData, bidData, params, auth);
    }

    function test_Start_RevertsOnSelfBidding() public {
        uint256 creatorFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(creatorFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, CREATOR, CREATOR_FID, CREATOR, creatorFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(CREATOR, amount);
        vm.prank(CREATOR);
        usdc.approve(address(auction), amount);

        vm.prank(CREATOR);
        vm.expectRevert(IAuction.SelfBidding.selector);
        auction.start(castData, bidData, params, auth);
    }

    function test_Start_RevertsWithShortDuration() public {
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.AuctionParams memory params = IAuction.AuctionParams({
            minBid: 1e6,
            minBidIncrement: 1000,
            duration: 30 minutes, // Less than MIN_AUCTION_DURATION
            extension: 15 minutes,
            extensionThreshold: 15 minutes,
            protocolFee: 1000
        });

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, CREATOR, CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        auction.start(castData, bidData, params, auth);
    }

    function test_Start_RevertsWithLongDuration() public {
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.AuctionParams memory params = IAuction.AuctionParams({
            minBid: 1e6,
            minBidIncrement: 1000,
            duration: 31 days, // More than MAX_AUCTION_DURATION
            extension: 15 minutes,
            extensionThreshold: 15 minutes,
            protocolFee: 1000
        });

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, CREATOR, CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        auction.start(castData, bidData, params, auth);
    }

    function test_Start_RevertsWithExtensionGreaterThanDuration() public {
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.AuctionParams memory params = IAuction.AuctionParams({
            minBid: 1e6,
            minBidIncrement: 1000,
            duration: 2 hours,
            extension: 3 hours, // Greater than duration
            extensionThreshold: 15 minutes,
            protocolFee: 1000
        });

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, CREATOR, CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        auction.start(castData, bidData, params, auth);
    }

    function test_Start_RevertsWithHighMinBidIncrement() public {
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.AuctionParams memory params = IAuction.AuctionParams({
            minBid: 1e6,
            minBidIncrement: 10001, // More than 100%
            duration: 24 hours,
            extension: 15 minutes,
            extensionThreshold: 15 minutes,
            protocolFee: 1000
        });

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, CREATOR, CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        auction.start(castData, bidData, params, auth);
    }

    function test_Bid_RevertsOnSelfBidding() public {
        // Start auction first with a different bidder
        address firstBidder = address(0x123);
        uint256 firstBidderFid = 12345;
        uint256 firstAmount = 1e6;
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Try to bid as the creator
        uint256 creatorBidderFid = 99999;
        uint256 creatorAmount = 2e6;
        bytes32 nonce = keccak256("bid-nonce-creator");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, CREATOR, creatorBidderFid, creatorAmount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(CREATOR, creatorAmount);
        vm.prank(CREATOR);
        usdc.approve(address(auction), creatorAmount);

        IAuction.BidData memory bidData = createBidData(creatorBidderFid, creatorAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.prank(CREATOR);
        vm.expectRevert(IAuction.SelfBidding.selector);
        auction.bid(TEST_CAST_HASH, bidData, auth);
    }

    function _startAuction(address bidder, uint256 bidderFid, uint256 amount) internal {
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, CREATOR, CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        auction.start(castData, bidData, params, auth);
    }
}
