// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {AuctionTestHelper} from "../shared/AuctionTestHelper.sol";

contract AuctionBidTest is Test, AuctionTestHelper {
    Auction public auction;
    MockERC20 public usdc;

    // Mock addresses
    address public constant MINTER = address(0x2);
    address public constant TREASURY = address(0x4);

    // Test accounts
    address public authorizer;
    uint256 public authorizerKey;

    bytes32 public constant TEST_CAST_HASH = keccak256("test-cast");
    address public constant CREATOR = address(0x789);
    uint256 public constant CREATOR_FID = 67890;

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC");

        // Deploy auction with mock USDC
        auction = new Auction(MINTER, address(usdc), TREASURY);

        // Setup authorizer
        (authorizer, authorizerKey) = makeAddrAndKey("authorizer");
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
    }

    function test_Start_Success() public {
        // Test starting an auction with the first bid
        bytes32 castHash = keccak256("test-cast");
        address creator = address(0x789);
        uint256 creatorFid = 67890;
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6; // 1 USDC
        bytes32 nonce = keccak256("start-nonce-1");
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

    event AuctionStarted(bytes32 indexed castHash, address indexed creator, uint256 creatorFid);
    event BidPlaced(bytes32 indexed castHash, address indexed bidder, uint256 bidderFid, uint256 amount);

    function test_Start_RevertsInvalidProtocolFee() public {
        bytes32 castHash = keccak256("test-cast-invalid-fee");
        address creator = address(0x789);
        uint256 creatorFid = 67890;
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6; // 1 USDC
        bytes32 nonce = keccak256("start-nonce-invalid-fee");
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
            10001 // protocolFee - Invalid: >100%
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

    function test_Start_RevertsBelowMinimum() public {
        bytes32 castHash = keccak256("test-cast-2");
        address creator = address(0x789);
        uint256 creatorFid = 67890;
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 0.5e6; // 0.5 USDC (below minimum)
        bytes32 nonce = keccak256("start-nonce-2");
        uint256 deadline = block.timestamp + 1 hours;

        // Create structs using helper functions
        IAuction.CastData memory castData = createCastData(castHash, creator, creatorFid);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
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
            castHash, creator, creatorFid, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Setup: Give bidder some USDC and approve auction contract
        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        // Try to start auction below minimum
        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidBidAmount.selector);
        auction.start(castData, bidData, params, auth);
    }

    function test_Start_RevertsWithInvalidSignature() public {
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce-invalid-sig");
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

    function test_Start_RevertsWithUsedNonce() public {
        bytes32 castHash = keccak256("test-cast");
        address creator = address(0x789);
        uint256 creatorFid = 67890;
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 reusedNonce = keccak256("reused-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        // First, use the nonce by starting an auction
        IAuction.CastData memory castData1 = createCastData(castHash, creator, creatorFid);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, 1000, 24 hours, 15 minutes, 15 minutes, 1000
        );

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
        bytes32 differentCastHash = keccak256("different-cast");
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


    function test_Start_RevertsWithZeroExtension() public {
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("zero-extension-nonce");
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

    function test_Start_RevertsWithZeroExtensionThreshold() public {
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("zero-threshold-nonce");
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

    function test_Start_RevertsWithLowMinBid() public {
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 0.5e6; // 0.5 USDC
        bytes32 nonce = keccak256("low-minbid-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        // Create params with minBid below MIN_BID_AMOUNT
        IAuction.AuctionParams memory params = IAuction.AuctionParams({
            minBid: 0.5e6, // 0.5 USDC - below MIN_BID_AMOUNT (1e6)
            minBidIncrement: 1000,
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
        
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        auction.start(castData, bidData, params, auth);
    }

    function test_Start_RevertsWithExpiredDeadline() public {
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("expired-deadline-nonce");
        uint256 deadline = block.timestamp - 1; // Already expired

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

    /* TODO: Update these tests for the new start/bid/settle pattern
    function test_OpeningBid_RevertsBelowMinimum() public {
        bytes32 tokenId = keccak256("test-cast");
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 0.5e6; // 0.5 USDC (below minimum)
        bytes32 nonce = keccak256("bid-nonce-2");
        uint256 deadline = block.timestamp + 1 hours;
        
        // Create bid authorization signature
        bytes32 messageHash = auction.hashBidAuthorization(tokenId, bidder, bidderFid, amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Setup: Give bidder some USDC and approve auction contract
        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);
        
        // Try to place bid below minimum
        vm.prank(bidder);
        vm.expectRevert(IAuction.InvalidBidAmount.selector);
        auction.placeBid(tokenId, bidderFid, amount, nonce, deadline, signature);
    }
    
    function test_PlaceBid_RevertsNonceReuse() public {
        bytes32 tokenId = keccak256("test-cast");
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("bid-nonce-3");
        uint256 deadline = block.timestamp + 1 hours;
        
        // Create bid authorization signature
        bytes32 messageHash = auction.hashBidAuthorization(tokenId, bidder, bidderFid, amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Setup: Give bidder some USDC and approve auction contract
        usdc.mint(bidder, amount * 2);
        vm.prank(bidder);
        usdc.approve(address(auction), amount * 2);
        
        // Place first bid
        vm.prank(bidder);
        auction.placeBid(tokenId, bidderFid, amount, nonce, deadline, signature);
        
        // Try to reuse nonce
        vm.prank(bidder);
        vm.expectRevert(IAuction.NonceAlreadyUsed.selector);
        auction.placeBid(tokenId, bidderFid, amount, nonce, deadline, signature);
    }
    
    function test_PlaceBid_RevertsUnauthorizedBidder() public {
        bytes32 tokenId = keccak256("test-cast");
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("bid-nonce-4");
        uint256 deadline = block.timestamp + 1 hours;
        
        // Create bid authorization with wrong bidder
        address wrongBidder = address(0x456);
        bytes32 messageHash = auction.hashBidAuthorization(tokenId, wrongBidder, bidderFid, amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Setup: Give bidder some USDC and approve auction contract
        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);
        
        // Try to place bid with wrong authorization
        vm.prank(bidder);
        vm.expectRevert(IAuction.UnauthorizedBidder.selector);
        auction.placeBid(tokenId, bidderFid, amount, nonce, deadline, signature);
    }
    
    function test_PlaceBid_RevertsExpiredDeadline() public {
        bytes32 tokenId = keccak256("test-cast");
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("bid-nonce-5");
        uint256 deadline = block.timestamp - 1; // Already expired
        
        // Create bid authorization signature
        bytes32 messageHash = auction.hashBidAuthorization(tokenId, bidder, bidderFid, amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Setup: Give bidder some USDC and approve auction contract
        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);
        
        // Try to place bid with expired deadline
        vm.prank(bidder);
        vm.expectRevert(IAuction.UnauthorizedBidder.selector);
        auction.placeBid(tokenId, bidderFid, amount, nonce, deadline, signature);
    }
    */
}
