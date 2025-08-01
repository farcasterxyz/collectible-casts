// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {AuctionTestBase} from "./AuctionTestBase.sol";

contract AuctionStateTest is AuctionTestBase {
    function test_StateTransitions() public {
        bytes32 castHash = TEST_CAST_HASH;
        // Initially, auction should be in None state
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.None));

        // Start auction
        _startAuction(castHash);

        // Should now be Active
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Active));

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Should now be Ended (automatically detected)
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Ended));

        // Settle the auction
        auction.settle(castHash);

        // State should now be Settled
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Settled));
    }

    function testFuzz_CannotStartAuctionTwice(
        bytes32 castHash,
        address creator,
        uint96 creatorFid,
        address bidder,
        uint96 bidderFid,
        uint256 amount,
        bytes32 nonce
    ) public {
        vm.assume(castHash != bytes32(0));
        vm.assume(creator != address(0));
        vm.assume(bidder != address(0));
        vm.assume(creator != bidder);
        creatorFid = uint96(_bound(creatorFid, 1, type(uint96).max));
        bidderFid = uint96(_bound(bidderFid, 1, type(uint96).max));
        amount = _bound(amount, 1e6, 10000e6);
        uint256 deadline = block.timestamp + 1 hours;

        _startAuction(castHash);

        // Try to start again

        IAuction.CastData memory castData = createCastData(castHash, creator, creatorFid);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = _getDefaultAuctionParams();

        bytes32 messageHash = auction.hashStartAuthorization(
            castHash, creator, creatorFid, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        usdc.mint(bidder, amount);
        vm.prank(bidder);
        usdc.approve(address(auction), amount);

        vm.prank(bidder);
        vm.expectRevert(IAuction.AuctionAlreadyExists.selector);
        auction.start(castData, bidData, params, auth);
    }

    function testFuzz_BidChecksState(bytes32 castHash, uint96 bidderFid, uint256 bidAmount, bytes32 nonce) public {
        vm.assume(castHash != bytes32(0));
        bidderFid = uint96(_bound(bidderFid, 1, type(uint96).max));
        bidAmount = _bound(bidAmount, 1e6, 10000e6);

        // Ensure nonce doesn't collide with the one used in _startAuction
        vm.assume(nonce != keccak256("start-nonce-1"));

        // Try to bid on non-existent auction
        IAuction.BidData memory bidData = createBidData(bidderFid, bidAmount);

        // Create a dummy signature (65 bytes) to avoid ECDSA errors
        bytes memory dummySignature = new bytes(65);
        IAuction.AuthData memory auth = createAuthData(nonce, block.timestamp + 1 hours, dummySignature);

        vm.expectRevert(IAuction.AuctionNotActive.selector);
        auction.bid(castHash, bidData, auth);

        // Start auction
        _startAuction(castHash);

        // Now bidding should work (but will fail with ECDSAInvalidSignature due to invalid signature)
        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        auction.bid(castHash, bidData, auth);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Try to bid on ended auction
        vm.expectRevert(IAuction.AuctionNotActive.selector);
        auction.bid(castHash, bidData, auth);
    }

    function testFuzz_SettleChecksState(bytes32 castHash) public {
        vm.assume(castHash != bytes32(0));
        // Try to settle non-existent auction
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(castHash);

        // Start auction
        _startAuction(castHash);

        // Try to settle active auction
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(castHash);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Now should be able to settle (no longer reverts with "Not implemented")
        // Settlement will succeed and transition state to Settled
        auction.settle(castHash);

        // Verify state is now Settled
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Settled));
    }

    function _startAuction(bytes32 castHash) internal {
        _startAuctionWithParams(
            castHash,
            address(0x789), // creator
            67890, // creatorFid
            address(0x123), // bidder
            12345, // bidderFid
            1e6, // amount
            _getDefaultAuctionParams()
        );
    }

    // Test state transitions from Active state
    function test_StateTransition_ActiveToCancelled() public {
        bytes32 castHash = TEST_CAST_HASH;
        _startAuction(castHash);

        // Active state
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Active));

        // Creator cancels
        vm.prank(address(0x789)); // creator
        _cancelAuction(castHash);

        // Should now be Cancelled
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Cancelled));
    }

    function test_StateTransition_ActiveToRecovered() public {
        bytes32 castHash = TEST_CAST_HASH;
        _startAuction(castHash);

        // Active state
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Active));

        // Owner recovers
        vm.prank(auction.owner());
        auction.recover(castHash, address(0x999));

        // Should now be Recovered
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Recovered));
    }

    // Test state transitions from Ended state
    function test_StateTransition_EndedToCancelled() public {
        bytes32 castHash = TEST_CAST_HASH;
        _startAuction(castHash);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Ended state
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Ended));

        // Creator cancels
        vm.prank(address(0x789)); // creator
        _cancelAuction(castHash);

        // Should now be Cancelled
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Cancelled));
    }

    function test_StateTransition_EndedToRecovered() public {
        bytes32 castHash = TEST_CAST_HASH;
        _startAuction(castHash);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Ended state
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Ended));

        // Owner recovers
        vm.prank(auction.owner());
        auction.recover(castHash, address(0x999));

        // Should now be Recovered
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Recovered));
    }

    // Test that settled auctions cannot be settled again
    function test_SettledAuctionCannotBeSettledAgain() public {
        bytes32 castHash = TEST_CAST_HASH;
        _startAuction(castHash);

        // Fast forward and settle
        vm.warp(block.timestamp + 25 hours);
        auction.settle(castHash);

        // Verify Settled state
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Settled));

        // Cannot settle again
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(castHash);
    }

    function test_CancelledAuctionCannotBeSettled() public {
        bytes32 castHash = TEST_CAST_HASH;
        _startAuction(castHash);

        // Cancel auction
        _cancelAuction(castHash);

        // Verify Cancelled state
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Cancelled));

        // Cannot settle cancelled auction
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(castHash);
    }

    function test_RecoveredAuctionCannotBeSettled() public {
        bytes32 castHash = TEST_CAST_HASH;
        _startAuction(castHash);

        // Recover auction
        vm.prank(auction.owner());
        auction.recover(castHash, address(0x999));

        // Verify Recovered state
        assertEq(uint256(auction.auctionState(castHash)), uint256(IAuction.AuctionState.Recovered));

        // Cannot settle recovered auction
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(castHash);
    }

    function test_NonExistentAuctionCannotTransition() public {
        bytes32 nonExistentCastHash = keccak256("non-existent");

        // Verify None state
        assertEq(uint256(auction.auctionState(nonExistentCastHash)), uint256(IAuction.AuctionState.None));

        // Cannot settle
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(nonExistentCastHash);

        // Cannot bid
        IAuction.BidData memory bidData = createBidData(12345, 2e6);
        bytes memory dummySignature = new bytes(65);
        IAuction.AuthData memory auth2 =
            createAuthData(keccak256("test-nonce"), block.timestamp + 1 hours, dummySignature);
        vm.expectRevert(IAuction.AuctionNotActive.selector);
        auction.bid(nonExistentCastHash, bidData, auth2);
    }
}
