// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockMinter} from "../mocks/MockMinter.sol";
import {MockCollectibleCast} from "../mocks/MockCollectibleCast.sol";
import {AuctionTestHelper} from "../shared/AuctionTestHelper.sol";

contract AuctionStateTest is Test, AuctionTestHelper {
    Auction public auction;
    MockERC20 public usdc;
    MockMinter public minter;
    MockCollectibleCast public collectibleCast;

    address public constant TREASURY = address(0x4);

    address public authorizer;
    uint256 public authorizerKey;

    bytes32 public constant TEST_CAST_HASH = keccak256("test-cast");

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        collectibleCast = new MockCollectibleCast();
        minter = new MockMinter(address(collectibleCast));
        auction = new Auction(address(minter), address(usdc), TREASURY);

        // Allow auction contract to mint
        minter.allow(address(auction));

        (authorizer, authorizerKey) = makeAddrAndKey("authorizer");
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
    }

    function test_StateTransitions() public {
        // Initially, auction should be in None state
        assertEq(uint256(auction.getAuctionState(TEST_CAST_HASH)), uint256(IAuction.AuctionState.None));

        // Start auction
        _startAuction();

        // Should now be Active
        assertEq(uint256(auction.getAuctionState(TEST_CAST_HASH)), uint256(IAuction.AuctionState.Active));

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Should now be Ended (automatically detected)
        assertEq(uint256(auction.getAuctionState(TEST_CAST_HASH)), uint256(IAuction.AuctionState.Ended));

        // Settle the auction
        auction.settle(TEST_CAST_HASH);

        // State should now be Settled
        assertEq(uint256(auction.getAuctionState(TEST_CAST_HASH)), uint256(IAuction.AuctionState.Settled));
    }

    function test_CannotStartAuctionTwice() public {
        _startAuction();

        // Try to start again
        address creator = address(0x789);
        uint256 creatorFid = 67890;
        address bidder = address(0x456);
        uint256 bidderFid = 54321;
        uint256 amount = 2e6;
        bytes32 nonce = keccak256("start-nonce-2");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, creator, creatorFid);
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
            TEST_CAST_HASH, creator, creatorFid, bidder, bidderFid, amount, params, nonce, deadline
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

    function test_BidChecksState() public {
        // Try to bid on non-existent auction
        IAuction.BidData memory bidData = createBidData(12345, 2e6);
        IAuction.AuthData memory auth = createAuthData(keccak256("nonce"), block.timestamp + 1 hours, "");
        
        vm.expectRevert(IAuction.AuctionDoesNotExist.selector);
        auction.bid(TEST_CAST_HASH, bidData, auth);

        // Start auction
        _startAuction();

        // Now bidding should work (but will fail with UnauthorizedBidder due to invalid signature)
        vm.expectRevert(IAuction.UnauthorizedBidder.selector);
        auction.bid(TEST_CAST_HASH, bidData, auth);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Try to bid on ended auction
        vm.expectRevert(IAuction.AuctionNotActive.selector);
        auction.bid(TEST_CAST_HASH, bidData, auth);
    }

    function test_SettleChecksState() public {
        // Try to settle non-existent auction
        vm.expectRevert(IAuction.AuctionDoesNotExist.selector);
        auction.settle(TEST_CAST_HASH);

        // Start auction
        _startAuction();

        // Try to settle active auction
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(TEST_CAST_HASH);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Now should be able to settle (no longer reverts with "Not implemented")
        // Settlement will succeed and transition state to Settled
        auction.settle(TEST_CAST_HASH);

        // Verify state is now Settled
        assertEq(uint256(auction.getAuctionState(TEST_CAST_HASH)), uint256(IAuction.AuctionState.Settled));
    }

    function _startAuction() internal {
        address creator = address(0x789);
        uint256 creatorFid = 67890;
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 1e6;
        bytes32 nonce = keccak256("start-nonce-1");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, creator, creatorFid);
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
            TEST_CAST_HASH, creator, creatorFid, bidder, bidderFid, amount, params, nonce, deadline
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
