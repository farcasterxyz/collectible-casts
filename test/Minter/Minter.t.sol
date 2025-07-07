// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Minter} from "../../src/Minter.sol";
import {IMinter} from "../../src/interfaces/IMinter.sol";
import {CollectibleCast} from "../../src/CollectibleCast.sol";
import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";

contract MinterTest is Test {
    Minter public minter;
    CollectibleCast public token;

    function setUp() public {
        token = new CollectibleCast();
        minter = new Minter(address(token));
    }

    function test_Constructor_SetsTokenAddress() public view {
        assertEq(minter.token(), address(token));
    }

    function test_Constructor_RevertsWithZeroAddress() public {
        vm.expectRevert(IMinter.InvalidToken.selector);
        new Minter(address(0));
    }

    function testFuzz_Mint_MintsTokenToRecipient(
        address recipient,
        bytes32 castHash,
        uint256 fid,
        address creator
    ) public {
        // Setup
        vm.assume(recipient != address(0));
        vm.assume(fid != 0); // FID must be non-zero
        vm.assume(creator != address(0));
        // Ensure recipient can receive ERC1155 tokens (EOA or valid receiver)
        vm.assume(recipient.code.length == 0);

        // Set the minter as the minter on the token
        token.setModule("minter", address(minter));

        // Mint
        minter.mint(recipient, castHash, fid, creator);

        // Verify
        uint256 tokenId = uint256(castHash);
        assertEq(token.balanceOf(recipient, tokenId), 1);
        assertEq(token.castHashToFid(castHash), fid);
        assertEq(token.tokenCreator(tokenId), creator);
    }

    function test_Mint_RevertsWhenNotAuthorized() public {
        // Setup
        address recipient = makeAddr("recipient");
        bytes32 castHash = keccak256("test cast");
        uint256 fid = 123;
        address creator = makeAddr("creator");

        // Don't set the minter as authorized - mint should fail
        vm.expectRevert(ICollectibleCast.Unauthorized.selector);
        minter.mint(recipient, castHash, fid, creator);
    }

    function test_Mint_RevertsOnDoubleMint() public {
        // Setup
        address recipient = makeAddr("recipient");
        bytes32 castHash = keccak256("test cast");
        uint256 fid = 123;
        address creator = makeAddr("creator");

        // Set the minter as the minter on the token
        token.setModule("minter", address(minter));

        // First mint should succeed
        minter.mint(recipient, castHash, fid, creator);

        // Second mint should fail
        vm.expectRevert(ICollectibleCast.AlreadyMinted.selector);
        minter.mint(recipient, castHash, fid, creator);
    }
}