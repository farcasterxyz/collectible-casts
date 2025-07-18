// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockCollectibleCasts} from "../mocks/MockCollectibleCasts.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract AuctionRecoverTest is TestSuiteSetup, AuctionTestHelper {
    event AuctionRecovered(bytes32 indexed castHash, address indexed refundTo, uint256 amount);

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
    address public recoveryAddress;

    function setUp() public override {
        super.setUp();

        // Create named addresses
        treasury = makeAddr("treasury");
        owner = makeAddr("owner");
        (authorizer, authorizerPk) = makeAddrAndKey("authorizer");
        (creator, creatorPk) = makeAddrAndKey("creator");
        (bidder, bidderPk) = makeAddrAndKey("bidder");
        recoveryAddress = makeAddr("recoveryAddress");

        // Deploy contracts
        collectibleCast = new MockCollectibleCasts();
        usdc = new MockUSDC();
        auction = new Auction(address(collectibleCast), address(usdc), treasury, owner);

        // Setup
        collectibleCast.allowMinter(address(auction));
        vm.prank(owner);
        auction.allowAuthorizer(authorizer);

        // Give USDC to bidder
        usdc.mint(bidder, 10000e6);
        vm.prank(bidder);
        usdc.approve(address(auction), type(uint256).max);
    }

    function test_Recover_OnlyOwner() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        // Try to recover as non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        auction.recover(castHash, recoveryAddress);
    }

    function test_Recover_RevertsIfAuctionDoesNotExist() public {
        bytes32 castHash = keccak256("nonexistent");

        vm.prank(owner);
        vm.expectRevert(IAuction.AuctionNotCancellable.selector);
        auction.recover(castHash, recoveryAddress);
    }

    function test_Recover_RevertsIfAuctionSettled() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        // Warp past auction end and settle
        vm.warp(block.timestamp + 2 days);
        auction.settle(castHash);

        // Try to recover settled auction
        vm.prank(owner);
        vm.expectRevert(IAuction.AuctionNotCancellable.selector);
        auction.recover(castHash, recoveryAddress);
    }

    function test_Recover_RevertsIfAuctionCancelled() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        // Cancel auction
        bytes32 nonce = keccak256("nonce");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCancellation(castHash, nonce, deadline, authorizerPk);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        auction.cancel(castHash, auth);

        // Try to recover cancelled auction
        vm.prank(owner);
        vm.expectRevert(IAuction.AuctionNotCancellable.selector);
        auction.recover(castHash, recoveryAddress);
    }

    function test_Recover_ActiveAuction() public {
        bytes32 castHash = keccak256("test");
        uint256 bidAmount = 100e6; // 100 USDC
        _createActiveAuctionWithAmount(castHash, bidAmount);

        uint256 recoveryBalanceBefore = usdc.balanceOf(recoveryAddress);

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit AuctionRecovered(castHash, recoveryAddress, bidAmount);

        // Recover as owner
        vm.prank(owner);
        auction.recover(castHash, recoveryAddress);

        // Check refund sent to recovery address
        assertEq(usdc.balanceOf(recoveryAddress), recoveryBalanceBefore + bidAmount);
        assertEq(usdc.balanceOf(address(auction)), 0);

        // Check state is Recovered
        assertEq(uint8(auction.auctionState(castHash)), uint8(IAuction.AuctionState.Recovered));
    }

    function test_Recover_EndedAuction() public {
        bytes32 castHash = keccak256("test");
        uint256 bidAmount = 200e6; // 200 USDC
        _createActiveAuctionWithAmount(castHash, bidAmount);

        // Warp past auction end
        vm.warp(block.timestamp + 2 days);

        uint256 recoveryBalanceBefore = usdc.balanceOf(recoveryAddress);

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit AuctionRecovered(castHash, recoveryAddress, bidAmount);

        // Recover as owner
        vm.prank(owner);
        auction.recover(castHash, recoveryAddress);

        // Check refund sent to recovery address (not original bidder)
        assertEq(usdc.balanceOf(recoveryAddress), recoveryBalanceBefore + bidAmount);
        assertEq(usdc.balanceOf(address(auction)), 0);
        assertEq(usdc.balanceOf(bidder), 10000e6 - bidAmount); // Original balance minus bid

        // Check state is Recovered
        assertEq(uint8(auction.auctionState(castHash)), uint8(IAuction.AuctionState.Recovered));
    }

    function test_Recover_AuctionWithBid() public {
        // Test normal recovery case
        bytes32 castHash = keccak256("test");
        uint256 bidAmount = 10e6; // 10 USDC
        _createActiveAuction(castHash);

        // Expect event with bid amount
        vm.expectEmit(true, true, false, true);
        emit AuctionRecovered(castHash, recoveryAddress, bidAmount);

        // Recover as owner
        vm.prank(owner);
        auction.recover(castHash, recoveryAddress);

        // Check state is Recovered
        assertEq(uint8(auction.auctionState(castHash)), uint8(IAuction.AuctionState.Recovered));
        // Check funds transferred
        assertEq(usdc.balanceOf(recoveryAddress), bidAmount);
    }

    function test_Recover_RevertsIfRecoveryAddressZero() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        vm.prank(owner);
        vm.expectRevert(IAuction.InvalidAddress.selector);
        auction.recover(castHash, address(0));
    }

    function test_Recover_PreventsDoubleRecovery() public {
        bytes32 castHash = keccak256("test");
        uint256 bidAmount = 50e6;
        _createActiveAuctionWithAmount(castHash, bidAmount);

        // First recovery
        vm.prank(owner);
        auction.recover(castHash, recoveryAddress);

        // Try to recover again
        vm.prank(owner);
        vm.expectRevert(IAuction.AuctionNotCancellable.selector);
        auction.recover(castHash, recoveryAddress);
    }

    function test_Recover_PreventsSettleAfterRecover() public {
        bytes32 castHash = keccak256("test");
        _createActiveAuction(castHash);

        // Warp to end
        vm.warp(block.timestamp + 2 days);

        // Recover
        vm.prank(owner);
        auction.recover(castHash, recoveryAddress);

        // Try to settle recovered auction
        vm.expectRevert(IAuction.AuctionNotEnded.selector);
        auction.settle(castHash);
    }

    function testFuzz_Recover_VariousAmounts(uint256 bidAmount) public {
        bidAmount = _bound(bidAmount, 1e6, 1000e6); // 1 to 1000 USDC

        bytes32 castHash = keccak256("test");
        _createActiveAuctionWithAmount(castHash, bidAmount);

        uint256 recoveryBalanceBefore = usdc.balanceOf(recoveryAddress);

        vm.prank(owner);
        auction.recover(castHash, recoveryAddress);

        assertEq(usdc.balanceOf(recoveryAddress), recoveryBalanceBefore + bidAmount);
        assertEq(uint8(auction.auctionState(castHash)), uint8(IAuction.AuctionState.Recovered));
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
        bytes32 startNonce = keccak256(abi.encodePacked("startNonce", castHash));
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
}
