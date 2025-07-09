// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {Minter} from "../../src/Minter.sol";
import {IMinter} from "../../src/interfaces/IMinter.sol";
import {CollectibleCast} from "../../src/CollectibleCast.sol";
import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MinterTest is TestSuiteSetup {
    Minter public minter;
    CollectibleCast public token;

    function setUp() public override {
        super.setUp();
        token = new CollectibleCast(
            address(this),
            address(0),
            address(0),
            address(0),
            address(0)
        );
        minter = new Minter(address(this));
        minter.setToken(address(token));
    }

    function test_SetToken_SetsTokenAddress() public view {
        assertEq(minter.token(), address(token));
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(minter.owner(), address(this));
    }

    function test_SetToken_RevertsWithZeroAddress() public {
        Minter newMinter = new Minter(address(this));
        vm.expectRevert(IMinter.InvalidToken.selector);
        newMinter.setToken(address(0));
    }

    function test_SetToken_RevertsWhenAlreadySet() public {
        Minter newMinter = new Minter(address(this));
        
        // Set token once
        newMinter.setToken(address(token));
        
        // Try to set again - should fail
        vm.expectRevert(IMinter.TokenAlreadySet.selector);
        newMinter.setToken(makeAddr("anotherToken"));
    }

    function testFuzz_Mint_MintsTokenToRecipient(address recipient, bytes32 castHash, uint256 fid, address creator)
        public
    {
        // Setup
        vm.assume(recipient != address(0));
        vm.assume(fid != 0); // FID must be non-zero
        vm.assume(creator != address(0));
        // Ensure recipient can receive ERC1155 tokens (EOA or valid receiver)
        vm.assume(recipient.code.length == 0);

        // Set the minter as the minter on the token
        token.setModule("minter", address(minter));

        // Allow this test contract to mint
        minter.allow(address(this));

        // Mint
        minter.mint(recipient, castHash, fid, creator);

        // Verify
        uint256 tokenId = uint256(castHash);
        assertEq(token.balanceOf(recipient, tokenId), 1);
        assertEq(token.tokenFid(uint256(castHash)), fid);
        assertEq(token.tokenCreator(tokenId), creator);
    }

    function testFuzz_Mint_RevertsWhenCallerNotAllowed(address recipient, bytes32 castHash, uint256 fid, address creator, address unauthorizedCaller) public {
        // Setup
        vm.assume(recipient != address(0));
        vm.assume(fid != 0);
        vm.assume(creator != address(0));
        vm.assume(!minter.allowed(unauthorizedCaller)); // Ensure caller is not allowed

        // Set the minter as the minter on the token
        token.setModule("minter", address(minter));

        // Try to mint from unauthorized address - should fail
        vm.prank(unauthorizedCaller);
        vm.expectRevert(IMinter.Unauthorized.selector);
        minter.mint(recipient, castHash, fid, creator);
    }

    function testFuzz_Mint_RevertsOnDoubleMint(address recipient, bytes32 castHash, uint256 fid, address creator) public {
        // Setup
        vm.assume(recipient != address(0));
        vm.assume(fid != 0);
        vm.assume(creator != address(0));
        vm.assume(recipient.code.length == 0); // EOA for safe minting

        // Set the minter as the minter on the token
        token.setModule("minter", address(minter));

        // Allow this test contract to mint
        minter.allow(address(this));

        // First mint should succeed
        minter.mint(recipient, castHash, fid, creator);

        // Second mint should fail
        vm.expectRevert(ICollectibleCast.AlreadyMinted.selector);
        minter.mint(recipient, castHash, fid, creator);
    }

    function testFuzz_Allow_SetsAllowedStatus(address account) public {
        // Expect event
        vm.expectEmit(true, false, false, true);
        emit IMinter.Allow(account);

        // Allow should set allowed to true
        minter.allow(account);
        assertTrue(minter.allowed(account));
    }

    function testFuzz_Deny_RemovesAllowedStatus(address account) public {
        // First allow
        minter.allow(account);
        assertTrue(minter.allowed(account));

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit IMinter.Deny(account);

        // Then deny
        minter.deny(account);
        assertFalse(minter.allowed(account));
    }

    function testFuzz_Allow_OnlyOwner(address notOwner, address toAllow) public {
        vm.assume(notOwner != minter.owner());
        vm.assume(notOwner != address(0));

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        minter.allow(toAllow);
    }

    function testFuzz_Deny_OnlyOwner(address notOwner, address toDeny) public {
        vm.assume(notOwner != minter.owner());
        vm.assume(notOwner != address(0));

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        minter.deny(toDeny);
    }
}
