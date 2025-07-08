// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {Minter} from "../../src/Minter.sol";
import {CollectibleCast} from "../../src/CollectibleCast.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";

contract AuctionBidTest is Test, AuctionTestHelper {
    Auction public auction;
    MockUSDC public usdc;
    Minter public minter;
    CollectibleCast public collectibleCast;

    address public constant TREASURY = address(0x4);

    address public authorizer;
    uint256 public authorizerKey;

    bytes32 public constant TEST_CAST_HASH = keccak256("test-cast");
    address public constant CREATOR = address(0x789);
    uint256 public constant CREATOR_FID = 67890;

    function setUp() public {
        usdc = new MockUSDC();
        
        // Deploy real contracts
        address owner = address(this);
        minter = new Minter(owner);
        collectibleCast = new CollectibleCast(
            owner,
            address(minter),
            address(0), // metadata - not needed for auction tests
            address(0), // transferValidator - not needed
            address(0)  // royalties - not needed
        );
        
        // Configure real contracts
        minter.setToken(address(collectibleCast));
        auction = new Auction(address(minter), address(usdc), TREASURY, address(this));
        minter.allow(address(auction));

        (authorizer, authorizerKey) = makeAddrAndKey("authorizer");
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
    }

    function testFuzz_Bid_Success(address firstBidder, uint256 firstBidderFid, uint256 firstAmount, address secondBidder, uint256 secondBidderFid, uint256 bidIncrement) public {
        // Bound inputs
        vm.assume(firstBidder != address(0) && secondBidder != address(0));
        vm.assume(firstBidder != secondBidder);
        vm.assume(firstBidder != address(auction) && secondBidder != address(auction));
        vm.assume(firstBidder != CREATOR && secondBidder != CREATOR); // Can't be the creator
        firstBidderFid = _bound(firstBidderFid, 1, type(uint256).max);
        secondBidderFid = _bound(secondBidderFid, 1, type(uint256).max);
        firstAmount = _bound(firstAmount, 1e6, 1000e6); // 1 to 1000 USDC
        // Calculate minimum increment (10% of firstAmount)
        uint256 minIncrement = (firstAmount * 1000) / 10000; // 10%
        if (minIncrement < 1e6) minIncrement = 1e6; // At least 1 USDC
        bidIncrement = _bound(bidIncrement, minIncrement, 100e6);
        uint256 secondAmount = firstAmount + bidIncrement;
        
        // Start auction first
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Second bidder places higher bid
        bytes32 nonce = keccak256(abi.encodePacked("bid-nonce", secondBidder, secondAmount));
        uint256 deadline = block.timestamp + 1 hours;

        // Create bid authorization
        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, secondAmount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Give second bidder USDC and approve
        usdc.mint(secondBidder, secondAmount);
        vm.prank(secondBidder);
        usdc.approve(address(auction), secondAmount);

        // Record first bidder's balance before bid
        uint256 firstBidderBalanceBefore = usdc.balanceOf(firstBidder);

        // Place bid
        IAuction.BidData memory bidData = createBidData(secondBidderFid, secondAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectEmit(true, true, false, true);
        emit BidPlaced(TEST_CAST_HASH, secondBidder, secondBidderFid, secondAmount);

        vm.prank(secondBidder);
        auction.bid(TEST_CAST_HASH, bidData, auth);

        // Verify first bidder got refunded
        assertEq(usdc.balanceOf(firstBidder), firstBidderBalanceBefore + firstAmount);

        // Verify USDC balances
        assertEq(usdc.balanceOf(secondBidder), 0);
        assertEq(usdc.balanceOf(address(auction)), secondAmount);
    }

    function test_Bid_InsufficientIncrement() public {
        // Start auction
        address firstBidder = address(0x123);
        uint256 firstBidderFid = 12345;
        uint256 firstAmount = 1e6;
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Try to bid with insufficient increment
        address secondBidder = address(0x456);
        uint256 secondBidderFid = 54321;
        uint256 secondAmount = 1.5e6; // Only 0.5 USDC higher (minimum increment is 1 USDC)
        bytes32 nonce = keccak256("bid-nonce-2");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, secondAmount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(secondBidder, secondAmount);
        vm.prank(secondBidder);
        usdc.approve(address(auction), secondAmount);

        IAuction.BidData memory bidData = createBidData(secondBidderFid, secondAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.prank(secondBidder);
        vm.expectRevert(IAuction.InvalidBidAmount.selector);
        auction.bid(TEST_CAST_HASH, bidData, auth);
    }

    function testFuzz_Bid_ExtendAuction(uint256 timeBeforeEnd, address secondBidder, uint256 secondBidderFid, uint256 bidAmount) public {
        // Bound inputs
        timeBeforeEnd = _bound(timeBeforeEnd, 1, 15 minutes - 1); // Within extension threshold
        vm.assume(secondBidder != address(0));
        vm.assume(secondBidder != address(0x123)); // Can't be same as first bidder
        vm.assume(secondBidder != CREATOR); // Can't be the creator
        secondBidderFid = _bound(secondBidderFid, 1, type(uint256).max);
        bidAmount = _bound(bidAmount, 2e6, 1000e6); // At least 2 USDC to outbid initial 1 USDC
        
        // Start auction
        address firstBidder = address(0x123);
        uint256 firstBidderFid = 12345;
        uint256 firstAmount = 1e6;
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Fast forward to within extension threshold
        vm.warp(block.timestamp + 24 hours - timeBeforeEnd);

        // Place bid
        bytes32 nonce = keccak256(abi.encodePacked("bid-extend", secondBidder, bidAmount));
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, bidAmount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(secondBidder, bidAmount);
        vm.prank(secondBidder);
        usdc.approve(address(auction), bidAmount);

        // We don't check the exact new end time since it depends on the contract's stored value
        // Just verify that the extension event is emitted
        IAuction.BidData memory bidData = createBidData(secondBidderFid, bidAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectEmit(true, false, false, false);
        emit AuctionExtended(TEST_CAST_HASH, 0); // Don't check the data

        vm.prank(secondBidder);
        auction.bid(TEST_CAST_HASH, bidData, auth);

        // Verify auction was extended (we'll check this via events for now)
    }

    function test_Bid_RevertsNonceReuse() public {
        // Start auction
        address firstBidder = address(0x123);
        uint256 firstBidderFid = 12345;
        uint256 firstAmount = 1e6;
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Try to bid with a reused nonce
        address secondBidder = address(0x456);
        uint256 secondBidderFid = 54321;
        uint256 secondAmount = 1.1e6;
        bytes32 nonce = keccak256("start-nonce"); // Reuse the start nonce
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, secondAmount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(secondBidder, secondAmount);
        vm.prank(secondBidder);
        usdc.approve(address(auction), secondAmount);

        IAuction.BidData memory bidData = createBidData(secondBidderFid, secondAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.prank(secondBidder);
        vm.expectRevert(IAuction.NonceAlreadyUsed.selector);
        auction.bid(TEST_CAST_HASH, bidData, auth);
    }

    function test_Bid_RevertsExpiredDeadline() public {
        // Start auction
        address firstBidder = address(0x123);
        uint256 firstBidderFid = 12345;
        uint256 firstAmount = 1e6;
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Try to bid with expired deadline
        address secondBidder = address(0x456);
        uint256 secondBidderFid = 54321;
        uint256 secondAmount = 1.1e6;
        bytes32 nonce = keccak256("bid-nonce-expired");
        uint256 deadline = block.timestamp - 1; // Already expired

        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, secondAmount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(secondBidder, secondAmount);
        vm.prank(secondBidder);
        usdc.approve(address(auction), secondAmount);

        IAuction.BidData memory bidData = createBidData(secondBidderFid, secondAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.prank(secondBidder);
        vm.expectRevert(IAuction.UnauthorizedBidder.selector);
        auction.bid(TEST_CAST_HASH, bidData, auth);
    }

    function test_Bid_RevertsOnNonExistentAuction() public {
        bytes32 nonExistentTokenId = keccak256("non-existent");
        address bidder = address(0x456);
        uint256 bidderFid = 54321;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("bid-nonce-ne");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash =
            auction.hashBidAuthorization(nonExistentTokenId, bidder, bidderFid, amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.prank(bidder);
        vm.expectRevert(IAuction.AuctionDoesNotExist.selector);
        auction.bid(nonExistentTokenId, bidData, auth);
    }

    function test_Bid_RevertsOnSettledAuction() public {
        // Start an auction first
        address firstBidder = address(0x123);
        uint256 firstBidderFid = 12345;
        uint256 firstAmount = 1e6;
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Fast forward past end time and settle
        vm.warp(block.timestamp + 25 hours);
        auction.settle(TEST_CAST_HASH);

        // Now try to bid on the settled auction
        address secondBidder = address(0x456);
        uint256 secondBidderFid = 54321;
        uint256 secondAmount = 2e6;
        bytes32 nonce = keccak256("bid-nonce-settled");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, secondAmount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.BidData memory bidData = createBidData(secondBidderFid, secondAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(secondBidder, secondAmount);
        vm.prank(secondBidder);
        usdc.approve(address(auction), secondAmount);

        // Should revert because auction is already settled
        vm.prank(secondBidder);
        vm.expectRevert(IAuction.AuctionAlreadySettled.selector);
        auction.bid(TEST_CAST_HASH, bidData, auth);
    }

    event BidPlaced(bytes32 indexed castHash, address indexed bidder, uint256 bidderFid, uint256 amount);
    event AuctionExtended(bytes32 indexed castHash, uint256 newEndTime);

    function _startAuction(address bidder, uint256 bidderFid, uint256 amount) internal {
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement (10%)
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
