// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockCollectibleCasts} from "../mocks/MockCollectibleCasts.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

contract AuctionCancelTest is TestSuiteSetup, AuctionTestHelper {
    event AuctionCancelled(bytes32 indexed castHash, address indexed refundedBidder, address indexed authorizer);

    Auction public auction;
    MockCollectibleCasts public collectibleCast;
    MockUSDC public usdc;

    address public treasury;
    address public owner;
    address public authorizer;
    uint256 public authorizerPk;
    address public creator;
    uint256 public creatorPk;
    address public bidder;
    uint256 public bidderPk;

    function setUp() public override {
        super.setUp();

        // Create named addresses
        treasury = makeAddr("treasury");
        owner = makeAddr("owner");
        (authorizer, authorizerPk) = makeAddrAndKey("authorizer");
        (creator, creatorPk) = makeAddrAndKey("creator");
        (bidder, bidderPk) = makeAddrAndKey("bidder");

        // Deploy contracts
        collectibleCast = new MockCollectibleCasts();
        usdc = new MockUSDC();
        auction = new Auction(address(collectibleCast), address(usdc), treasury, owner);

        // Setup
        collectibleCast.allowMinter(address(auction));
        vm.prank(owner);
        auction.allowAuthorizer(authorizer);

        // Give USDC to bidder
        usdc.mint(bidder, 10000e6); // Give more USDC for fuzz tests
        vm.prank(bidder);
        usdc.approve(address(auction), type(uint256).max);
    }

    function test_Cancel_RevertsIfAuctionDoesNotExist() public {
        bytes32 castHash = keccak256("nonexistent");
        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;

        // Sign cancellation
        bytes memory signature = _signCancellation(castHash, nonce, deadline, authorizerPk);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectRevert(IAuction.AuctionNotFound.selector);
        auction.cancel(castHash, auth);
    }

    function test_Cancel_RevertsIfAuctionNotActive_Settled() public {
        // Create and settle an auction first
        bytes32 castHash = keccak256("test");
        _createAndSettleAuction(castHash);

        // Try to cancel settled auction
        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancellation(castHash, nonce, deadline, authorizerPk);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectRevert(IAuction.AuctionNotActive.selector);
        auction.cancel(castHash, auth);
    }

    function test_Cancel_RevertsIfAuctionNotActive_Ended() public {
        // Create an auction and let it end
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        // Warp past auction end
        vm.warp(block.timestamp + 2 days);

        // Try to cancel ended auction
        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancellation(castHash, nonce, deadline, authorizerPk);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectRevert(IAuction.AuctionNotActive.selector);
        auction.cancel(castHash, auth);
    }

    function test_Cancel_RevertsIfDeadlineExpired() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp - 1; // Expired deadline
        bytes memory signature = _signCancellation(castHash, nonce, deadline, authorizerPk);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectRevert(IAuction.DeadlineExpired.selector);
        auction.cancel(castHash, auth);
    }

    function test_Cancel_RevertsIfNonceUsed() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancellation(castHash, nonce, deadline, authorizerPk);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Cancel once
        auction.cancel(castHash, auth);

        // Create a new auction with different cast hash to test nonce reuse
        bytes32 castHash2 = keccak256("test2");
        _createActiveAuction(castHash2);

        // Try to cancel the new auction with same nonce (should fail)
        bytes memory signature2 = _signCancellation(castHash2, nonce, deadline, authorizerPk);
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
        bytes memory signature = _signCancellation(castHash, nonce, deadline, creatorPk);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectRevert(IAuction.InvalidSignature.selector);
        auction.cancel(castHash, auth);
    }

    function test_Cancel_RefundsHighestBidder() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        uint256 bidderBalanceBefore = usdc.balanceOf(bidder);

        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancellation(castHash, nonce, deadline, authorizerPk);
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
        bytes memory signature = _signCancellation(castHash, nonce, deadline, authorizerPk);
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
        bytes memory signature = _signCancellation(castHash, nonce, deadline, authorizerPk);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        vm.expectEmit(true, true, true, true);
        emit AuctionCancelled(castHash, bidder, authorizer);

        auction.cancel(castHash, auth);
    }

    function testFuzz_Cancel_WithVariousAmounts(uint256 bidAmount) public {
        bidAmount = _bound(bidAmount, 1e6, 1000e6); // Between 1 and 1000 USDC

        bytes32 castHash = keccak256("test");
        _createActiveAuctionWithAmount(castHash, bidAmount);

        uint256 bidderBalanceBefore = usdc.balanceOf(bidder);

        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancellation(castHash, nonce, deadline, authorizerPk);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        auction.cancel(castHash, auth);

        // Check full refund
        assertEq(usdc.balanceOf(bidder), bidderBalanceBefore + bidAmount);
        assertEq(uint8(auction.auctionState(castHash)), uint8(IAuction.AuctionState.Cancelled));
    }

    // Helper functions
    function _signCancellation(bytes32 castHash, bytes32 nonce, uint256 deadline, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = auction.hashCancelAuthorization(castHash, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function _createActiveAuction(bytes32 castHash) internal {
        _createActiveAuctionWithAmount(castHash, 10e6);
    }

    function _createActiveAuctionWithAmount(bytes32 castHash, uint256 amount) internal {
        // Setup auction parameters
        bytes32 startNonce = keccak256(abi.encodePacked("startNonce", castHash)); // Make nonce unique per auction
        uint256 startDeadline = block.timestamp + 1 hours;

        IAuction.CastData memory cast = createCastData(castHash, creator, 1);
        IAuction.BidData memory bid = createBidData(2, amount);
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            500, // minBidIncrementBps (5%)
            1 days, // duration
            10 minutes, // extension
            10 minutes, // extensionThreshold
            500 // protocolFeeBps (5%)
        );

        // Sign start authorization
        bytes32 messageHash = auction.hashStartAuthorization(
            castHash,
            creator,
            1, // creatorFid
            bidder,
            2, // bidderFid
            amount,
            params,
            startNonce,
            startDeadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(startNonce, startDeadline, signature);

        // Start auction
        vm.prank(bidder);
        auction.start(cast, bid, params, auth);
    }

    function _createAndSettleAuction(bytes32 castHash) internal {
        _createActiveAuction(castHash);

        // Warp past auction end
        vm.warp(block.timestamp + 2 days);

        // Settle
        auction.settle(castHash);
    }
}
