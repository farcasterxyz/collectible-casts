// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "../../src/Auction.sol";
import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";
import {IMinter} from "../../src/interfaces/IMinter.sol";

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
}
