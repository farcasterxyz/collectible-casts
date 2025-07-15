// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockCollectibleCasts} from "../mocks/MockCollectibleCasts.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract AuctionPausableTest is Test, AuctionTestHelper {
    event Paused(address account);
    event Unpaused(address account);

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

    function setUp() public {
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
        usdc.mint(bidder, 100e6);
        vm.prank(bidder);
        usdc.approve(address(auction), type(uint256).max);
    }

    function test_Pause_OnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        auction.pause();
    }

    function test_Pause_Success() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit Paused(owner);
        auction.pause();

        assertTrue(auction.paused());
    }

    function test_Unpause_OnlyOwner() public {
        // First pause
        vm.prank(owner);
        auction.pause();

        // Try to unpause as non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        auction.unpause();
    }

    function test_Unpause_Success() public {
        // First pause
        vm.prank(owner);
        auction.pause();

        // Then unpause
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit Unpaused(owner);
        auction.unpause();

        assertFalse(auction.paused());
    }

    function test_Start_RevertsWhenPaused() public {
        // Pause the contract
        vm.prank(owner);
        auction.pause();

        // Try to start auction
        bytes32 castHash = keccak256("test");
        IAuction.CastData memory cast = createCastData(castHash, creator, 1);
        IAuction.BidData memory bid = createBidData(2, 10e6);
        IAuction.AuctionParams memory params = createAuctionParams(10e6, 500, 1 days, 10 minutes, 10 minutes, 500);
        IAuction.AuthData memory auth = createAuthData(keccak256("nonce"), block.timestamp + 1 hours, "");

        vm.prank(bidder);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        auction.start(cast, bid, params, auth);
    }

    function test_Bid_RevertsWhenPaused() public {
        // First create an auction
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        // Pause the contract
        vm.prank(owner);
        auction.pause();

        // Try to bid
        IAuction.BidData memory bid = createBidData(3, 20e6);
        IAuction.AuthData memory auth = createAuthData(keccak256("bidNonce"), block.timestamp + 1 hours, "");

        vm.prank(bidder);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        auction.bid(castHash, bid, auth);
    }

    function test_Settle_RevertsWhenPaused() public {
        // First create and end an auction
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);
        vm.warp(block.timestamp + 2 days);

        // Pause the contract
        vm.prank(owner);
        auction.pause();

        // Try to settle
        vm.expectRevert(Pausable.EnforcedPause.selector);
        auction.settle(castHash);
    }

    function test_Cancel_RevertsWhenPaused() public {
        // First create an auction
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        // Pause the contract
        vm.prank(owner);
        auction.pause();

        // Cancel should also be paused since it uses authorizer signatures
        bytes32 nonce = keccak256("cancelNonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancellation(castHash, nonce, deadline, authorizerPk);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Should revert
        vm.expectRevert(Pausable.EnforcedPause.selector);
        auction.cancel(castHash, auth);
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
        // Setup auction parameters
        bytes32 startNonce = keccak256(abi.encodePacked("startNonce", castHash));
        uint256 startDeadline = block.timestamp + 1 hours;

        IAuction.CastData memory cast = createCastData(castHash, creator, 1);
        IAuction.BidData memory bid = createBidData(2, 10e6);
        IAuction.AuctionParams memory params = createAuctionParams(
            10e6, // minBid
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
            10e6,
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
}
