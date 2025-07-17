// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {CollectibleCasts} from "../../src/CollectibleCasts.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";

contract AuctionSettleTest is Test, AuctionTestHelper {
    Auction public auction;
    MockUSDC public usdc;
    CollectibleCasts public collectibleCast;

    address public constant TREASURY = address(0x4);

    address public authorizer;
    uint256 public authorizerKey;

    bytes32 public constant TEST_CAST_HASH = keccak256("test-cast");
    address public constant CREATOR = address(0x789);
    uint96 public constant CREATOR_FID = 67890;

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

    function testFuzz_Settle_Success(address bidder, uint96 bidderFid, uint256 amount) public {
        // Bound inputs
        vm.assume(bidder != address(0));
        vm.assume(bidder != CREATOR); // Bidder must be different from creator
        vm.assume(bidder.code.length == 0); // Must be EOA to receive ERC-1155 tokens safely
        bidderFid = uint96(_bound(bidderFid, 1, type(uint96).max));
        amount = _bound(amount, 1e6, 1000000e6); // 1 to 1,000,000 USDC

        // Start auction
        _startAuction(bidder, bidderFid, amount);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Record balances before settlement
        uint256 treasuryBalanceBefore = usdc.balanceOf(TREASURY);
        uint256 creatorBalanceBefore = usdc.balanceOf(CREATOR);

        // Settle auction
        auction.settle(TEST_CAST_HASH);

        // Verify payment distribution (90% to creator, 10% to treasury based on default protocol fee)
        uint256 treasuryAmount = (amount * 1000) / 10000; // 10% (1000 basis points)
        uint256 creatorAmount = amount - treasuryAmount;

        assertEq(usdc.balanceOf(TREASURY), treasuryBalanceBefore + treasuryAmount);
        assertEq(usdc.balanceOf(CREATOR), creatorBalanceBefore + creatorAmount);

        // Verify NFT was minted to the bidder
        uint256 tokenId = uint256(TEST_CAST_HASH);
        assertEq(collectibleCast.balanceOf(bidder), 1);
        assertEq(collectibleCast.ownerOf(tokenId), bidder);
        assertEq(collectibleCast.tokenFid(tokenId), CREATOR_FID);
        assertEq(collectibleCast.tokenCreator(tokenId), CREATOR);

        // Verify auction is marked as settled
        assertEq(uint256(auction.auctionState(TEST_CAST_HASH)), uint256(IAuction.AuctionState.Settled));
    }

    function test_Settle_RevertsIfCancelled() public {
        // Start an auction
        address bidder = address(0x123);
        uint96 bidderFid = 12345;
        uint256 amount = 100e6;
        _startAuctionWithParams(TEST_CAST_HASH, CREATOR, CREATOR_FID, bidder, bidderFid, amount);

        // Cancel it
        bytes32 nonce = keccak256("cancel-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash = auction.hashCancelAuthorization(TEST_CAST_HASH, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        auction.cancel(TEST_CAST_HASH, auth);

        // Try to settle the cancelled auction
        vm.expectRevert(IAuction.AuctionIsCancelled.selector);
        auction.settle(TEST_CAST_HASH);
    }

    function test_Settle_RevertsIfNotEnded() public {
        // Start auction
        address bidder = address(0x123);
        uint96 bidderFid = 12345;
        uint256 amount = 100e6;
        _startAuction(bidder, bidderFid, amount);

        // Try to settle while still active
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(TEST_CAST_HASH);
    }

    function test_Settle_RevertsIfAlreadySettled() public {
        // Start auction
        address bidder = address(0x123);
        uint96 bidderFid = 12345;
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

        vm.expectRevert(IAuction.AuctionNotFound.selector);
        auction.settle(nonExistentTokenId);
    }

    event AuctionSettled(bytes32 indexed castHash, address indexed winner, uint96 winnerFid, uint256 amount);

    function test_BatchSettle_Success() public {
        // Create multiple auctions
        bytes32[] memory castHashes = new bytes32[](3);
        castHashes[0] = keccak256("cast-1");
        castHashes[1] = keccak256("cast-2");
        castHashes[2] = keccak256("cast-3");

        address[] memory bidders = new address[](3);
        bidders[0] = address(0x100);
        bidders[1] = address(0x200);
        bidders[2] = address(0x300);

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
            _startAuctionWithParams(castHashes[i], CREATOR, CREATOR_FID, bidders[i], bidderFids[i], amounts[i]);
        }

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Record balances before batch settlement
        uint256 treasuryBalanceBefore = usdc.balanceOf(TREASURY);
        uint256 creatorBalanceBefore = usdc.balanceOf(CREATOR);

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

        assertEq(usdc.balanceOf(TREASURY), treasuryBalanceBefore + totalTreasuryAmount);
        assertEq(usdc.balanceOf(CREATOR), creatorBalanceBefore + totalCreatorAmount);

        // Verify all NFTs were minted to correct bidders
        for (uint256 i = 0; i < 3; i++) {
            uint256 tokenId = uint256(castHashes[i]);
            assertEq(collectibleCast.balanceOf(bidders[i]), 1);
            assertEq(collectibleCast.ownerOf(tokenId), bidders[i]);
            assertEq(uint256(auction.auctionState(castHashes[i])), uint256(IAuction.AuctionState.Settled));
        }
    }

    function test_BatchSettle_EmptyArray() public {
        bytes32[] memory emptyCastHashes = new bytes32[](0);

        // Should not revert with empty array
        auction.batchSettle(emptyCastHashes);
    }

    function test_BatchSettle_SingleAuction() public {
        // Start one auction
        address bidder = address(0x123);
        uint96 bidderFid = 12345;
        uint256 amount = 1e6;
        _startAuction(bidder, bidderFid, amount);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Create array with single cast hash
        bytes32[] memory castHashes = new bytes32[](1);
        castHashes[0] = TEST_CAST_HASH;

        // Batch settle single auction
        auction.batchSettle(castHashes);

        // Verify settlement
        assertEq(uint256(auction.auctionState(TEST_CAST_HASH)), uint256(IAuction.AuctionState.Settled));
        assertEq(collectibleCast.ownerOf(uint256(TEST_CAST_HASH)), bidder);
    }

    function test_BatchSettle_RevertsOnNonExistentAuction() public {
        bytes32[] memory castHashes = new bytes32[](2);
        castHashes[0] = keccak256("valid-cast");
        castHashes[1] = keccak256("non-existent");

        // Start only the first auction
        address bidder = address(0x123);
        uint96 bidderFid = 12345;
        uint256 amount = 1e6;
        _startAuctionWithParams(castHashes[0], CREATOR, CREATOR_FID, bidder, bidderFid, amount);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Should revert when trying to settle non-existent auction
        vm.expectRevert(IAuction.AuctionNotFound.selector);
        auction.batchSettle(castHashes);
    }

    function test_BatchSettle_RevertsOnActiveAuction() public {
        bytes32[] memory castHashes = new bytes32[](2);
        castHashes[0] = keccak256("ended-cast");
        castHashes[1] = keccak256("active-cast");

        // Start both auctions with different end times
        address bidder1 = address(0x123);
        address bidder2 = address(0x456);
        uint96 bidderFid = 12345;
        uint256 amount = 1e6;

        _startAuctionWithParams(castHashes[0], CREATOR, CREATOR_FID, bidder1, bidderFid, amount);

        // Start second auction 1 hour later (so it ends later)
        vm.warp(block.timestamp + 1 hours);
        _startAuctionWithParams(castHashes[1], CREATOR, CREATOR_FID, bidder2, bidderFid + 1, amount);

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
        address bidder1 = address(0x123);
        address bidder2 = address(0x456);
        uint96 bidderFid = 12345;
        uint256 amount = 1e6;

        _startAuctionWithParams(castHashes[0], CREATOR, CREATOR_FID, bidder1, bidderFid, amount);
        _startAuctionWithParams(castHashes[1], CREATOR, CREATOR_FID, bidder2, bidderFid + 1, amount);

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Settle one auction individually
        auction.settle(castHashes[1]);

        // Should revert when trying to settle already settled auction
        vm.expectRevert(IAuction.AuctionAlreadySettled.selector);
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
            bidders[i] = address(uint160(0x1000 + i));
            amounts[i] = (i + 1) * 1e6; // 1, 2, 3, ... USDC

            _startAuctionWithParams(castHashes[i], CREATOR, CREATOR_FID, bidders[i], uint96(10000 + i), amounts[i]);
        }

        // Fast forward past end time
        vm.warp(block.timestamp + 25 hours);

        // Record balances before
        uint256 treasuryBalanceBefore = usdc.balanceOf(TREASURY);
        uint256 creatorBalanceBefore = usdc.balanceOf(CREATOR);

        // Batch settle
        auction.batchSettle(castHashes);

        // Verify all settled
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < numAuctions; i++) {
            assertEq(uint256(auction.auctionState(castHashes[i])), uint256(IAuction.AuctionState.Settled));
            assertEq(collectibleCast.ownerOf(uint256(castHashes[i])), bidders[i]);
            totalAmount += amounts[i];
        }

        // Verify payments
        uint256 expectedTreasuryAmount = (totalAmount * 1000) / 10000; // 10%
        uint256 expectedCreatorAmount = totalAmount - expectedTreasuryAmount;

        assertEq(usdc.balanceOf(TREASURY), treasuryBalanceBefore + expectedTreasuryAmount);
        assertEq(usdc.balanceOf(CREATOR), creatorBalanceBefore + expectedCreatorAmount);
    }

    function _startAuction(address bidder, uint96 bidderFid, uint256 amount) internal {
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

    function _startAuctionWithParams(
        bytes32 castHash,
        address creator,
        uint96 creatorFid,
        address bidder,
        uint96 bidderFid,
        uint256 amount
    ) internal {
        bytes32 nonce = keccak256(abi.encodePacked("start-nonce", castHash));
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
