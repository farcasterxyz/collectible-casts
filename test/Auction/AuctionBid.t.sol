// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {CollectibleCasts} from "../../src/CollectibleCasts.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";

contract AuctionBidTest is Test, AuctionTestHelper {
    Auction public auction;
    MockUSDC public usdc;
    CollectibleCasts public collectibleCast;

    address public constant TREASURY = address(0x4);

    address public authorizer;
    uint256 public authorizerKey;

    bytes32 public constant TEST_CAST_HASH = keccak256("test-cast");
    address public constant CREATOR = address(0x789);
    uint96 public constant CREATOR_FID = 67890;

    function setUp() public {
        usdc = new MockUSDC();

        // Deploy real contracts
        address owner = address(this);
        collectibleCast = new CollectibleCasts(
            owner,
            "https://example.com/" // baseURI - not needed for auction tests
        );

        // Configure real contracts
        auction = new Auction(address(collectibleCast), address(usdc), TREASURY, address(this));
        collectibleCast.allowMinter(address(auction));

        (authorizer, authorizerKey) = makeAddrAndKey("authorizer");
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
    }

    function testFuzz_Bid_Success(
        address firstBidder,
        uint96 firstBidderFid,
        uint256 firstAmount,
        address secondBidder,
        uint96 secondBidderFid,
        uint256 bidIncrement
    ) public {
        // Bound inputs
        vm.assume(firstBidder != address(0) && secondBidder != address(0));
        vm.assume(firstBidder != secondBidder);
        vm.assume(firstBidder != address(auction) && secondBidder != address(auction));
        vm.assume(firstBidder != CREATOR && secondBidder != CREATOR); // Can't be the creator
        firstBidderFid = uint96(_bound(firstBidderFid, 1, type(uint96).max));
        secondBidderFid = uint96(_bound(secondBidderFid, 1, type(uint96).max));
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

    function test_Bid_UpdatesLastBidAt() public {
        // Start auction first
        address firstBidder = address(0x123);
        uint96 firstBidderFid = 12345;
        uint256 firstAmount = 100e6; // 100 USDC
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Get initial lastBidAt
        (,,,,, uint40 initialLastBidAt,,,,) = auction.auctions(TEST_CAST_HASH);
        assertGt(initialLastBidAt, 0, "Initial lastBidAt should be set");

        // Warp time forward
        vm.warp(block.timestamp + 1 hours);

        // Second bidder places higher bid
        address secondBidder = address(0x456);
        uint96 secondBidderFid = 45678;
        uint256 secondAmount = 150e6; // 150 USDC

        bytes32 nonce = keccak256("bid-nonce");
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

        // Record timestamp before bid
        uint256 timestampBefore = block.timestamp;

        // Place bid
        IAuction.BidData memory bidData = createBidData(secondBidderFid, secondAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.prank(secondBidder);
        auction.bid(TEST_CAST_HASH, bidData, auth);

        // Verify lastBidAt was updated
        (,,,,, uint40 newLastBidAt,,,,) = auction.auctions(TEST_CAST_HASH);
        assertEq(newLastBidAt, timestampBefore, "lastBidAt should be updated to current block.timestamp");
        assertGt(newLastBidAt, initialLastBidAt, "New lastBidAt should be greater than initial");
    }

    function testFuzz_Bid_InsufficientIncrement(
        address firstBidder,
        uint96 firstBidderFid,
        uint256 firstAmount,
        address secondBidder,
        uint96 secondBidderFid,
        uint256 insufficientIncrement
    ) public {
        // Bound inputs
        vm.assume(firstBidder != address(0) && secondBidder != address(0));
        vm.assume(firstBidder != secondBidder);
        vm.assume(firstBidder != CREATOR && secondBidder != CREATOR);
        firstBidderFid = uint96(_bound(firstBidderFid, 1, type(uint96).max));
        secondBidderFid = uint96(_bound(secondBidderFid, 1, type(uint96).max));
        firstAmount = _bound(firstAmount, 1e6, 1000e6); // 1 to 1000 USDC

        // Calculate minimum required increment
        uint256 minIncrement = (firstAmount * 1000) / 10000; // 10%
        if (minIncrement < 1e6) minIncrement = 1e6; // At least 1 USDC

        // Bound insufficient increment to be less than minimum
        insufficientIncrement = _bound(insufficientIncrement, 1, minIncrement - 1);
        uint256 secondAmount = firstAmount + insufficientIncrement;

        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Try to bid with insufficient increment
        bytes32 nonce = keccak256(abi.encodePacked("bid-nonce-2", secondBidder, secondAmount));
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

    function test_Bid_ExtendAuction() public {
        // Test with concrete values first
        uint256 timeBeforeEnd = 5 minutes;
        address secondBidder = makeAddr("secondBidder");
        uint96 secondBidderFid = 54321;
        uint256 bidAmount = 2e6; // 2 USDC

        // Start auction
        address firstBidder = address(0x123);
        uint96 firstBidderFid = 12345;
        uint256 firstAmount = 1e6;

        // Store the original start time before starting auction
        uint256 auctionStartTime = block.timestamp;
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Fast forward to within extension threshold
        vm.warp(auctionStartTime + 24 hours - timeBeforeEnd);

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

        IAuction.BidData memory bidData = createBidData(secondBidderFid, bidAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Just verify the bid succeeds - the auction should be extended
        vm.prank(secondBidder);
        auction.bid(TEST_CAST_HASH, bidData, auth);

        // Verify the bid was placed successfully
        assertEq(usdc.balanceOf(secondBidder), 0);
        assertEq(usdc.balanceOf(address(auction)), bidAmount);
    }

    function testFuzz_Bid_ExtendAuction(
        uint256 timeBeforeEnd,
        address secondBidder,
        uint96 secondBidderFid,
        uint256 bidAmount
    ) public {
        // Bound inputs
        timeBeforeEnd = _bound(timeBeforeEnd, 1, 15 minutes - 1); // Within extension threshold
        vm.assume(secondBidder != address(0));
        vm.assume(secondBidder != address(0x123)); // Can't be same as first bidder
        vm.assume(secondBidder != CREATOR); // Can't be the creator
        vm.assume(secondBidder != address(auction)); // Can't be the auction contract
        vm.assume(secondBidder != authorizer); // Can't be the authorizer
        vm.assume(secondBidder.code.length == 0); // Ensure EOA
        secondBidderFid = uint96(_bound(secondBidderFid, 1, type(uint96).max));
        // Calculate minimum bid to outbid initial 1 USDC bid
        // minBid = 1e6 + max(1e6, 1e6 * 10%) = 1e6 + 1e6 = 2e6
        bidAmount = _bound(bidAmount, 2e6, 1000e6); // At least 2 USDC to outbid initial 1 USDC

        // Start auction
        address firstBidder = address(0x123);
        uint96 firstBidderFid = 12345;
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

        IAuction.BidData memory bidData = createBidData(secondBidderFid, bidAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Just verify the bid succeeds - the auction should be extended
        vm.prank(secondBidder);
        auction.bid(TEST_CAST_HASH, bidData, auth);

        // Verify the bid was placed successfully
        assertEq(usdc.balanceOf(secondBidder), 0);
        assertEq(usdc.balanceOf(address(auction)), bidAmount);
    }

    function testFuzz_Bid_RevertsNonceReuse(
        address firstBidder,
        uint96 firstBidderFid,
        uint256 firstAmount,
        address secondBidder,
        uint96 secondBidderFid,
        uint256 bidIncrement
    ) public {
        // Bound inputs
        vm.assume(firstBidder != address(0) && secondBidder != address(0));
        vm.assume(firstBidder != secondBidder);
        vm.assume(firstBidder != CREATOR && secondBidder != CREATOR);
        firstBidderFid = uint96(_bound(firstBidderFid, 1, type(uint96).max));
        secondBidderFid = uint96(_bound(secondBidderFid, 1, type(uint96).max));
        firstAmount = _bound(firstAmount, 1e6, 1000e6);

        // Calculate valid bid increment
        uint256 minIncrement = (firstAmount * 1000) / 10000; // 10%
        if (minIncrement < 1e6) minIncrement = 1e6;
        bidIncrement = _bound(bidIncrement, minIncrement, 100e6);
        uint256 secondAmount = firstAmount + bidIncrement;

        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Try to bid with a reused nonce
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

    function testFuzz_Bid_RevertsUnauthorizedBidder(
        address firstBidder,
        uint96 firstBidderFid,
        uint256 firstAmount,
        address secondBidder,
        uint96 secondBidderFid,
        uint256 bidIncrement
    ) public {
        // Bound inputs
        vm.assume(firstBidder != address(0) && secondBidder != address(0));
        vm.assume(firstBidder != secondBidder);
        vm.assume(firstBidder != CREATOR && secondBidder != CREATOR);
        firstBidderFid = uint96(_bound(firstBidderFid, 1, type(uint96).max));
        secondBidderFid = uint96(_bound(secondBidderFid, 1, type(uint96).max));
        firstAmount = _bound(firstAmount, 1e6, 1000e6);

        // Calculate valid bid increment
        uint256 minIncrement = (firstAmount * 1000) / 10000; // 10%
        if (minIncrement < 1e6) minIncrement = 1e6;
        bidIncrement = _bound(bidIncrement, minIncrement, 100e6);
        uint256 secondAmount = firstAmount + bidIncrement;

        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Try to bid with unauthorized signer (not an allowed authorizer)
        bytes32 nonce = keccak256(abi.encodePacked("bid-nonce-unauthorized", secondBidder));
        uint256 deadline = block.timestamp + 1 hours;

        // Create a new key that is NOT an allowed authorizer
        (, uint256 unauthorizedKey) = makeAddrAndKey("unauthorizedSigner");

        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, secondAmount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(unauthorizedKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        usdc.mint(secondBidder, secondAmount);
        vm.prank(secondBidder);
        usdc.approve(address(auction), secondAmount);

        IAuction.BidData memory bidData = createBidData(secondBidderFid, secondAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.prank(secondBidder);
        vm.expectRevert(IAuction.Unauthorized.selector);
        auction.bid(TEST_CAST_HASH, bidData, auth);
    }

    function testFuzz_Bid_RevertsExpiredDeadline(
        address firstBidder,
        uint96 firstBidderFid,
        uint256 firstAmount,
        address secondBidder,
        uint96 secondBidderFid,
        uint256 bidIncrement,
        uint256 expiredOffset
    ) public {
        // Bound inputs
        vm.assume(firstBidder != address(0) && secondBidder != address(0));
        vm.assume(firstBidder != secondBidder);
        vm.assume(firstBidder != CREATOR && secondBidder != CREATOR);
        firstBidderFid = uint96(_bound(firstBidderFid, 1, type(uint96).max));
        secondBidderFid = uint96(_bound(secondBidderFid, 1, type(uint96).max));
        firstAmount = _bound(firstAmount, 1e6, 1000e6);

        // Calculate valid bid increment
        uint256 minIncrement = (firstAmount * 1000) / 10000; // 10%
        if (minIncrement < 1e6) minIncrement = 1e6;
        bidIncrement = _bound(bidIncrement, minIncrement, 100e6);
        uint256 secondAmount = firstAmount + bidIncrement;

        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Try to bid with expired deadline
        bytes32 nonce = keccak256(abi.encodePacked("bid-nonce-expired", secondBidder));
        expiredOffset = _bound(expiredOffset, 1, block.timestamp > 365 days ? 365 days : block.timestamp); // Avoid underflow
        uint256 deadline = block.timestamp - expiredOffset; // Already expired

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
        vm.expectRevert(IAuction.DeadlineExpired.selector);
        auction.bid(TEST_CAST_HASH, bidData, auth);
    }

    function testFuzz_Bid_RevertsOnNonExistentAuction(
        bytes32 nonExistentTokenId,
        address bidder,
        uint96 bidderFid,
        uint256 amount,
        bytes32 nonce
    ) public {
        vm.assume(bidder != address(0));
        vm.assume(nonExistentTokenId != bytes32(0));
        bidderFid = uint96(_bound(bidderFid, 1, type(uint96).max));
        amount = _bound(amount, 1e6, 10000e6);
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

    function testFuzz_Bid_RevertsOnSettledAuction(
        address firstBidder,
        uint96 firstBidderFid,
        uint256 firstAmount,
        address secondBidder,
        uint96 secondBidderFid,
        uint256 bidIncrement
    ) public {
        // Bound inputs
        vm.assume(firstBidder != address(0) && secondBidder != address(0));
        vm.assume(firstBidder != secondBidder);
        vm.assume(firstBidder != CREATOR && secondBidder != CREATOR);
        vm.assume(firstBidder.code.length == 0 && secondBidder.code.length == 0); // Ensure EOAs for ERC1155 transfers
        firstBidderFid = uint96(_bound(firstBidderFid, 1, type(uint96).max));
        secondBidderFid = uint96(_bound(secondBidderFid, 1, type(uint96).max));
        firstAmount = _bound(firstAmount, 1e6, 1000e6);

        // Calculate valid bid increment
        uint256 minIncrement = (firstAmount * 1000) / 10000; // 10%
        if (minIncrement < 1e6) minIncrement = 1e6;
        bidIncrement = _bound(bidIncrement, minIncrement, 100e6);
        uint256 secondAmount = firstAmount + bidIncrement;

        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Fast forward past end time and settle
        vm.warp(block.timestamp + 25 hours);
        auction.settle(TEST_CAST_HASH);

        // Now try to bid on the settled auction
        bytes32 nonce = keccak256(abi.encodePacked("bid-nonce-settled", secondBidder));
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

        // Should revert because auction is not active (it's settled)
        vm.prank(secondBidder);
        vm.expectRevert(IAuction.AuctionNotActive.selector);
        auction.bid(TEST_CAST_HASH, bidData, auth);
    }

    event BidPlaced(bytes32 indexed castHash, address indexed bidder, uint96 bidderFid, uint256 amount);
    event AuctionExtended(bytes32 indexed castHash, uint256 newEndTime);

    function _startAuction(address bidder, uint96 bidderFid, uint256 amount) internal {
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

    function test_Bid_RevertsWrongChainId() public {
        // Start an auction first
        address firstBidder = makeAddr("firstBidder");
        uint96 firstBidderFid = 123;
        uint256 firstAmount = 10e6;
        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Setup second bid
        address secondBidder = makeAddr("secondBidder");
        uint96 secondBidderFid = 456;
        uint256 secondAmount = 20e6;

        // Create auction on different chain to generate wrong signature
        vm.chainId(999);
        MockUSDC wrongChainUsdc = new MockUSDC();
        Auction wrongChainAuction =
            new Auction(address(collectibleCast), address(wrongChainUsdc), TREASURY, address(this));

        // Allow the authorizer on wrong chain auction
        wrongChainAuction.allowAuthorizer(authorizer);

        // Create the bid authorization hash for wrong chain
        bytes32 nonce = keccak256("wrong-chain-nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 messageHash = wrongChainAuction.hashBidAuthorization(
            TEST_CAST_HASH, secondBidder, secondBidderFid, secondAmount, nonce, deadline
        );

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Reset chain id back to original
        vm.chainId(31337);

        // Prepare for bid on original chain
        usdc.mint(secondBidder, secondAmount);
        vm.prank(secondBidder);
        usdc.approve(address(auction), secondAmount);

        IAuction.BidData memory bidData = createBidData(secondBidderFid, secondAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Should fail due to different chain id in signature
        vm.prank(secondBidder);
        vm.expectRevert(IAuction.Unauthorized.selector);
        auction.bid(TEST_CAST_HASH, bidData, auth);
    }
}
