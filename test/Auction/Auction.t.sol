// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";
import {IMinter} from "../../src/interfaces/IMinter.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract AuctionTest is Test {
    Auction public auction;

    address public constant COLLECTIBLE_CAST = address(0x1);
    address public constant MINTER = address(0x2);
    address public constant USDC = address(0x3);
    address public constant TREASURY = address(0x4);

    function setUp() public {
        auction = new Auction(COLLECTIBLE_CAST, MINTER, USDC, TREASURY);
    }

    function test_Constructor_SetsConfiguration() public view {
        assertEq(auction.collectibleCast(), COLLECTIBLE_CAST);
        assertEq(auction.minter(), MINTER);
        assertEq(auction.usdc(), USDC);
        assertEq(auction.treasury(), TREASURY);
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(auction.owner(), address(this));
    }

    function test_Constructor_RevertsIfCollectibleCastIsZero() public {
        vm.expectRevert(Auction.InvalidAddress.selector);
        new Auction(address(0), MINTER, USDC, TREASURY);
    }

    function test_Constructor_RevertsIfMinterIsZero() public {
        vm.expectRevert(Auction.InvalidAddress.selector);
        new Auction(COLLECTIBLE_CAST, address(0), USDC, TREASURY);
    }

    function test_Constructor_RevertsIfUSDCIsZero() public {
        vm.expectRevert(Auction.InvalidAddress.selector);
        new Auction(COLLECTIBLE_CAST, MINTER, address(0), TREASURY);
    }

    function test_Constructor_RevertsIfTreasuryIsZero() public {
        vm.expectRevert(Auction.InvalidAddress.selector);
        new Auction(COLLECTIBLE_CAST, MINTER, USDC, address(0));
    }

    function test_SetDefaultParams_StoresCorrectly() public {
        Auction.AuctionParams memory params = Auction.AuctionParams({
            minBid: 1e6, // 1 USDC (6 decimals)
            minBidIncrement: 1000, // 10% in basis points
            duration: 24 hours,
            extension: 15 minutes,
            extensionThreshold: 15 minutes
        });

        vm.prank(auction.owner());
        auction.setDefaultParams(params);

        Auction.AuctionParams memory storedParams = auction.defaultParams();
        assertEq(storedParams.minBid, 1e6);
        assertEq(storedParams.minBidIncrement, 1000);
        assertEq(storedParams.duration, 24 hours);
        assertEq(storedParams.extension, 15 minutes);
        assertEq(storedParams.extensionThreshold, 15 minutes);
    }

    function test_SetDefaultParams_OnlyOwner() public {
        Auction.AuctionParams memory params = Auction.AuctionParams({
            minBid: 1e6,
            minBidIncrement: 1000,
            duration: 24 hours,
            extension: 15 minutes,
            extensionThreshold: 15 minutes
        });

        address notOwner = address(0x123);
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        auction.setDefaultParams(params);
    }

    function test_Constructor_SetsDefaultParams() public view {
        Auction.AuctionParams memory params = auction.defaultParams();
        assertEq(params.minBid, 1e6); // 1 USDC
        assertEq(params.minBidIncrement, 1000); // 10%
        assertEq(params.duration, 24 hours);
        assertEq(params.extension, 15 minutes);
        assertEq(params.extensionThreshold, 15 minutes);
    }

    function test_AllowAuthorizer_OnlyOwner() public {
        address authorizer = address(0x456);
        address notOwner = address(0x123);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        auction.allowAuthorizer(authorizer);
    }

    function test_AllowAuthorizer_UpdatesAllowlist() public {
        address authorizer = address(0x456);

        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        assertTrue(auction.authorizers(authorizer));
    }

    function test_AllowAuthorizer_EmitsEvent() public {
        address authorizer = address(0x456);

        vm.expectEmit(true, false, false, false);
        emit AuthorizerAllowed(authorizer);

        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
    }

    function test_AllowAuthorizer_RevertsIfZeroAddress() public {
        vm.prank(auction.owner());
        vm.expectRevert(Auction.InvalidAddress.selector);
        auction.allowAuthorizer(address(0));
    }

    function test_DenyAuthorizer_OnlyOwner() public {
        address authorizer = address(0x456);
        address notOwner = address(0x123);

        // First allow the authorizer
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        // Try to deny as non-owner
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        auction.denyAuthorizer(authorizer);
    }

    function test_DenyAuthorizer_UpdatesAllowlist() public {
        address authorizer = address(0x456);

        // First allow the authorizer
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
        assertTrue(auction.authorizers(authorizer));

        // Then deny the authorizer
        vm.prank(auction.owner());
        auction.denyAuthorizer(authorizer);
        assertFalse(auction.authorizers(authorizer));
    }

    function test_DenyAuthorizer_EmitsEvent() public {
        address authorizer = address(0x456);

        // First allow the authorizer
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        // Then deny with event check
        vm.expectEmit(true, false, false, false);
        emit AuthorizerDenied(authorizer);

        vm.prank(auction.owner());
        auction.denyAuthorizer(authorizer);
    }

    event AuthorizerAllowed(address indexed authorizer);
    event AuthorizerDenied(address indexed authorizer);

    function test_SetTreasury_OnlyOwner() public {
        address newTreasury = address(0x789);
        address notOwner = address(0x123);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        auction.setTreasury(newTreasury);
    }

    function test_SetTreasury_UpdatesTreasury() public {
        address newTreasury = address(0x789);

        vm.prank(auction.owner());
        auction.setTreasury(newTreasury);

        assertEq(auction.treasury(), newTreasury);
    }

    function test_SetTreasury_EmitsEvent() public {
        address newTreasury = address(0x789);

        vm.expectEmit(true, true, false, false);
        emit TreasurySet(TREASURY, newTreasury);

        vm.prank(auction.owner());
        auction.setTreasury(newTreasury);
    }

    function test_SetTreasury_RevertsIfZeroAddress() public {
        vm.prank(auction.owner());
        vm.expectRevert(Auction.InvalidAddress.selector);
        auction.setTreasury(address(0));
    }

    event TreasurySet(address indexed oldTreasury, address indexed newTreasury);

    // Fuzz tests
    function testFuzz_SetDefaultParams_StoresCorrectly(
        uint256 minBid,
        uint256 minBidIncrement,
        uint256 duration,
        uint256 extension,
        uint256 extensionThreshold
    ) public {
        // Bound inputs to reasonable ranges
        minBid = _bound(minBid, 0, type(uint256).max);
        minBidIncrement = _bound(minBidIncrement, 0, 10000); // 0-100%
        duration = _bound(duration, 0, 365 days);
        extension = _bound(extension, 0, 24 hours);
        extensionThreshold = _bound(extensionThreshold, 0, 24 hours);

        Auction.AuctionParams memory params = Auction.AuctionParams({
            minBid: minBid,
            minBidIncrement: minBidIncrement,
            duration: duration,
            extension: extension,
            extensionThreshold: extensionThreshold
        });

        vm.prank(auction.owner());
        auction.setDefaultParams(params);

        Auction.AuctionParams memory storedParams = auction.defaultParams();
        assertEq(storedParams.minBid, minBid);
        assertEq(storedParams.minBidIncrement, minBidIncrement);
        assertEq(storedParams.duration, duration);
        assertEq(storedParams.extension, extension);
        assertEq(storedParams.extensionThreshold, extensionThreshold);
    }

    function testFuzz_AllowAuthorizer_UpdatesAllowlist(address authorizer) public {
        vm.assume(authorizer != address(0));

        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);

        assertTrue(auction.authorizers(authorizer));
    }

    function testFuzz_DenyAuthorizer_UpdatesAllowlist(address authorizer) public {
        vm.assume(authorizer != address(0));

        // First allow the authorizer
        vm.prank(auction.owner());
        auction.allowAuthorizer(authorizer);
        assertTrue(auction.authorizers(authorizer));

        // Then deny the authorizer
        vm.prank(auction.owner());
        auction.denyAuthorizer(authorizer);
        assertFalse(auction.authorizers(authorizer));
    }

    function testFuzz_SetTreasury_UpdatesTreasury(address newTreasury) public {
        vm.assume(newTreasury != address(0));

        vm.prank(auction.owner());
        auction.setTreasury(newTreasury);

        assertEq(auction.treasury(), newTreasury);
    }

    // Edge case tests
    function test_SetDefaultParams_ZeroValues() public {
        Auction.AuctionParams memory params = Auction.AuctionParams({
            minBid: 0,
            minBidIncrement: 0,
            duration: 0,
            extension: 0,
            extensionThreshold: 0
        });

        vm.prank(auction.owner());
        auction.setDefaultParams(params);

        Auction.AuctionParams memory storedParams = auction.defaultParams();
        assertEq(storedParams.minBid, 0);
        assertEq(storedParams.minBidIncrement, 0);
        assertEq(storedParams.duration, 0);
        assertEq(storedParams.extension, 0);
        assertEq(storedParams.extensionThreshold, 0);
    }

    function test_SetDefaultParams_MaxValues() public {
        Auction.AuctionParams memory params = Auction.AuctionParams({
            minBid: type(uint256).max,
            minBidIncrement: 10000, // 100%
            duration: type(uint256).max,
            extension: type(uint256).max,
            extensionThreshold: type(uint256).max
        });

        vm.prank(auction.owner());
        auction.setDefaultParams(params);

        Auction.AuctionParams memory storedParams = auction.defaultParams();
        assertEq(storedParams.minBid, type(uint256).max);
        assertEq(storedParams.minBidIncrement, 10000);
        assertEq(storedParams.duration, type(uint256).max);
        assertEq(storedParams.extension, type(uint256).max);
        assertEq(storedParams.extensionThreshold, type(uint256).max);
    }

    // Test denying an authorizer that was never allowed
    function test_DenyAuthorizer_NotPreviouslyAllowed() public {
        address authorizer = address(0x456);

        // Verify not allowed initially
        assertFalse(auction.authorizers(authorizer));

        // Deny without allowing first
        vm.expectEmit(true, false, false, false);
        emit AuthorizerDenied(authorizer);

        vm.prank(auction.owner());
        auction.denyAuthorizer(authorizer);

        // Still false
        assertFalse(auction.authorizers(authorizer));
    }

    // Test Ownable2Step functionality
    function test_TransferOwnership_TwoStep() public {
        address newOwner = address(0x999);

        // Start transfer
        vm.prank(auction.owner());
        auction.transferOwnership(newOwner);

        // Ownership not transferred yet
        assertEq(auction.owner(), address(this));
        assertEq(auction.pendingOwner(), newOwner);

        // Accept ownership
        vm.prank(newOwner);
        auction.acceptOwnership();

        // Now ownership is transferred
        assertEq(auction.owner(), newOwner);
        assertEq(auction.pendingOwner(), address(0));
    }

    function test_AcceptOwnership_RevertsIfNotPendingOwner() public {
        address notPendingOwner = address(0x999);

        vm.prank(notPendingOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notPendingOwner));
        auction.acceptOwnership();
    }
}
