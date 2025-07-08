// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockMinter} from "../mocks/MockMinter.sol";
import {MockCollectibleCast} from "../mocks/MockCollectibleCast.sol";
import {AuctionTestHelper} from "../shared/AuctionTestHelper.sol";

contract AuctionSettleTest is Test, AuctionTestHelper {
    Auction public auction;
    MockERC20 public usdc;
    MockMinter public minter;
    MockCollectibleCast public collectibleCast;

    address public constant TREASURY = address(0x4);

    address public authorizer;
    uint256 public authorizerKey;

    bytes32 public constant TEST_CAST_HASH = keccak256("test-cast");
    address public constant CREATOR = address(0x789);
    uint256 public constant CREATOR_FID = 67890;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        collectibleCast = new MockCollectibleCast();
        minter = new MockMinter();
        minter.setToken(address(collectibleCast));
        auction = new Auction(address(minter), address(usdc), TREASURY, address(this));

        // Allow auction contract to mint
        minter.allow(address(auction));

        (authorizer, authorizerKey) = makeAddrAndKey("authorizer");
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
    }

    function test_Settle_Success() public {
        // Start auction
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 100e6; // 100 USDC
        _startAuction(bidder, bidderFid, amount);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Record balances before settlement
        uint256 treasuryBalanceBefore = usdc.balanceOf(TREASURY);
        uint256 creatorBalanceBefore = usdc.balanceOf(CREATOR);

        // Settle auction
        vm.expectEmit(true, true, false, true);
        emit AuctionSettled(TEST_CAST_HASH, bidder, bidderFid, amount);

        auction.settle(TEST_CAST_HASH);

        // Verify payment distribution (90% to creator, 10% to treasury based on default protocol fee)
        uint256 treasuryAmount = (amount * 1000) / 10000; // 10% (1000 basis points)
        uint256 creatorAmount = amount - treasuryAmount;

        assertEq(usdc.balanceOf(TREASURY), treasuryBalanceBefore + treasuryAmount);
        assertEq(usdc.balanceOf(CREATOR), creatorBalanceBefore + creatorAmount);

        // Verify NFT was minted
        assertTrue(minter.mintCalled());
        assertEq(minter.lastMintTo(), bidder);
        assertEq(minter.lastCastHash(), TEST_CAST_HASH);
        assertEq(minter.lastFid(), CREATOR_FID); // Creator's FID, not bidder's
        assertEq(minter.lastCreator(), CREATOR);

        // Verify auction is marked as settled
        assertEq(uint256(auction.getAuctionState(TEST_CAST_HASH)), uint256(IAuction.AuctionState.Settled));
    }

    function test_Settle_RevertsIfNotEnded() public {
        // Start auction
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 100e6;
        _startAuction(bidder, bidderFid, amount);

        // Try to settle while still active
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(TEST_CAST_HASH);
    }

    function test_Settle_RevertsIfAlreadySettled() public {
        // Start auction
        address bidder = address(0x123);
        uint256 bidderFid = 12345;
        uint256 amount = 100e6;
        _startAuction(bidder, bidderFid, amount);

        // Fast forward and settle
        vm.warp(block.timestamp + 25 hours);
        auction.settle(TEST_CAST_HASH);

        // Try to settle again
        vm.expectRevert(IAuction.AuctionAlreadySettled.selector);
        auction.settle(TEST_CAST_HASH);
    }

    function test_Settle_RevertsIfNonExistent() public {
        bytes32 nonExistentTokenId = keccak256("non-existent");

        vm.expectRevert(IAuction.AuctionDoesNotExist.selector);
        auction.settle(nonExistentTokenId);
    }

    event AuctionSettled(bytes32 indexed castHash, address indexed winner, uint256 winnerFid, uint256 amount);

    function _startAuction(address bidder, uint256 bidderFid, uint256 amount) internal {
        bytes32 nonce = keccak256("start-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, CREATOR, CREATOR_FID);
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
            TEST_CAST_HASH, CREATOR, CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
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
