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
            antiSnipeExtension: 15 minutes,
            antiSnipeThreshold: 15 minutes
        });

        vm.prank(auction.owner());
        auction.setDefaultParams(params);

        Auction.AuctionParams memory storedParams = auction.defaultParams();
        assertEq(storedParams.minBid, 1e6);
        assertEq(storedParams.minBidIncrement, 1000);
        assertEq(storedParams.duration, 24 hours);
        assertEq(storedParams.antiSnipeExtension, 15 minutes);
        assertEq(storedParams.antiSnipeThreshold, 15 minutes);
    }

    function test_SetDefaultParams_OnlyOwner() public {
        Auction.AuctionParams memory params = Auction.AuctionParams({
            minBid: 1e6,
            minBidIncrement: 1000,
            duration: 24 hours,
            antiSnipeExtension: 15 minutes,
            antiSnipeThreshold: 15 minutes
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
        assertEq(params.antiSnipeExtension, 15 minutes);
        assertEq(params.antiSnipeThreshold, 15 minutes);
    }

    function test_SetBackendSigner_OnlyOwner() public {
        address newSigner = address(0x456);
        address notOwner = address(0x123);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        auction.setBackendSigner(newSigner);
    }

    function test_SetBackendSigner_UpdatesSigner() public {
        address newSigner = address(0x456);

        vm.prank(auction.owner());
        auction.setBackendSigner(newSigner);

        assertEq(auction.backendSigner(), newSigner);
    }

    function test_SetBackendSigner_EmitsEvent() public {
        address newSigner = address(0x456);

        vm.expectEmit(true, true, false, false);
        emit BackendSignerSet(address(0), newSigner);

        vm.prank(auction.owner());
        auction.setBackendSigner(newSigner);
    }

    function test_SetBackendSigner_AllowsZeroAddress() public {
        vm.prank(auction.owner());
        auction.setBackendSigner(address(0));

        assertEq(auction.backendSigner(), address(0));
    }

    event BackendSignerSet(address indexed oldSigner, address indexed newSigner);
}
