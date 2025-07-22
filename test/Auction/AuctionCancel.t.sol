// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "../../src/interfaces/IAuction.sol";
import {AuctionTestBase} from "./AuctionTestBase.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

contract AuctionCancelTest is AuctionTestBase {
    event AuctionCancelled(
        bytes32 indexed castHash, address indexed refundedBidder, uint96 indexed refundedBidderFid, address authorizer
    );
    event BidRefunded(bytes32 indexed castHash, address indexed to, uint256 amount);

    function setUp() public override {
        super.setUp();

        // Give USDC to bidder for fuzz tests
        usdc.mint(bidder, 10000e6);
        vm.prank(bidder);
        usdc.approve(address(auction), type(uint256).max);
    }

    function test_Cancel_RevertsIfAuctionDoesNotExist() public {
        bytes32 castHash = keccak256("nonexistent");
        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;

        // Sign cancellation
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectRevert(IAuction.AuctionNotCancellable.selector);
        auction.cancel(castHash, auth);
    }

    function test_Cancel_RevertsIfAuctionNotActive_Settled() public {
        // Create and settle an auction first
        bytes32 castHash = keccak256("test");
        _createAndSettleAuction(castHash);

        // Try to cancel settled auction
        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectRevert(IAuction.AuctionNotCancellable.selector);
        auction.cancel(castHash, auth);
    }

    function test_Cancel_AllowsEndedAuctions() public {
        // Create an auction and let it end
        bytes32 castHash = keccak256("test");
        uint256 bidAmount = 50e6; // 50 USDC
        _createActiveAuctionWithAmount(castHash, bidAmount);

        uint256 bidderBalanceBefore = usdc.balanceOf(bidder);

        // Prepare cancellation signature with deadline that will survive the warp
        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 3 days; // Set deadline longer than warp
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Warp past auction end
        vm.warp(block.timestamp + 2 days);

        auction.cancel(castHash, auth);

        // Check refund
        assertEq(usdc.balanceOf(bidder), bidderBalanceBefore + bidAmount);
        // Check state
        assertEq(uint8(auction.auctionState(castHash)), uint8(IAuction.AuctionState.Cancelled));
    }

    function test_Cancel_RevertsIfDeadlineExpired() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp - 1; // Expired deadline
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectRevert(IAuction.DeadlineExpired.selector);
        auction.cancel(castHash, auth);
    }

    function test_Cancel_RevertsIfNonceUsed() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Cancel once
        auction.cancel(castHash, auth);

        // Create a new auction with different cast hash to test nonce reuse
        bytes32 castHash2 = keccak256("test2");
        _createActiveAuction(castHash2);

        // Try to cancel the new auction with same nonce (should fail)
        bytes memory signature2 = _signCancelAuthorization(castHash2, nonce, deadline);
        IAuction.AuthData memory auth2 = createAuthData(nonce, deadline, signature2);

        vm.expectRevert(IAuction.NonceAlreadyUsed.selector);
        auction.cancel(castHash2, auth2);
    }

    function test_Cancel_RevertsIfInvalidSignature() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;

        // Sign with wrong private key
        // Sign with wrong key (creator instead of authorizer)
        bytes32 messageHash = auction.hashCancelAuthorization(castHash, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectRevert(IAuction.Unauthorized.selector);
        auction.cancel(castHash, auth);
    }

    function test_Cancel_RefundsHighestBidder() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        uint256 bidderBalanceBefore = usdc.balanceOf(bidder);

        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        auction.cancel(castHash, auth);

        // Check refund
        assertEq(usdc.balanceOf(bidder), bidderBalanceBefore + 10e6);
    }

    function test_Cancel_UpdatesAuctionState() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        auction.cancel(castHash, auth);

        // Check state
        assertEq(uint8(auction.auctionState(castHash)), uint8(IAuction.AuctionState.Cancelled));
    }

    function test_Cancel_EmitsEvent() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectEmit(true, true, false, true);
        emit AuctionCancelled(castHash, bidder, 2, authorizer); // FID is 2 from createBidData(2, amount)

        auction.cancel(castHash, auth);
    }

    function testFuzz_Cancel_WithVariousAmounts(uint256 bidAmount) public {
        bidAmount = _bound(bidAmount, 1e6, 1000e6); // Between 1 and 1000 USDC

        bytes32 castHash = keccak256("test");
        _createActiveAuctionWithAmount(castHash, bidAmount);

        uint256 bidderBalanceBefore = usdc.balanceOf(bidder);

        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        auction.cancel(castHash, auth);

        // Check full refund
        assertEq(usdc.balanceOf(bidder), bidderBalanceBefore + bidAmount);
        assertEq(uint8(auction.auctionState(castHash)), uint8(IAuction.AuctionState.Cancelled));
    }

    // Helper functions
    function _createActiveAuction(bytes32 castHash) internal {
        _createActiveAuctionWithAmount(castHash, 10e6);
    }

    function _createActiveAuctionWithAmount(bytes32 castHash, uint256 amount) internal {
        // Use base test helper to start auction
        _startAuctionWithParams(
            castHash,
            creator,
            1, // creatorFid
            bidder,
            2, // bidderFid
            amount,
            IAuction.AuctionParams({
                minBid: 1e6,
                minBidIncrementBps: 500, // 5%
                duration: 1 days,
                extension: 10 minutes,
                extensionThreshold: 10 minutes,
                protocolFeeBps: 500 // 5%
            })
        );
    }

    function test_Cancel_EmitsBidRefundedEvent() public {
        bytes32 castHash = keccak256("test");
        uint256 bidAmount = 100e6; // 100 USDC
        _createActiveAuctionWithAmount(castHash, bidAmount);

        // Prepare cancel authorization
        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Expect BidRefunded event
        vm.expectEmit(true, false, false, true);
        emit BidRefunded(castHash, bidder, bidAmount);

        // Also expect AuctionCancelled event
        vm.expectEmit(true, true, false, true);
        emit AuctionCancelled(castHash, bidder, 2, authorizer); // FID is 2 from createBidData(2, amount)

        auction.cancel(castHash, auth);
    }

    function test_Cancel_EmitsAuctionCancelledWithBidderFid() public {
        bytes32 castHash = keccak256("test-fid");
        uint96 expectedFid = 12345;
        uint256 bidAmount = 150e6; // 150 USDC

        // Create auction with specific FID
        bytes32 startNonce = keccak256(abi.encodePacked("startNonce", castHash));
        uint256 startDeadline = block.timestamp + 1 hours;

        IAuction.CastData memory cast = createCastData(castHash, creator, 1);
        IAuction.BidData memory bid = createBidData(expectedFid, bidAmount);
        IAuction.AuctionParams memory params = createAuctionParams(1e6, 500, 1 days, 10 minutes, 10 minutes, 500);

        bytes32 messageHash = auction.hashStartAuthorization(
            castHash, creator, 1, bidder, expectedFid, bidAmount, params, startNonce, startDeadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(startNonce, startDeadline, signature);

        vm.prank(bidder);
        auction.start(cast, bid, params, auth);

        // Now cancel and check event includes correct FID
        bytes32 cancelNonce = keccak256("cancel-nonce");
        uint256 cancelDeadline = block.timestamp + 1 hours;
        bytes memory cancelSignature = _signCancelAuthorization(castHash, cancelNonce, cancelDeadline);
        IAuction.AuthData memory cancelAuth = createAuthData(cancelNonce, cancelDeadline, cancelSignature);

        // Expect event with correct FID
        vm.expectEmit(true, true, false, true);
        emit AuctionCancelled(castHash, bidder, expectedFid, authorizer);

        auction.cancel(castHash, cancelAuth);
    }

    function test_Cancel_RevertsIfCancelledAuctionAlreadyCancelled() public {
        bytes32 castHash = keccak256("test-double-cancel");
        _createActiveAuction(castHash);

        // Cancel once
        bytes32 nonce1 = keccak256("nonce1");
        uint256 deadline1 = block.timestamp + 1 hours;
        bytes memory signature1 = _signCancelAuthorization(castHash, nonce1, deadline1);
        IAuction.AuthData memory auth1 = createAuthData(nonce1, deadline1, signature1);
        auction.cancel(castHash, auth1);

        // Try to cancel again
        bytes32 nonce2 = keccak256("nonce2");
        uint256 deadline2 = block.timestamp + 1 hours;
        bytes memory signature2 = _signCancelAuthorization(castHash, nonce2, deadline2);
        IAuction.AuthData memory auth2 = createAuthData(nonce2, deadline2, signature2);

        vm.expectRevert(IAuction.AuctionNotCancellable.selector);
        auction.cancel(castHash, auth2);
    }

    function test_Cancel_PreventsCancelAfterSettle() public {
        bytes32 castHash = keccak256("test-settle-then-cancel");
        _createActiveAuction(castHash);

        // Warp past auction end and settle
        vm.warp(block.timestamp + 2 days);
        auction.settle(castHash);

        // Try to cancel settled auction
        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectRevert(IAuction.AuctionNotCancellable.selector);
        auction.cancel(castHash, auth);
    }

    function test_Cancel_PreventsSettleAfterCancel() public {
        bytes32 castHash = keccak256("test-cancel-then-settle");
        _createActiveAuction(castHash);

        // Prepare cancellation signature with deadline that will survive the warp
        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 3 days; // Set deadline longer than warp
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Warp past auction end
        vm.warp(block.timestamp + 2 days);

        // Cancel first
        auction.cancel(castHash, auth);

        // Try to settle cancelled auction
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(castHash);
    }

    function _createAndSettleAuction(bytes32 castHash) internal {
        _createActiveAuction(castHash);

        // Warp past auction end
        vm.warp(block.timestamp + 2 days);

        // Settle
        auction.settle(castHash);
    }
}
