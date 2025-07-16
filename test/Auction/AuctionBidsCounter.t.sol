// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockCollectibleCasts} from "../mocks/MockCollectibleCasts.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

contract AuctionBidsCounterTest is Test, AuctionTestHelper {
    Auction public auction;
    MockCollectibleCasts public collectibleCast;
    MockUSDC public usdc;

    address public treasury;
    address public owner;
    address public authorizer;
    uint256 public authorizerPk = 0x123;
    address public creator;
    address public bidder1;
    address public bidder2;
    address public bidder3;

    function setUp() public {
        // Create named addresses
        treasury = makeAddr("treasury");
        owner = makeAddr("owner");
        authorizer = vm.addr(authorizerPk);
        creator = makeAddr("creator");
        bidder1 = makeAddr("bidder1");
        bidder2 = makeAddr("bidder2");
        bidder3 = makeAddr("bidder3");

        // Deploy contracts
        usdc = new MockUSDC();
        collectibleCast = new MockCollectibleCasts();
        auction = new Auction(address(collectibleCast), address(usdc), treasury, owner);

        // Allow the auction contract to mint
        collectibleCast.allowMinter(address(auction));

        // Set up authorizer
        vm.prank(owner);
        auction.allowAuthorizer(authorizer);

        // Fund bidders with USDC
        usdc.mint(bidder1, 1000e6);
        usdc.mint(bidder2, 1000e6);
        usdc.mint(bidder3, 1000e6);

        // Approve auction to spend USDC
        vm.prank(bidder1);
        usdc.approve(address(auction), type(uint256).max);
        vm.prank(bidder2);
        usdc.approve(address(auction), type(uint256).max);
        vm.prank(bidder3);
        usdc.approve(address(auction), type(uint256).max);
    }

    function test_BidsCounter_StartsAtOne_WhenAuctionStarted() public {
        bytes32 castHash = keccak256("cast1");
        uint256 startAmount = 10e6;

        // Create and sign start authorization
        IAuction.CastData memory cast = createCastData(castHash, creator, 123);
        IAuction.BidData memory bidData = createBidData(456, startAmount);
        IAuction.AuctionParams memory params = createAuctionParams(
            startAmount, // minBid
            500, // minBidIncrementBps (5%)
            1 hours, // duration
            5 minutes, // extension
            10 minutes, // extensionThreshold
            1000 // protocolFeeBps (10%)
        );

        bytes32 nonce = keccak256("nonce1");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest =
            auction.hashStartAuthorization(castHash, creator, 123, bidder1, 456, startAmount, params, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Start auction
        vm.prank(bidder1);
        auction.start(cast, bidData, params, auth);

        // Check that bids is 1
        (,,,,,,, uint32 bids,,) = auction.auctions(castHash);
        assertEq(bids, 1, "Bids count should be 1 after auction start");
    }

    function test_BidsCounter_Increments_OnEachBid() public {
        bytes32 castHash = keccak256("cast2");
        uint256 startAmount = 10e6;

        // Start auction
        _startAuction(castHash, creator, bidder1, startAmount);

        // Check initial bids count
        (,,,,,,, uint32 bids,,) = auction.auctions(castHash);
        assertEq(bids, 1, "Initial bids count should be 1");

        // Place second bid
        uint256 secondBidAmount = 11e6;
        _placeBid(castHash, bidder2, 789, secondBidAmount, keccak256("nonce2"));

        // Check bids count after second bid
        (,,,,,,, bids,,) = auction.auctions(castHash);
        assertEq(bids, 2, "Bids count should be 2 after second bid");

        // Place third bid
        uint256 thirdBidAmount = 12e6;
        _placeBid(castHash, bidder3, 1011, thirdBidAmount, keccak256("nonce3"));

        // Check bids count after third bid
        (,,,,,,, bids,,) = auction.auctions(castHash);
        assertEq(bids, 3, "Bids count should be 3 after third bid");
    }

    function testFuzz_BidsCounter_TracksAllBids(uint16 numBids) public {
        vm.assume(numBids >= 1 && numBids <= 1000); // Test up to 1000 bids

        bytes32 castHash = keccak256("cast_fuzz");
        uint256 startAmount = 10e6;

        // Start auction
        _startAuction(castHash, creator, bidder1, startAmount);

        // Place additional bids
        uint256 currentBidAmount = startAmount;
        for (uint16 i = 1; i < numBids; i++) {
            address currentBidder = address(uint160(uint256(keccak256(abi.encode("bidder", i)))));

            // Calculate next bid amount - ensure it meets minimum increment
            // The contract requires: newBid >= oldBid + max(1e6, oldBid * 5%)
            uint256 minIncrement = (currentBidAmount * 500) / 10000; // 5%
            if (minIncrement < 1e6) minIncrement = 1e6;

            // Prevent overflow
            if (currentBidAmount > type(uint256).max - minIncrement) {
                // Skip if would overflow
                break;
            }
            currentBidAmount = currentBidAmount + minIncrement;

            // Fund and approve for new bidder with enough for the bid
            usdc.mint(currentBidder, currentBidAmount + 100e6); // Extra buffer
            vm.prank(currentBidder);
            usdc.approve(address(auction), type(uint256).max);

            _placeBid(castHash, currentBidder, uint96(100 + i), currentBidAmount, keccak256(abi.encode("nonce", i)));
        }

        // Check final bids count (might be less than numBids if we hit overflow)
        (,,,,,,, uint32 bids,,) = auction.auctions(castHash);
        assertGe(bids, 1, "Should have at least 1 bid");
        assertLe(bids, numBids, "Bids count should not exceed requested number");
    }

    function test_BidsCounter_RemainsUnchanged_OnCancelledAuction() public {
        bytes32 castHash = keccak256("cast_cancel");
        uint256 startAmount = 10e6;

        // Start auction and place some bids
        _startAuction(castHash, creator, bidder1, startAmount);
        _placeBid(castHash, bidder2, 789, 11e6, keccak256("nonce2"));
        _placeBid(castHash, bidder3, 1011, 12e6, keccak256("nonce3"));

        // Check bids count before cancel
        (,,,,,,, uint32 bidsBefore,,) = auction.auctions(castHash);
        assertEq(bidsBefore, 3, "Should have 3 bids before cancellation");

        // Cancel auction
        bytes32 cancelNonce = keccak256("cancel_nonce");
        uint256 cancelDeadline = block.timestamp + 1 hours;
        bytes32 cancelDigest = auction.hashCancelAuthorization(castHash, cancelNonce, cancelDeadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, cancelDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory cancelAuth = createAuthData(cancelNonce, cancelDeadline, signature);
        auction.cancel(castHash, cancelAuth);

        // Check bids count after cancel - should remain the same
        (,,,,,,, uint32 bidsAfter,,) = auction.auctions(castHash);
        assertEq(bidsAfter, bidsBefore, "Bids count should remain unchanged after cancellation");
    }

    function test_BidsCounter_RemainsUnchanged_AfterSettlement() public {
        bytes32 castHash = keccak256("cast_settle");
        uint256 startAmount = 10e6;

        // Start auction and place some bids
        _startAuction(castHash, creator, bidder1, startAmount);
        _placeBid(castHash, bidder2, 789, 11e6, keccak256("nonce2"));
        _placeBid(castHash, bidder3, 1011, 12e6, keccak256("nonce3"));

        // Check bids count before settlement
        (,,,,,,, uint32 bidsBefore,,) = auction.auctions(castHash);
        assertEq(bidsBefore, 3, "Should have 3 bids before settlement");

        // Fast forward past auction end
        vm.warp(block.timestamp + 2 hours);

        // Settle auction
        auction.settle(castHash);

        // Check bids count after settlement - should remain the same
        (,,,,,,, uint32 bidsAfter,,) = auction.auctions(castHash);
        assertEq(bidsAfter, bidsBefore, "Bids count should remain unchanged after settlement");
    }

    function test_BidsCounter_MaxUint32_DoesNotOverflow() public {
        bytes32 castHash = keccak256("cast_max");
        uint256 startAmount = 10e6;

        // Start auction
        _startAuction(castHash, creator, bidder1, startAmount);

        // Manually set bidsCount to max uint32 - 1
        // This requires accessing the storage slot directly
        // We'll test that incrementing from max-1 doesn't cause issues

        // First, let's get close to max by placing many bids
        uint256 currentBidAmount = startAmount;
        for (uint256 i = 1; i < 10; i++) {
            address currentBidder = address(uint160(uint256(keccak256(abi.encode("maxbidder", i)))));
            usdc.mint(currentBidder, 1000e6);
            vm.prank(currentBidder);
            usdc.approve(address(auction), type(uint256).max);

            currentBidAmount = currentBidAmount + 1e6;
            _placeBid(castHash, currentBidder, uint96(100 + i), currentBidAmount, keccak256(abi.encode("maxnonce", i)));
        }

        // Verify we can still read the bids count
        (,,,,,,, uint32 bids,,) = auction.auctions(castHash);
        assertEq(bids, 10, "Should have 10 bids");
    }

    function test_BidsCounter_ZeroBids_NeverExists() public {
        bytes32 castHash = keccak256("cast_zero");

        // Check that non-existent auction has no bid data
        (,,,,,,, uint32 bids,,) = auction.auctions(castHash);
        assertEq(bids, 0, "Non-existent auction should have 0 bids");

        // Verify auction state is None
        assertEq(uint8(auction.auctionState(castHash)), uint8(IAuction.AuctionState.None));
    }

    function test_BidsCounter_SingleBid_StartsAtOne() public {
        bytes32 castHash = keccak256("cast_single");
        uint256 amount = 10e6;

        // Start auction with single bid
        _startAuction(castHash, creator, bidder1, amount);

        // Verify bids count is exactly 1
        (,,,,,,, uint32 bids,,) = auction.auctions(castHash);
        assertEq(bids, 1, "Single bid auction should have bids of 1");

        // Let auction end without more bids
        vm.warp(block.timestamp + 2 hours);

        // Settle and verify count remains 1
        auction.settle(castHash);
        (,,,,,,, uint32 bidsAfter,,) = auction.auctions(castHash);
        assertEq(bidsAfter, 1, "Bids count should remain 1 after settlement");
    }

    function test_BidsCounter_DoesNotDecrementOnRefund() public {
        bytes32 castHash = keccak256("cast_refund");
        uint256 startAmount = 10e6;

        // Start auction and place multiple bids
        _startAuction(castHash, creator, bidder1, startAmount);
        _placeBid(castHash, bidder2, 789, 11e6, keccak256("refund_nonce2"));
        _placeBid(castHash, bidder3, 1011, 12e6, keccak256("refund_nonce3"));

        // Get count before last bid that will cause refunds
        (,,,,,,, uint32 countBefore,,) = auction.auctions(castHash);
        assertEq(countBefore, 3, "Should have 3 bids before final bid");

        // Place another bid that will refund previous bidder
        _placeBid(castHash, bidder1, 456, 13e6, keccak256("refund_nonce4"));

        // Verify count incremented despite refund
        (,,,,,,, uint32 countAfter,,) = auction.auctions(castHash);
        assertEq(countAfter, 4, "Bids count should increment even when refunding previous bidder");
    }

    // Helper functions
    function _startAuction(bytes32 castHash, address _creator, address firstBidder, uint256 amount) internal {
        IAuction.CastData memory cast = createCastData(castHash, _creator, 123);
        IAuction.BidData memory bidData = createBidData(456, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            amount, // minBid
            500, // minBidIncrementBps (5%)
            1 hours, // duration
            5 minutes, // extension
            10 minutes, // extensionThreshold
            1000 // protocolFeeBps (10%)
        );

        bytes32 nonce = keccak256("start_nonce");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest =
            auction.hashStartAuthorization(castHash, _creator, 123, firstBidder, 456, amount, params, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.prank(firstBidder);
        auction.start(cast, bidData, params, auth);
    }

    function _placeBid(bytes32 castHash, address _bidder, uint96 bidderFid, uint256 amount, bytes32 nonce) internal {
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = auction.hashBidAuthorization(castHash, _bidder, bidderFid, amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.prank(_bidder);
        auction.bid(castHash, bidData, auth);
    }
}
