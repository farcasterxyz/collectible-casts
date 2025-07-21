// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "../../src/interfaces/IAuction.sol";
import {AuctionTestBase} from "./AuctionTestBase.sol";

contract AuctionGetAuctionTest is AuctionTestBase {
    function test_GetAuction_NonExistentAuction() public view {
        bytes32 castHash = keccak256("nonexistent");
        IAuction.AuctionData memory data = auction.getAuction(castHash);

        // Should return empty struct
        assertEq(data.creator, address(0));
        assertEq(data.creatorFid, 0);
        assertEq(data.highestBidder, address(0));
        assertEq(data.highestBidderFid, 0);
        assertEq(data.highestBid, 0);
        assertEq(data.lastBidAt, 0);
        assertEq(data.endTime, 0);
        assertEq(data.bids, 0);
        assertEq(uint8(data.state), uint8(IAuction.AuctionState.None));
    }

    function test_GetAuction_ActiveAuction() public {
        // Create an active auction
        bytes32 castHash = keccak256("test");
        uint256 amount = 100e6;
        _startAuctionWithParams(
            castHash,
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            bidder,
            DEFAULT_BIDDER_FID,
            amount,
            _getDefaultAuctionParams()
        );

        IAuction.AuctionData memory data = auction.getAuction(castHash);

        // Verify data matches
        assertEq(data.creator, DEFAULT_CREATOR);
        assertEq(data.creatorFid, DEFAULT_CREATOR_FID);
        assertEq(data.highestBidder, bidder);
        assertEq(data.highestBidderFid, DEFAULT_BIDDER_FID);
        assertEq(data.highestBid, amount);
        assertGt(data.lastBidAt, 0);
        assertGt(data.endTime, block.timestamp);
        assertEq(data.bids, 1);
        assertEq(uint8(data.state), uint8(IAuction.AuctionState.Active));
    }

    function test_GetAuction_EndedAuction() public {
        // Create and let auction end
        bytes32 castHash = keccak256("test");
        uint256 amount = 100e6;
        uint256 endTime = _startAuctionWithParams(
            castHash,
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            bidder,
            DEFAULT_BIDDER_FID,
            amount,
            _getDefaultAuctionParams()
        );

        // Warp past end time
        vm.warp(endTime + 1);

        IAuction.AuctionData memory data = auction.getAuction(castHash);

        // State should be Ended (calculated), not Active (stored)
        assertEq(uint8(data.state), uint8(IAuction.AuctionState.Ended));

        // Other data should remain the same
        assertEq(data.creator, DEFAULT_CREATOR);
        assertEq(data.highestBidder, bidder);
        assertEq(data.highestBid, amount);
    }

    function test_GetAuction_SettledAuction() public {
        // Create, end, and settle auction
        bytes32 castHash = keccak256("test");
        uint256 amount = 100e6;
        uint256 endTime = _startAuctionWithParams(
            castHash,
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            bidder,
            DEFAULT_BIDDER_FID,
            amount,
            _getDefaultAuctionParams()
        );

        vm.warp(endTime + 1);
        auction.settle(castHash);

        IAuction.AuctionData memory data = auction.getAuction(castHash);

        // State should be Settled
        assertEq(uint8(data.state), uint8(IAuction.AuctionState.Settled));
        assertEq(data.creator, DEFAULT_CREATOR);
        assertEq(data.highestBidder, bidder);
        assertEq(data.highestBid, amount);
    }

    function test_GetAuction_CancelledAuction() public {
        // Create and cancel auction
        bytes32 castHash = keccak256("test");
        uint256 amount = 100e6;
        _startAuctionWithParams(
            castHash,
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            bidder,
            DEFAULT_BIDDER_FID,
            amount,
            _getDefaultAuctionParams()
        );

        // Cancel the auction
        bytes32 nonce = keccak256("cancel-nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        auction.cancel(castHash, auth);

        IAuction.AuctionData memory data = auction.getAuction(castHash);

        // State should be Cancelled
        assertEq(uint8(data.state), uint8(IAuction.AuctionState.Cancelled));
        assertEq(data.creator, DEFAULT_CREATOR);
        assertEq(data.highestBidder, bidder);
        assertEq(data.highestBid, amount);
    }

    function test_GetAuction_RecoveredAuction() public {
        // Create and recover auction
        bytes32 castHash = keccak256("test");
        uint256 amount = 100e6;
        _startAuctionWithParams(
            castHash,
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            bidder,
            DEFAULT_BIDDER_FID,
            amount,
            _getDefaultAuctionParams()
        );

        // Recover the auction
        vm.prank(owner);
        auction.recover(castHash, treasury);

        IAuction.AuctionData memory data = auction.getAuction(castHash);

        // State should be Recovered
        assertEq(uint8(data.state), uint8(IAuction.AuctionState.Recovered));
        assertEq(data.creator, DEFAULT_CREATOR);
        assertEq(data.highestBidder, bidder);
        assertEq(data.highestBid, amount);
    }

    function test_GetAuction_PreservesAllFields() public {
        // Create auction with specific params
        bytes32 castHash = keccak256("detailed-test");
        address testCreator = makeAddr("testCreator");
        uint96 testCreatorFid = 99999;
        address testBidder = makeAddr("testBidder");
        uint96 testBidderFid = 88888;
        uint256 testAmount = 567e6;

        IAuction.AuctionParams memory testParams = IAuction.AuctionParams({
            minBid: uint64(10e6),
            minBidIncrementBps: uint16(500), // 5%
            duration: uint32(12 hours),
            extension: uint32(30 minutes),
            extensionThreshold: uint32(30 minutes),
            protocolFeeBps: uint16(250) // 2.5%
        });

        _fundAndApprove(testBidder, testAmount);

        uint256 startTime = block.timestamp;
        _startAuctionWithParams(
            castHash, testCreator, testCreatorFid, testBidder, testBidderFid, testAmount, testParams
        );

        IAuction.AuctionData memory data = auction.getAuction(castHash);

        // Verify all fields are preserved
        assertEq(data.creator, testCreator);
        assertEq(data.creatorFid, testCreatorFid);
        assertEq(data.highestBidder, testBidder);
        assertEq(data.highestBidderFid, testBidderFid);
        assertEq(data.highestBid, testAmount);
        assertEq(data.lastBidAt, startTime);
        assertEq(data.endTime, startTime + testParams.duration);
        assertEq(data.bids, 1);
        assertEq(uint8(data.state), uint8(IAuction.AuctionState.Active));

        // Verify params are preserved
        assertEq(data.params.minBid, testParams.minBid);
        assertEq(data.params.minBidIncrementBps, testParams.minBidIncrementBps);
        assertEq(data.params.duration, testParams.duration);
        assertEq(data.params.extension, testParams.extension);
        assertEq(data.params.extensionThreshold, testParams.extensionThreshold);
        assertEq(data.params.protocolFeeBps, testParams.protocolFeeBps);
    }

    function testFuzz_GetAuction_VariousStates(bytes32 castHash, uint96 creatorFid, uint256 amount) public {
        // Bound inputs
        vm.assume(castHash != bytes32(0)); // castHash cannot be zero
        creatorFid = uint96(_bound(creatorFid, 1, type(uint96).max));
        amount = _bound(amount, 1e6, 1000e6);

        // Test non-existent
        IAuction.AuctionData memory data = auction.getAuction(castHash);
        assertEq(uint8(data.state), uint8(IAuction.AuctionState.None));

        // Create auction
        _startAuctionWithParams(
            castHash, DEFAULT_CREATOR, creatorFid, bidder, DEFAULT_BIDDER_FID, amount, _getDefaultAuctionParams()
        );

        // Test active
        data = auction.getAuction(castHash);
        assertEq(uint8(data.state), uint8(IAuction.AuctionState.Active));
        assertEq(data.creatorFid, creatorFid);
        assertEq(data.highestBid, amount);

        // Test ended
        vm.warp(block.timestamp + 25 hours);
        data = auction.getAuction(castHash);
        assertEq(uint8(data.state), uint8(IAuction.AuctionState.Ended));

        // Settle and test
        auction.settle(castHash);
        data = auction.getAuction(castHash);
        assertEq(uint8(data.state), uint8(IAuction.AuctionState.Settled));
    }
}
