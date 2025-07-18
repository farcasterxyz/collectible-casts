// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "../../src/interfaces/IAuction.sol";
import {AuctionTestBase} from "./AuctionTestBase.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract AuctionPausableTest is AuctionTestBase {
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public override {
        super.setUp();

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
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Should revert
        vm.expectRevert(Pausable.EnforcedPause.selector);
        auction.cancel(castHash, auth);
    }

    // Helper functions
    function _createActiveAuction(bytes32 castHash) internal {
        _startAuctionWithParams(
            castHash,
            creator,
            1, // creatorFid
            bidder,
            2, // bidderFid
            10e6, // amount
            IAuction.AuctionParams({
                minBid: 10e6,
                minBidIncrementBps: 500, // 5%
                duration: 1 days,
                extension: 10 minutes,
                extensionThreshold: 10 minutes,
                protocolFeeBps: 500 // 5%
            })
        );
    }
}
