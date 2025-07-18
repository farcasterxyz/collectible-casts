// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "../../src/interfaces/IAuction.sol";
import {AuctionTestBase} from "./AuctionTestBase.sol";

contract AuctionSettleTest is AuctionTestBase {
    event AuctionSettled(bytes32 indexed castHash, address indexed winner, uint96 winnerFid, uint256 amount);
    event BidRefunded(address indexed to, uint256 amount);

    function testFuzz_Settle_Success(address bidder, uint96 bidderFid, uint256 amount) public {
        // Bound inputs
        vm.assume(bidder != address(0));
        bidderFid = uint96(_bound(bidderFid, 1, type(uint96).max));
        amount = _bound(amount, 1e6, 1000000e6); // 1 to 1,000,000 USDC

        // Start auction
        _startAuction(bidder, bidderFid, amount);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Record balances before settlement
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);
        uint256 creatorBalanceBefore = usdc.balanceOf(DEFAULT_CREATOR);

        // Settle auction
        auction.settle(TEST_CAST_HASH);

        // Verify payment distribution (90% to creator, 10% to treasury based on default protocol fee)
        uint256 treasuryAmount = (amount * 1000) / 10000; // 10% (1000 basis points)
        uint256 creatorAmount = amount - treasuryAmount;

        assertEq(usdc.balanceOf(treasury), treasuryBalanceBefore + treasuryAmount);
        assertEq(usdc.balanceOf(DEFAULT_CREATOR), creatorBalanceBefore + creatorAmount);

        // Verify NFT was minted to the bidder
        _assertNFTOwnership(TEST_CAST_HASH, bidder);
        _assertTokenData(TEST_CAST_HASH, DEFAULT_CREATOR_FID, DEFAULT_CREATOR);

        // Verify auction is marked as settled
        _assertAuctionState(TEST_CAST_HASH, IAuction.AuctionState.Settled);
    }

    function test_Settle_RevertsIfCancelled() public {
        // Start an auction
        address testBidder = makeAddr("cancelledBidder");
        uint96 bidderFid = 12345;
        uint256 amount = 100e6;
        _startAuctionWithParams(
            TEST_CAST_HASH,
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            testBidder,
            bidderFid,
            amount,
            _getDefaultAuctionParams()
        );

        // Cancel it
        _cancelAuction(TEST_CAST_HASH);

        // Try to settle the cancelled auction
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(TEST_CAST_HASH);
    }

    function test_Settle_RevertsIfNotEnded() public {
        // Start auction
        address testBidder = makeAddr("activeBidder");
        uint96 bidderFid = 12345;
        uint256 amount = 100e6;
        _startAuction(testBidder, bidderFid, amount);

        // Try to settle while still active
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(TEST_CAST_HASH);
    }

    function test_Settle_RevertsIfAlreadySettled() public {
        // Start auction
        address testBidder = makeAddr("settledBidder");
        uint96 bidderFid = 12345;
        uint256 amount = 100e6;
        _startAuction(testBidder, bidderFid, amount);

        // Fast forward and settle
        vm.warp(block.timestamp + 25 hours);
        auction.settle(TEST_CAST_HASH);

        // Try to settle again
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(TEST_CAST_HASH);
    }

    function test_Settle_RevertsIfNonExistent() public {
        bytes32 nonExistentTokenId = keccak256("non-existent");

        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(nonExistentTokenId);
    }

    function test_BatchSettle_Success() public {
        // Create multiple auctions
        bytes32[] memory castHashes = new bytes32[](3);
        castHashes[0] = keccak256("cast-1");
        castHashes[1] = keccak256("cast-2");
        castHashes[2] = keccak256("cast-3");

        address[] memory bidders = new address[](3);
        bidders[0] = makeAddr("batchBidder1");
        bidders[1] = makeAddr("batchBidder2");
        bidders[2] = makeAddr("batchBidder3");

        uint96[] memory bidderFids = new uint96[](3);
        bidderFids[0] = 11111;
        bidderFids[1] = 22222;
        bidderFids[2] = 33333;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1e6; // 1 USDC
        amounts[1] = 10e6; // 10 USDC
        amounts[2] = 100e6; // 100 USDC

        // Start all auctions
        for (uint256 i = 0; i < 3; i++) {
            _startAuctionWithParams(
                castHashes[i],
                DEFAULT_CREATOR,
                DEFAULT_CREATOR_FID,
                bidders[i],
                bidderFids[i],
                amounts[i],
                _getDefaultAuctionParams()
            );
        }

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Record balances before batch settlement
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);
        uint256 creatorBalanceBefore = usdc.balanceOf(DEFAULT_CREATOR);

        // Batch settle all auctions
        auction.batchSettle(castHashes);

        // Verify all payments were distributed correctly
        uint256 totalTreasuryAmount = 0;
        uint256 totalCreatorAmount = 0;
        for (uint256 i = 0; i < 3; i++) {
            uint256 treasuryAmount = (amounts[i] * 1000) / 10000; // 10%
            totalTreasuryAmount += treasuryAmount;
            totalCreatorAmount += amounts[i] - treasuryAmount;
        }

        assertEq(usdc.balanceOf(treasury), treasuryBalanceBefore + totalTreasuryAmount);
        assertEq(usdc.balanceOf(DEFAULT_CREATOR), creatorBalanceBefore + totalCreatorAmount);

        // Verify all NFTs were minted to correct bidders
        for (uint256 i = 0; i < 3; i++) {
            _assertNFTOwnership(castHashes[i], bidders[i]);
            _assertAuctionState(castHashes[i], IAuction.AuctionState.Settled);
        }
    }

    function test_BatchSettle_EmptyArray() public {
        bytes32[] memory emptyCastHashes = new bytes32[](0);

        // Should not revert with empty array
        auction.batchSettle(emptyCastHashes);
    }

    function test_BatchSettle_SingleAuction() public {
        // Start one auction
        address testBidder = makeAddr("singleBidder");
        uint96 bidderFid = 12345;
        uint256 amount = 1e6;
        _startAuction(testBidder, bidderFid, amount);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Create array with single cast hash
        bytes32[] memory castHashes = new bytes32[](1);
        castHashes[0] = TEST_CAST_HASH;

        // Batch settle single auction
        auction.batchSettle(castHashes);

        // Verify settlement
        _assertAuctionState(TEST_CAST_HASH, IAuction.AuctionState.Settled);
        _assertNFTOwnership(TEST_CAST_HASH, testBidder);
    }

    function test_BatchSettle_RevertsOnNonExistentAuction() public {
        bytes32[] memory castHashes = new bytes32[](2);
        castHashes[0] = keccak256("valid-cast");
        castHashes[1] = keccak256("non-existent");

        // Start only the first auction
        address testBidder = makeAddr("nonExistentBidder");
        uint96 bidderFid = 12345;
        uint256 amount = 1e6;
        _startAuctionWithParams(
            castHashes[0],
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            testBidder,
            bidderFid,
            amount,
            _getDefaultAuctionParams()
        );

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Should revert when trying to settle non-existent auction
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.batchSettle(castHashes);
    }

    function test_BatchSettle_RevertsOnActiveAuction() public {
        bytes32[] memory castHashes = new bytes32[](2);
        castHashes[0] = keccak256("ended-cast");
        castHashes[1] = keccak256("active-cast");

        // Start both auctions with different end times
        address bidder1 = makeAddr("endedBidder");
        address bidder2 = makeAddr("activeBidder2");
        uint96 bidderFid = 12345;
        uint256 amount = 1e6;

        _startAuctionWithParams(
            castHashes[0], DEFAULT_CREATOR, DEFAULT_CREATOR_FID, bidder1, bidderFid, amount, _getDefaultAuctionParams()
        );

        // Start second auction 1 hour later (so it ends later)
        vm.warp(block.timestamp + 1 hours);
        _startAuctionWithParams(
            castHashes[1],
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            bidder2,
            bidderFid + 1,
            amount,
            _getDefaultAuctionParams()
        );

        // Fast forward to end first auction but not second
        vm.warp(block.timestamp + 23 hours); // First auction ended, second still active

        // Should revert when trying to settle active auction
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.batchSettle(castHashes);
    }

    function test_BatchSettle_RevertsOnAlreadySettledAuction() public {
        bytes32[] memory castHashes = new bytes32[](2);
        castHashes[0] = keccak256("unsettled-cast");
        castHashes[1] = keccak256("settled-cast");

        // Start both auctions
        address bidder1 = makeAddr("unsettledBidder");
        address bidder2 = makeAddr("alreadySettledBidder");
        uint96 bidderFid = 12345;
        uint256 amount = 1e6;

        _startAuctionWithParams(
            castHashes[0], DEFAULT_CREATOR, DEFAULT_CREATOR_FID, bidder1, bidderFid, amount, _getDefaultAuctionParams()
        );
        _startAuctionWithParams(
            castHashes[1],
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            bidder2,
            bidderFid + 1,
            amount,
            _getDefaultAuctionParams()
        );

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Settle one auction individually
        auction.settle(castHashes[1]);

        // Should revert when trying to settle already settled auction
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.batchSettle(castHashes);
    }

    function testFuzz_BatchSettle_MultipleAuctions(uint8 numAuctions) public {
        // Bound to reasonable number for gas limits
        numAuctions = uint8(_bound(numAuctions, 1, 10));

        bytes32[] memory castHashes = new bytes32[](numAuctions);
        address[] memory bidders = new address[](numAuctions);
        uint256[] memory amounts = new uint256[](numAuctions);

        // Create auctions
        for (uint256 i = 0; i < numAuctions; i++) {
            castHashes[i] = keccak256(abi.encodePacked("cast", i));
            bidders[i] = makeAddr(string(abi.encodePacked("fuzzBidder", i)));
            amounts[i] = (i + 1) * 1e6; // 1, 2, 3, ... USDC

            _startAuctionWithParams(
                castHashes[i],
                DEFAULT_CREATOR,
                DEFAULT_CREATOR_FID,
                bidders[i],
                uint96(10000 + i),
                amounts[i],
                _getDefaultAuctionParams()
            );
        }

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Record balances before
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);
        uint256 creatorBalanceBefore = usdc.balanceOf(DEFAULT_CREATOR);

        // Batch settle
        auction.batchSettle(castHashes);

        // Verify all settled
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < numAuctions; i++) {
            _assertAuctionState(castHashes[i], IAuction.AuctionState.Settled);
            _assertNFTOwnership(castHashes[i], bidders[i]);
            totalAmount += amounts[i];
        }

        // Verify payments
        uint256 expectedTreasuryAmount = (totalAmount * 1000) / 10000; // 10%
        uint256 expectedCreatorAmount = totalAmount - expectedTreasuryAmount;

        assertEq(usdc.balanceOf(treasury), treasuryBalanceBefore + expectedTreasuryAmount);
        assertEq(usdc.balanceOf(DEFAULT_CREATOR), creatorBalanceBefore + expectedCreatorAmount);
    }
}
