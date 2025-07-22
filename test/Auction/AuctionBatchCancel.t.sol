// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "../../src/interfaces/IAuction.sol";
import {AuctionTestBase} from "./AuctionTestBase.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";

contract AuctionBatchCancelTest is AuctionTestBase {
    event AuctionCancelled(
        bytes32 indexed castHash, address indexed refundedBidder, uint96 indexed refundedBidderFid, address authorizer
    );
    event BidRefunded(bytes32 indexed castHash, address indexed to, uint256 amount);

    function setUp() public override {
        super.setUp();
        // Give USDC to bidder for tests
        usdc.mint(bidder, 10000e6);
        vm.prank(bidder);
        usdc.approve(address(auction), 10000e6);
    }

    function test_BatchCancel_SingleAuction() public {
        // Create an active auction
        bytes32 castHash = keccak256("test1");
        _startAuctionWithParams(
            castHash,
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            bidder,
            DEFAULT_BIDDER_FID,
            100e6,
            _getDefaultAuctionParams()
        );

        // Prepare batch cancel data
        bytes32[] memory castHashes = new bytes32[](1);
        castHashes[0] = castHash;

        IAuction.AuthData[] memory authDatas = new IAuction.AuthData[](1);
        bytes32 nonce = keccak256("nonce1");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        authDatas[0] = createAuthData(nonce, deadline, signature);

        // Execute batch cancel
        uint256 bidderBalanceBefore = usdc.balanceOf(bidder);

        auction.batchCancel(castHashes, authDatas);

        // Verify auction was cancelled
        assertEq(uint8(auction.auctionState(castHash)), uint8(IAuction.AuctionState.Cancelled));
        assertEq(usdc.balanceOf(bidder), bidderBalanceBefore + 100e6);
    }

    function test_BatchCancel_MultipleAuctions() public {
        // Create multiple active auctions
        bytes32[] memory castHashes = new bytes32[](3);
        uint256[] memory amounts = new uint256[](3);
        castHashes[0] = keccak256("test1");
        castHashes[1] = keccak256("test2");
        castHashes[2] = keccak256("test3");
        amounts[0] = 100e6;
        amounts[1] = 200e6;
        amounts[2] = 300e6;

        // Start all auctions
        for (uint256 i = 0; i < 3; i++) {
            _startAuctionWithParams(
                castHashes[i],
                DEFAULT_CREATOR,
                DEFAULT_CREATOR_FID,
                bidder,
                DEFAULT_BIDDER_FID,
                amounts[i],
                _getDefaultAuctionParams()
            );
        }

        // Prepare batch cancel data
        IAuction.AuthData[] memory authDatas = new IAuction.AuthData[](3);
        for (uint256 i = 0; i < 3; i++) {
            bytes32 nonce = keccak256(abi.encode("nonce", i));
            uint256 deadline = block.timestamp + 1 hours;
            bytes memory signature = _signCancelAuthorization(castHashes[i], nonce, deadline);
            authDatas[i] = createAuthData(nonce, deadline, signature);
        }

        // Execute batch cancel
        uint256 bidderBalanceBefore = usdc.balanceOf(bidder);

        auction.batchCancel(castHashes, authDatas);

        // Verify all auctions were cancelled
        for (uint256 i = 0; i < 3; i++) {
            assertEq(uint8(auction.auctionState(castHashes[i])), uint8(IAuction.AuctionState.Cancelled));
        }
        assertEq(usdc.balanceOf(bidder), bidderBalanceBefore + 600e6); // Total refund
    }

    function test_BatchCancel_EmptyArrays() public {
        bytes32[] memory castHashes = new bytes32[](0);
        IAuction.AuthData[] memory authDatas = new IAuction.AuthData[](0);

        // Should succeed with no operations
        auction.batchCancel(castHashes, authDatas);
    }

    function test_BatchCancel_MismatchedArrayLengths() public {
        bytes32[] memory castHashes = new bytes32[](2);
        castHashes[0] = keccak256("test1");
        castHashes[1] = keccak256("test2");

        IAuction.AuthData[] memory authDatas = new IAuction.AuthData[](1);
        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancelAuthorization(castHashes[0], nonce, deadline);
        authDatas[0] = createAuthData(nonce, deadline, signature);

        vm.expectRevert(IAuction.InvalidAuctionParams.selector);
        auction.batchCancel(castHashes, authDatas);
    }

    function test_BatchCancel_RevertsIfOneAuctionFails() public {
        // Create two auctions
        bytes32 castHash1 = keccak256("test1");
        bytes32 castHash2 = keccak256("test2");

        // Only start the first auction
        _startAuctionWithParams(
            castHash1,
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            bidder,
            DEFAULT_BIDDER_FID,
            100e6,
            _getDefaultAuctionParams()
        );

        // Prepare batch cancel for both (second will fail)
        bytes32[] memory castHashes = new bytes32[](2);
        castHashes[0] = castHash1;
        castHashes[1] = castHash2;

        IAuction.AuthData[] memory authDatas = new IAuction.AuthData[](2);
        for (uint256 i = 0; i < 2; i++) {
            bytes32 nonce = keccak256(abi.encode("nonce", i));
            uint256 deadline = block.timestamp + 1 hours;
            bytes memory signature = _signCancelAuthorization(castHashes[i], nonce, deadline);
            authDatas[i] = createAuthData(nonce, deadline, signature);
        }

        // Should revert because second auction doesn't exist
        vm.expectRevert(IAuction.AuctionNotCancellable.selector);
        auction.batchCancel(castHashes, authDatas);

        // Verify first auction is still active (rollback happened)
        assertEq(uint8(auction.auctionState(castHash1)), uint8(IAuction.AuctionState.Active));
    }

    function test_BatchCancel_EmitsEventsForEachCancellation() public {
        // Create two auctions
        bytes32[] memory castHashes = new bytes32[](2);
        castHashes[0] = keccak256("test1");
        castHashes[1] = keccak256("test2");

        for (uint256 i = 0; i < 2; i++) {
            _startAuctionWithParams(
                castHashes[i],
                DEFAULT_CREATOR,
                DEFAULT_CREATOR_FID,
                bidder,
                DEFAULT_BIDDER_FID,
                100e6 * (i + 1),
                _getDefaultAuctionParams()
            );
        }

        // Prepare batch cancel
        IAuction.AuthData[] memory authDatas = new IAuction.AuthData[](2);
        for (uint256 i = 0; i < 2; i++) {
            bytes32 nonce = keccak256(abi.encode("nonce", i));
            uint256 deadline = block.timestamp + 1 hours;
            bytes memory signature = _signCancelAuthorization(castHashes[i], nonce, deadline);
            authDatas[i] = createAuthData(nonce, deadline, signature);
        }

        // Expect events for each cancellation
        vm.expectEmit(true, true, false, true);
        emit BidRefunded(castHashes[0], bidder, 100e6);
        vm.expectEmit(true, true, true, true);
        emit AuctionCancelled(castHashes[0], bidder, DEFAULT_BIDDER_FID, authorizer);

        vm.expectEmit(true, true, false, true);
        emit BidRefunded(castHashes[1], bidder, 200e6);
        vm.expectEmit(true, true, true, true);
        emit AuctionCancelled(castHashes[1], bidder, DEFAULT_BIDDER_FID, authorizer);

        auction.batchCancel(castHashes, authDatas);
    }

    function test_BatchCancel_RevertsWhenPaused() public {
        bytes32 castHash = keccak256("test");
        _startAuctionWithParams(
            castHash,
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            bidder,
            DEFAULT_BIDDER_FID,
            100e6,
            _getDefaultAuctionParams()
        );

        bytes32[] memory castHashes = new bytes32[](1);
        castHashes[0] = castHash;

        IAuction.AuthData[] memory authDatas = new IAuction.AuthData[](1);
        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        authDatas[0] = createAuthData(nonce, deadline, signature);

        // Pause the contract
        vm.prank(owner);
        auction.pause();

        // Should revert when paused
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        auction.batchCancel(castHashes, authDatas);
    }

    function testFuzz_BatchCancel_VariousAmounts(uint8 numAuctions, uint256 baseSeed) public {
        numAuctions = uint8(_bound(numAuctions, 1, 10)); // Limit to reasonable number

        bytes32[] memory castHashes = new bytes32[](numAuctions);
        uint256[] memory amounts = new uint256[](numAuctions);
        uint256 totalAmount = 0;

        // Create auctions
        for (uint256 i = 0; i < numAuctions; i++) {
            castHashes[i] = keccak256(abi.encode("test", i));
            amounts[i] = _bound(uint256(keccak256(abi.encode(baseSeed, i))), 1e6, 1000e6);
            totalAmount += amounts[i];

            _startAuctionWithParams(
                castHashes[i],
                DEFAULT_CREATOR,
                DEFAULT_CREATOR_FID,
                bidder,
                DEFAULT_BIDDER_FID,
                amounts[i],
                _getDefaultAuctionParams()
            );
        }

        // Prepare batch cancel
        IAuction.AuthData[] memory authDatas = new IAuction.AuthData[](numAuctions);
        for (uint256 i = 0; i < numAuctions; i++) {
            bytes32 nonce = keccak256(abi.encode("nonce", i));
            uint256 deadline = block.timestamp + 1 hours;
            bytes memory signature = _signCancelAuthorization(castHashes[i], nonce, deadline);
            authDatas[i] = createAuthData(nonce, deadline, signature);
        }

        uint256 bidderBalanceBefore = usdc.balanceOf(bidder);

        auction.batchCancel(castHashes, authDatas);

        // Verify all cancelled and refunded
        for (uint256 i = 0; i < numAuctions; i++) {
            assertEq(uint8(auction.auctionState(castHashes[i])), uint8(IAuction.AuctionState.Cancelled));
        }
        assertEq(usdc.balanceOf(bidder), bidderBalanceBefore + totalAmount);
    }
}
