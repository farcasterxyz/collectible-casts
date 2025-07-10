// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {MockCollectibleCasts} from "../mocks/MockCollectibleCasts.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";

contract AuctionStartTest is Test, AuctionTestHelper {
    Auction public auction;
    MockUSDC public usdc;
    MockCollectibleCasts public collectibleCast;

    // Mock addresses
    address public constant TREASURY = address(0x4);

    // Test accounts
    address public authorizer;
    uint256 public authorizerKey;

    bytes32 public constant TEST_CAST_HASH = keccak256("test-cast");
    address public constant CREATOR = address(0x789);
    uint256 public constant CREATOR_FID = 67890;

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy mock CollectibleCasts
        collectibleCast = new MockCollectibleCasts();

        // Deploy auction with mock CollectibleCasts and USDC
        auction = new Auction(address(collectibleCast), address(usdc), TREASURY, address(this));

        // Allow auction to mint
        collectibleCast.allowMinter(address(auction));

        // Setup authorizer
        (authorizer, authorizerKey) = makeAddrAndKey("authorizer");
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
    }

    function testFuzz_Start_Success(
        bytes32 castHash,
        address creator,
        uint256 creatorFid,
        address bidder,
        uint256 bidderFid,
        uint256 amount,
        bytes32 nonce
    ) public {
        // Bound inputs
        vm.assume(castHash != bytes32(0));
        vm.assume(creator != address(0));
        vm.assume(bidder != address(0));
        vm.assume(creator != bidder); // No self-bidding
        vm.assume(creatorFid != 0);
        vm.assume(bidderFid != 0);
        vm.assume(bidder.code.length == 0); // Ensure bidder is EOA for clean test
        amount = _bound(amount, 1e6, 10000e6); // 1 to 10,000 USDC
        uint256 deadline = block.timestamp + 1 hours;

        // Create structs using helper functions
        IAuction.CastData memory castData = createCastData(castHash, creator, creatorFid);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement (10%)
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        // Create start authorization signature
        bytes32 messageHash = auction.hashStartAuthorization(
            castHash, creator, creatorFid, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Setup: Give bidder some USDC and approve auction contract
        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        // Start auction
        vm.expectEmit(true, true, false, true);
        emit AuctionStarted(castHash, creator, creatorFid);
        vm.expectEmit(true, true, false, true);
        emit BidPlaced(castHash, bidder, bidderFid, amount);

        vm.prank(bidder);
        auction.start(castData, bidData, params, auth);

        // Verify USDC was transferred
        assertEq(usdc.balanceOf(bidder), 0);
        assertEq(usdc.balanceOf(address(auction)), amount);

        // Verify nonce was marked as used
        assertTrue(auction.usedNonces(nonce));
    }

    function test_Start_SetsLastBidAt() public {
        // Setup test parameters
        bytes32 castHash = TEST_CAST_HASH;
        address creator = CREATOR;
        uint256 creatorFid = CREATOR_FID;
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 100e6; // 100 USDC
        bytes32 nonce = keccak256("test-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        // Create structs
        IAuction.CastData memory castData = createCastData(castHash, creator, creatorFid);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement (10%)
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        // Create start authorization signature
        bytes32 messageHash = auction.hashStartAuthorization(
            castHash, creator, creatorFid, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Setup: Give bidder some USDC and approve auction contract
        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        // Record timestamp before start
        uint256 timestampBefore = block.timestamp;

        // Start auction
        vm.prank(bidder);
        auction.start(castData, bidData, params, auth);

        // Verify lastBidAt was set
        (, , , , , uint256 lastBidAt, , , ) = auction.auctions(castHash);
        assertEq(lastBidAt, timestampBefore, "lastBidAt should be set to block.timestamp");
    }

    function testFuzz_Start_Success_ParameterValidation(
        uint256 duration,
        uint256 extension,
        uint256 protocolFee,
        uint256 amount
    ) public {
        // This fuzz test focuses on parameter validation without complex event checking
        // Bound inputs
        amount = _bound(amount, 1e6, 10000e6); // 1 to 10,000 USDC
        duration = _bound(duration, 1 hours, 7 days);
        extension = _bound(extension, 5 minutes, 1 hours);
        protocolFee = _bound(protocolFee, 0, 10000); // 0 to 100%

        // Use fixed addresses to avoid event issues
        bytes32 castHash = keccak256(abi.encodePacked("fuzz", duration, amount));
        address creator = address(0x789);
        uint256 creatorFid = 67890;
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        bytes32 nonce = keccak256(abi.encodePacked("fuzz-nonce", castHash));
        uint256 deadline = block.timestamp + 1 hours;

        // Create structs using helper functions
        IAuction.CastData memory castData = createCastData(castHash, creator, creatorFid);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            amount, // minBid matches first bid
            1000, // minBidIncrement (10%)
            duration,
            extension,
            extension, // extensionThreshold same as extension for simplicity
            protocolFee
        );

        // Create start authorization signature
        bytes32 messageHash = auction.hashStartAuthorization(
            castHash, creator, creatorFid, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Setup: Give bidder some USDC and approve auction contract
        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        // Start auction - should succeed with valid parameters
        vm.prank(bidder);
        auction.start(castData, bidData, params, auth);

        // Verify USDC was transferred
        assertEq(usdc.balanceOf(bidder), 0);
        assertEq(usdc.balanceOf(address(auction)), amount);

        // Verify nonce was marked as used
        assertTrue(auction.usedNonces(nonce));
    }

    event AuctionStarted(bytes32 indexed castHash, address indexed creator, uint256 creatorFid);
    event BidPlaced(bytes32 indexed castHash, address indexed bidder, uint256 bidderFid, uint256 amount);

    function testFuzz_Start_RevertsInvalidProtocolFee(
        bytes32 castHash,
        address creator,
        uint256 creatorFid,
        address bidder,
        uint256 bidderFid,
        uint256 amount,
        bytes32 nonce,
        uint256 invalidFee
    ) public {
        vm.assume(castHash != bytes32(0));
        vm.assume(creator != address(0));
        vm.assume(bidder != address(0));
        vm.assume(creator != bidder);
        vm.assume(creatorFid != 0);
        vm.assume(bidderFid != 0);
        amount = _bound(amount, 1e6, 10000e6);
        invalidFee = _bound(invalidFee, 10001, type(uint256).max); // > 100%
        uint256 deadline = block.timestamp + 1 hours;

        // Create structs using helper functions
        IAuction.CastData memory castData = createCastData(castHash, creator, creatorFid);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        // Auction params with invalid protocol fee (>100%)
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            invalidFee // protocolFee - Invalid: >100%
        );

        // Create start authorization signature
        bytes32 messageHash = auction.hashStartAuthorization(
            castHash, creator, creatorFid, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Setup: Give bidder some USDC and approve auction contract
        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        // Try to start auction with invalid protocol fee
        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidProtocolFee.selector);
        auction.start(castData, bidData, params, auth);
    }

    function testFuzz_Start_RevertsBelowMinimum(
        bytes32 castHash,
        address creator,
        uint256 creatorFid,
        address bidder,
        uint256 bidderFid,
        uint256 belowMinAmount,
        bytes32 nonce
    ) public {
        vm.assume(castHash != bytes32(0));
        vm.assume(creator != address(0));
        vm.assume(bidder != address(0));
        vm.assume(creator != bidder);
        vm.assume(creatorFid != 0);
        vm.assume(bidderFid != 0);
        belowMinAmount = _bound(belowMinAmount, 1, 0.99e6); // Below 1 USDC minimum
        uint256 deadline = block.timestamp + 1 hours;

        // Create structs using helper functions
        IAuction.CastData memory castData = createCastData(castHash, creator, creatorFid);
        IAuction.BidData memory bidData = createBidData(bidderFid, belowMinAmount);
        // Auction params with 1 USDC minimum
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        // Create start authorization signature
        bytes32 messageHash = auction.hashStartAuthorization(
            castHash, creator, creatorFid, bidder, bidderFid, belowMinAmount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Setup: Give bidder some USDC and approve auction contract
        usdc.mint(bidder, belowMinAmount);
        vm.prank(bidder);
        usdc.approve(address(auction), belowMinAmount);

        // Try to start auction below minimum
        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidBidAmount.selector);
        auction.start(castData, bidData, params, auth);
    }

    function testFuzz_Start_RevertsWithInvalidSignature(
        address bidder,
        uint256 bidderFid,
        uint256 amount,
        bytes32 nonce
    ) public {
        vm.assume(bidder != address(0));
        vm.assume(bidder != CREATOR); // Avoid self-bidding error
        vm.assume(bidderFid != 0);
        amount = _bound(amount, 1e6, 10000e6);
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

        // Create invalid signature (malformed)
        bytes memory invalidSignature = abi.encodePacked(bytes32(0), bytes32(0), uint8(0));
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, invalidSignature);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        // Should revert due to invalid signature
        vm.prank(bidder);
        vm.expectRevert(IAuction.UnauthorizedBidder.selector);
        auction.start(castData, bidData, params, auth);
    }

    function testFuzz_Start_RevertsWithUsedNonce(
        bytes32 castHash,
        address creator,
        uint256 creatorFid,
        address bidder,
        uint256 bidderFid,
        uint256 amount,
        bytes32 reusedNonce
    ) public {
        vm.assume(castHash != bytes32(0));
        vm.assume(creator != address(0));
        vm.assume(bidder != address(0));
        vm.assume(creator != bidder);
        vm.assume(creatorFid != 0);
        vm.assume(bidderFid != 0);
        vm.assume(bidder.code.length == 0); // Ensure EOA
        amount = _bound(amount, 1e6, 10000e6);
        uint256 deadline = block.timestamp + 1 hours;

        // First, use the nonce by starting an auction
        IAuction.CastData memory castData1 = createCastData(castHash, creator, creatorFid);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(1e6, 1000, 24 hours, 15 minutes, 15 minutes, 1000);

        bytes32 messageHash1 = auction.hashStartAuthorization(
            castHash, creator, creatorFid, bidder, bidderFid, amount, params, reusedNonce, deadline
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(authorizerKey, messageHash1);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);
        IAuction.AuthData memory auth1 = createAuthData(reusedNonce, deadline, signature1);

        usdc.mint(bidder, amount * 2); // Mint for both attempts
        vm.prank(bidder);
        usdc.approve(address(auction), amount * 2);

        vm.prank(bidder);
        auction.start(castData1, bidData, params, auth1);

        // Now try to start another auction with the same nonce but different cast
        bytes32 differentCastHash = keccak256(abi.encodePacked("different-cast", castHash));
        vm.assume(differentCastHash != castHash); // Ensure different cast hash
        IAuction.CastData memory castData2 = createCastData(differentCastHash, creator, creatorFid);

        bytes32 messageHash2 = auction.hashStartAuthorization(
            differentCastHash, creator, creatorFid, bidder, bidderFid, amount, params, reusedNonce, deadline
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(authorizerKey, messageHash2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);
        IAuction.AuthData memory auth2 = createAuthData(reusedNonce, deadline, signature2);

        // Should revert because nonce is already used
        vm.prank(bidder);
        vm.expectRevert(IAuction.NonceAlreadyUsed.selector);
        auction.start(castData2, bidData, params, auth2);
    }

    function testFuzz_Start_RevertsWithZeroExtension(address bidder, uint256 bidderFid, uint256 amount, bytes32 nonce)
        public
    {
        vm.assume(bidder != address(0));
        vm.assume(bidderFid != 0);
        amount = _bound(amount, 1e6, 10000e6);
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            0, // extension = 0 (invalid)
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
        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        auction.start(castData, bidData, params, auth);
    }

    function testFuzz_Start_RevertsWithZeroExtensionThreshold(
        address bidder,
        uint256 bidderFid,
        uint256 amount,
        bytes32 nonce
    ) public {
        vm.assume(bidder != address(0));
        vm.assume(bidderFid != 0);
        amount = _bound(amount, 1e6, 10000e6);
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            0, // extensionThreshold = 0 (invalid)
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
        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        auction.start(castData, bidData, params, auth);
    }

    function testFuzz_Start_RevertsWithLowMinBid(address bidder, uint256 bidderFid, uint256 lowAmount, bytes32 nonce)
        public
    {
        vm.assume(bidder != address(0));
        vm.assume(bidderFid != 0);
        lowAmount = _bound(lowAmount, 1, 0.99e6); // Below 1 USDC minimum
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, lowAmount);
        // Create params with minBid below MIN_BID_AMOUNT
        IAuction.AuctionParams memory params = IAuction.AuctionParams({
            minBid: lowAmount, // Below MIN_BID_AMOUNT (1e6)
            minBidIncrement: 1000,
            duration: 24 hours,
            extension: 15 minutes,
            extensionThreshold: 15 minutes,
            protocolFee: 1000
        });

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, CREATOR, CREATOR_FID, bidder, bidderFid, lowAmount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(bidder, lowAmount);
        vm.prank(bidder);
        usdc.approve(address(auction), lowAmount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        auction.start(castData, bidData, params, auth);
    }

    function testFuzz_Start_RevertsWithExpiredDeadline(
        address bidder,
        uint256 bidderFid,
        uint256 amount,
        bytes32 nonce,
        uint256 expiredOffset
    ) public {
        vm.assume(bidder != address(0));
        vm.assume(bidder != CREATOR); // Avoid self-bidding error
        vm.assume(bidderFid != 0);
        amount = _bound(amount, 1e6, 10000e6);
        expiredOffset = _bound(expiredOffset, 1, block.timestamp > 365 days ? 365 days : block.timestamp); // Avoid underflow
        uint256 deadline = block.timestamp - expiredOffset; // Already expired

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

        // Create signature with expired deadline
        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, CREATOR, CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        // Should revert due to expired deadline
        vm.prank(bidder);
        vm.expectRevert(IAuction.DeadlineExpired.selector);
        auction.start(castData, bidData, params, auth);
    }
}
