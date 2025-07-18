// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "../../src/interfaces/IAuction.sol";
import {AuctionTestBase} from "./AuctionTestBase.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract AuctionRecoverTest is AuctionTestBase {
    event AuctionRecovered(bytes32 indexed castHash, address indexed refundTo, uint256 amount);

    address public recoveryAddress;

    function setUp() public override {
        super.setUp();
        recoveryAddress = makeAddr("recoveryAddress");

        // Fund the bidder with USDC (matching the original setup)
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
        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
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
        assertEq(usdc.balanceOf(bidder), 10000e6); // Bidder still has their original balance

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
}
