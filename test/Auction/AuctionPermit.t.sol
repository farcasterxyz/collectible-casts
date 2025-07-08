// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockUSDCWithPermit} from "../mocks/MockUSDCWithPermit.sol";
import {AuctionTestHelper} from "../shared/AuctionTestHelper.sol";

contract AuctionPermitTest is Test, AuctionTestHelper {
    Auction public auction;
    MockUSDCWithPermit public usdc;

    address public constant MINTER = address(0x2);
    address public constant TREASURY = address(0x4);

    address public authorizer;
    uint256 public authorizerKey;

    bytes32 public constant TEST_CAST_HASH = keccak256("test-cast");
    address public constant CREATOR = address(0x789);
    uint256 public constant CREATOR_FID = 67890;

    // Permit signature domain
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        usdc = new MockUSDCWithPermit();
        auction = new Auction(MINTER, address(usdc), TREASURY);

        (authorizer, authorizerKey) = makeAddrAndKey("authorizer");
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
    }

    function test_StartWithPermit_Success() public {
        (address bidder, uint256 bidderKey) = makeAddrAndKey("bidder");
        uint256 bidderFid = 12345;
        uint256 amount = 1e6; // 1 USDC
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

        // Create auction start authorization
        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, CREATOR, CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Create permit signature
        uint256 permitDeadline = block.timestamp + 1 hours;
        bytes32 permitHash = _getPermitHash(bidder, address(auction), amount, 0, permitDeadline);
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(bidderKey, permitHash);
        
        IAuction.PermitData memory permit = createPermitData(permitDeadline, permitV, permitR, permitS);

        // Give bidder USDC but don't approve
        usdc.mint(bidder, amount);

        // Verify no approval exists
        assertEq(usdc.allowance(bidder, address(auction)), 0);

        // Start auction with permit
        vm.prank(bidder);
        auction.start(castData, bidData, params, auth, permit);

        // Verify auction started and USDC transferred
        assertEq(usdc.balanceOf(address(auction)), amount);
        assertEq(usdc.balanceOf(bidder), 0);
    }

    function test_BidWithPermit_Success() public {
        // Start auction first
        address firstBidder = address(0x123);
        uint256 firstBidderFid = 12345;
        uint256 firstAmount = 1e6;
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Second bidder with permit
        (address secondBidder, uint256 secondBidderKey) = makeAddrAndKey("secondBidder");
        uint256 secondBidderFid = 54321;
        uint256 secondAmount = 2e6; // 2 USDC
        bytes32 nonce = keccak256("bid-nonce-1");
        uint256 deadline = block.timestamp + 1 hours;

        // Create bid authorization
        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, secondAmount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Create permit signature
        uint256 permitDeadline = block.timestamp + 1 hours;
        bytes32 permitHash = _getPermitHash(secondBidder, address(auction), secondAmount, 0, permitDeadline);
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(secondBidderKey, permitHash);

        // Give second bidder USDC but don't approve
        usdc.mint(secondBidder, secondAmount);

        // Verify no approval exists
        assertEq(usdc.allowance(secondBidder, address(auction)), 0);

        // Record first bidder's balance before bid
        uint256 firstBidderBalanceBefore = usdc.balanceOf(firstBidder);

        IAuction.BidData memory bidData = createBidData(secondBidderFid, secondAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        IAuction.PermitData memory permit = createPermitData(permitDeadline, permitV, permitR, permitS);

        // Place bid with permit
        vm.prank(secondBidder);
        auction.bid(TEST_CAST_HASH, bidData, auth, permit);

        // Verify bid succeeded
        assertEq(usdc.balanceOf(address(auction)), secondAmount);
        assertEq(usdc.balanceOf(secondBidder), 0);
        assertEq(usdc.balanceOf(firstBidder), firstBidderBalanceBefore + firstAmount); // Refunded
    }

    function test_StartWithPermit_ExpiredPermit() public {
        (address bidder, uint256 bidderKey) = makeAddrAndKey("bidder");
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
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

        // Create expired permit signature
        uint256 permitDeadline = block.timestamp - 1; // Already expired
        bytes32 permitHash = _getPermitHash(bidder, address(auction), amount, 0, permitDeadline);
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(bidderKey, permitHash);
        
        IAuction.PermitData memory permit = createPermitData(permitDeadline, permitV, permitR, permitS);

        usdc.mint(bidder, amount);

        // Should revert with InsufficientAllowance since permit fails and no approval exists
        vm.prank(bidder);
        vm.expectRevert(IAuction.InsufficientAllowance.selector);
        auction.start(castData, bidData, params, auth, permit);
    }

    function test_StartWithPermit_FallbackToApproval() public {
        (address bidder, uint256 bidderKey) = makeAddrAndKey("bidder");
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
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

        // Give invalid permit signature but approve normally
        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        // Use invalid permit signature
        uint256 permitDeadline = block.timestamp + 1 hours;
        uint8 permitV = 27;
        bytes32 permitR = bytes32(uint256(1));
        bytes32 permitS = bytes32(uint256(2));
        
        IAuction.PermitData memory permit = createPermitData(permitDeadline, permitV, permitR, permitS);

        // Should succeed using approval
        vm.prank(bidder);
        auction.start(castData, bidData, params, auth, permit);

        assertEq(usdc.balanceOf(address(auction)), amount);
    }

    function test_BidWithPermit_PermitAlreadyUsed() public {
        // Start auction first
        address firstBidder = address(0x123);
        uint256 firstBidderFid = 12345;
        uint256 firstAmount = 1e6;
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Second bidder setup
        (address secondBidder, uint256 secondBidderKey) = makeAddrAndKey("secondBidder");
        uint256 secondBidderFid = 54321;
        uint256 amount = 2e6;

        // Create permit signature
        uint256 permitDeadline = block.timestamp + 1 hours;
        bytes32 permitHash = _getPermitHash(secondBidder, address(auction), amount, 0, permitDeadline);
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(secondBidderKey, permitHash);

        // Use permit directly first
        usdc.mint(secondBidder, amount * 2); // Mint extra for second attempt
        vm.prank(secondBidder);
        usdc.permit(secondBidder, address(auction), amount, permitDeadline, permitV, permitR, permitS);

        // Now try to bid with same permit (should succeed using existing approval)
        bytes32 nonce = keccak256("bid-nonce-1");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.BidData memory bidData = createBidData(secondBidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        IAuction.PermitData memory permit = createPermitData(permitDeadline, permitV, permitR, permitS);

        vm.prank(secondBidder);
        auction.bid(TEST_CAST_HASH, bidData, auth, permit);

        // Should succeed using the approval from the already-used permit
        assertEq(usdc.balanceOf(address(auction)), amount);
    }

    function test_StartWithPermit_FailsWhenInsufficientAllowanceAfterPermitFail() public {
        (address bidder,) = makeAddrAndKey("bidder-no-allowance");
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce-permit-fail");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, 1000, 24 hours, 15 minutes, 15 minutes, 1000
        );

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, CREATOR, CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Create invalid permit data that will fail
        IAuction.PermitData memory invalidPermit = createPermitData(
            block.timestamp + 1 hours, // deadline
            27, // v (invalid)
            bytes32(uint256(1)), // r (invalid)
            bytes32(uint256(2)) // s (invalid)
        );

        // Give bidder USDC but don't approve and use invalid permit
        usdc.mint(bidder, amount);
        // No approval and invalid permit should cause InsufficientAllowance error

        vm.prank(bidder);
        vm.expectRevert(IAuction.InsufficientAllowance.selector);
        auction.start(castData, bidData, params, auth, invalidPermit);
    }

    function test_BidWithPermit_FailsWhenInsufficientAllowanceAfterPermitFail() public {
        // Start auction first
        address firstBidder = address(0x123);
        uint256 firstBidderFid = 12345;
        uint256 firstAmount = 1e6;
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Second bidder with invalid permit and no approval
        (address secondBidder,) = makeAddrAndKey("secondBidder-no-allowance");
        uint256 secondBidderFid = 54321;
        uint256 secondAmount = 2e6; // 2 USDC
        bytes32 nonce = keccak256("bid-nonce-permit-fail");
        uint256 deadline = block.timestamp + 1 hours;

        // Create bid authorization
        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, secondAmount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.BidData memory bidData = createBidData(secondBidderFid, secondAmount);
        IAuction.AuthData memory authData = createAuthData(nonce, deadline, signature);

        // Create invalid permit signature
        IAuction.PermitData memory invalidPermit = createPermitData(
            block.timestamp + 1 hours, // deadline
            27, // v (invalid)
            bytes32(uint256(1)), // r (invalid)
            bytes32(uint256(2)) // s (invalid)
        );

        // Give second bidder USDC but don't approve
        usdc.mint(secondBidder, secondAmount);

        // Verify no approval exists
        assertEq(usdc.allowance(secondBidder, address(auction)), 0);

        // Should revert with InsufficientAllowance since permit fails and no approval exists
        vm.prank(secondBidder);
        vm.expectRevert(IAuction.InsufficientAllowance.selector);
        auction.bid(TEST_CAST_HASH, bidData, authData, invalidPermit);
    }

    // Helper functions
    function _getPermitHash(address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));

        return keccak256(abi.encodePacked("\x19\x01", usdc.DOMAIN_SEPARATOR(), structHash));
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
