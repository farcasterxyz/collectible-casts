// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {CollectibleCasts} from "../../src/CollectibleCasts.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {AuctionTestHelper} from "./AuctionTestHelper.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

abstract contract AuctionTestBase is TestSuiteSetup, AuctionTestHelper {
    // ========== Core Contracts ==========
    Auction public auction;
    CollectibleCasts public collectibleCast;
    MockUSDC public usdc;

    // ========== Common Test Addresses ==========
    address public treasury;
    address public owner;
    address public authorizer;
    uint256 public authorizerPk;

    // Additional test addresses for common scenarios
    address public creator;
    uint256 public creatorPk;
    address public bidder;
    uint256 public bidderPk;
    address public bidder2;
    uint256 public bidder2Pk;

    // ========== Common Test Constants ==========
    bytes32 public constant TEST_CAST_HASH = keccak256("test-cast");
    address public DEFAULT_CREATOR;
    uint96 public constant DEFAULT_CREATOR_FID = 67890;
    uint96 public constant DEFAULT_BIDDER_FID = 12345;
    uint256 public constant DEFAULT_BID_AMOUNT = 100e6; // 100 USDC

    // Default auction parameters
    uint64 public constant DEFAULT_MIN_BID = 1e6; // 1 USDC
    uint16 public constant DEFAULT_MIN_BID_INCREMENT = 1000; // 10%
    uint32 public constant DEFAULT_DURATION = 24 hours;
    uint32 public constant DEFAULT_EXTENSION = 15 minutes;
    uint32 public constant DEFAULT_EXTENSION_THRESHOLD = 15 minutes;
    uint16 public constant DEFAULT_PROTOCOL_FEE = 1000; // 10%

    // ========== Setup ==========
    function setUp() public virtual override {
        super.setUp();
        _deployContracts();
        _setupRoles();
        _setupTestAccounts();
    }

    function _deployContracts() internal virtual {
        // Create core addresses
        treasury = makeAddr("treasury");
        owner = makeAddr("owner");
        (authorizer, authorizerPk) = makeAddrAndKey("authorizer");

        // Deploy contracts
        usdc = new MockUSDC();
        collectibleCast = new CollectibleCasts(owner, "https://example.com/");
        auction = new Auction(address(collectibleCast), address(usdc), treasury, owner);
    }

    function _setupRoles() internal virtual {
        // Allow auction to mint
        vm.prank(owner);
        collectibleCast.allowMinter(address(auction));

        // Allow authorizer
        vm.prank(owner);
        auction.allowAuthorizer(authorizer);
    }

    function _setupTestAccounts() internal virtual {
        // Create test accounts
        (creator, creatorPk) = makeAddrAndKey("creator");
        (bidder, bidderPk) = makeAddrAndKey("bidder");
        (bidder2, bidder2Pk) = makeAddrAndKey("bidder2");
        DEFAULT_CREATOR = creator;
    }

    // ========== USDC Helpers ==========
    function _fundAndApprove(address account, uint256 amount) internal {
        usdc.mint(account, amount);
        vm.prank(account);
        usdc.approve(address(auction), amount);
    }

    function _fundAndApproveMany(address[] memory accounts, uint256[] memory amounts) internal {
        require(accounts.length == amounts.length, "Array length mismatch");
        for (uint256 i = 0; i < accounts.length; i++) {
            _fundAndApprove(accounts[i], amounts[i]);
        }
    }

    // ========== Signature Helpers ==========
    function _signStartAuthorization(
        bytes32 castHash,
        address castCreator,
        uint96 castCreatorFid,
        address auctionBidder,
        uint96 auctionBidderFid,
        uint256 amount,
        IAuction.AuctionParams memory params,
        bytes32 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash = auction.hashStartAuthorization(
            castHash, castCreator, castCreatorFid, auctionBidder, auctionBidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function _signBidAuthorization(
        bytes32 castHash,
        address auctionBidder,
        uint96 auctionBidderFid,
        uint256 amount,
        bytes32 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash =
            auction.hashBidAuthorization(castHash, auctionBidder, auctionBidderFid, amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function _signCancelAuthorization(bytes32 castHash, bytes32 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = auction.hashCancelAuthorization(castHash, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        return abi.encodePacked(r, s, v);
    }

    // ========== Auction Creation Helpers ==========
    function _startAuction(address auctionBidder, uint96 auctionBidderFid, uint256 amount)
        internal
        returns (uint256 endTime)
    {
        return _startAuctionWithParams(
            TEST_CAST_HASH,
            DEFAULT_CREATOR,
            DEFAULT_CREATOR_FID,
            auctionBidder,
            auctionBidderFid,
            amount,
            _getDefaultAuctionParams()
        );
    }

    function _startAuctionWithParams(
        bytes32 castHash,
        address castCreator,
        uint96 castCreatorFid,
        address auctionBidder,
        uint96 auctionBidderFid,
        uint256 amount,
        IAuction.AuctionParams memory params
    ) internal returns (uint256 endTime) {
        bytes32 nonce =
            castHash == TEST_CAST_HASH ? keccak256("start-nonce") : keccak256(abi.encodePacked("start-nonce", castHash));
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(castHash, castCreator, castCreatorFid);
        IAuction.BidData memory bidData = createBidData(auctionBidderFid, amount);

        bytes memory signature = _signStartAuthorization(
            castHash, castCreator, castCreatorFid, auctionBidder, auctionBidderFid, amount, params, nonce, deadline
        );

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        _fundAndApprove(auctionBidder, amount);

        vm.prank(auctionBidder);
        auction.start(castData, bidData, params, auth);

        return block.timestamp + params.duration;
    }

    function _startDefaultAuction() internal returns (uint256 endTime) {
        return _startAuction(bidder, DEFAULT_BIDDER_FID, DEFAULT_BID_AMOUNT);
    }

    // ========== Bid Helpers ==========
    function _placeBid(bytes32 castHash, address auctionBidder, uint96 auctionBidderFid, uint256 amount) internal {
        bytes32 nonce = keccak256(abi.encodePacked("bid-nonce", auctionBidder, amount));
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory signature =
            _signBidAuthorization(castHash, auctionBidder, auctionBidderFid, amount, nonce, deadline);

        IAuction.BidData memory bidData = createBidData(auctionBidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        _fundAndApprove(auctionBidder, amount);

        vm.prank(auctionBidder);
        auction.bid(castHash, bidData, auth);
    }

    // ========== Cancel Helpers ==========
    function _cancelAuction(bytes32 castHash) internal {
        bytes32 nonce = keccak256(abi.encodePacked("cancel-nonce", castHash));
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory signature = _signCancelAuthorization(castHash, nonce, deadline);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        auction.cancel(castHash, auth);
    }

    // ========== State Helpers ==========
    function _getDefaultAuctionParams() internal pure returns (IAuction.AuctionParams memory) {
        return createAuctionParams(
            DEFAULT_MIN_BID,
            DEFAULT_MIN_BID_INCREMENT,
            DEFAULT_DURATION,
            DEFAULT_EXTENSION,
            DEFAULT_EXTENSION_THRESHOLD,
            DEFAULT_PROTOCOL_FEE
        );
    }

    function _fastForwardPastEnd(uint256 endTime) internal {
        vm.warp(endTime + 1);
    }

    function _fastForwardToExtensionWindow(uint256 endTime, uint32 extensionThreshold) internal {
        vm.warp(endTime - extensionThreshold + 1);
    }

    // ========== Assertion Helpers ==========
    function _assertAuctionState(bytes32 castHash, IAuction.AuctionState expectedState) internal view {
        assertEq(uint256(auction.auctionState(castHash)), uint256(expectedState));
    }

    function _assertAuctionData(bytes32 castHash, address expectedBidder, uint96 expectedBidderFid, uint256 expectedBid)
        internal
        view
    {
        (,, address highestBidder, uint96 highestBidderFid, uint256 highestBid,,,,,) = auction.auctions(castHash);

        assertEq(highestBidder, expectedBidder);
        assertEq(highestBidderFid, expectedBidderFid);
        assertEq(highestBid, expectedBid);
    }

    function _assertNFTOwnership(bytes32 castHash, address expectedOwner) internal view {
        uint256 tokenId = uint256(castHash);
        assertEq(collectibleCast.ownerOf(tokenId), expectedOwner);
    }

    function _assertTokenData(bytes32 castHash, uint96 expectedFid, address expectedCreator) internal view {
        uint256 tokenId = uint256(castHash);
        assertEq(collectibleCast.tokenFid(tokenId), expectedFid);
        // Creator parameter is no longer used after royalty removal
    }
}
