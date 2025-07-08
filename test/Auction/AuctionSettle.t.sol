// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {Minter} from "../../src/Minter.sol";
import {CollectibleCast} from "../../src/CollectibleCast.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";

contract AuctionSettleTest is Test, AuctionTestHelper {
    Auction public auction;
    MockUSDC public usdc;
    Minter public minter;
    CollectibleCast public collectibleCast;

    address public constant TREASURY = address(0x4);

    address public authorizer;
    uint256 public authorizerKey;

    bytes32 public constant TEST_CAST_HASH = keccak256("test-cast");
    address public constant CREATOR = address(0x789);
    uint256 public constant CREATOR_FID = 67890;

    function setUp() public {
        usdc = new MockUSDC();
        
        // Deploy real contracts
        address owner = address(this);
        minter = new Minter(owner);
        collectibleCast = new CollectibleCast(
            owner,
            address(minter),
            address(0), // metadata - not needed for auction tests
            address(0), // transferValidator - not needed
            address(0)  // royalties - not needed
        );
        
        // Configure real contracts
        minter.setToken(address(collectibleCast));
        auction = new Auction(address(minter), address(usdc), TREASURY, address(this));
        minter.allow(address(auction));

        (authorizer, authorizerKey) = makeAddrAndKey("authorizer");
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
    }

    function testFuzz_Settle_Success(address bidder, uint256 bidderFid, uint256 amount) public {
        // Bound inputs
        vm.assume(bidder != address(0));
        vm.assume(bidder != CREATOR); // Bidder must be different from creator
        vm.assume(bidder.code.length == 0); // Must be EOA to receive ERC-1155 tokens safely
        bidderFid = _bound(bidderFid, 1, type(uint256).max);
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
        assertTrue(collectibleCast.exists(tokenId));
        assertEq(collectibleCast.balanceOf(bidder, tokenId), 1);
        assertEq(collectibleCast.tokenFid(tokenId), CREATOR_FID);
        assertEq(collectibleCast.tokenCreator(tokenId), CREATOR);

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
