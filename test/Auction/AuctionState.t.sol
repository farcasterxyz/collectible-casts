// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {CollectibleCasts} from "../../src/CollectibleCasts.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";

contract AuctionStateTest is Test, AuctionTestHelper {
    Auction public auction;
    MockUSDC public usdc;
    CollectibleCasts public collectibleCast;

    address public constant TREASURY = address(0x4);

    address public authorizer;
    uint256 public authorizerKey;

    bytes32 public constant TEST_CAST_HASH = keccak256("test-cast");

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

    function testFuzz_StateTransitions(bytes32 castHash) public {
        vm.assume(castHash != bytes32(0));
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
        IAuction.AuctionParams memory params = createAuctionParams(
            1e6, // minBid
            1000, // minBidIncrement
            24 hours, // duration
            15 minutes, // extension
            15 minutes, // extensionThreshold
            1000 // protocolFee
        );

        bytes32 messageHash = auction.hashStartAuthorization(
            castHash, creator, creatorFid, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
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
        address creator = address(0x789);
        uint96 creatorFid = 67890;
        address bidder = address(0x123);
        uint96 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce-1");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(castHash, creator, creatorFid);
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
            castHash, creator, creatorFid, bidder, bidderFid, amount, params, nonce, deadline
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
