// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {CollectibleCasts} from "../../src/CollectibleCasts.sol";
import {ICollectibleCasts} from "../../src/interfaces/ICollectibleCasts.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract CollectibleCastsPausableTest is TestSuiteSetup {
    CollectibleCasts public token;

    address public owner = makeAddr("owner");
    address public minter = makeAddr("minter");
    address public recipient = makeAddr("recipient");
    address public creator = makeAddr("creator");
    uint96 public creatorFid = 12345;

    function setUp() public override {
        super.setUp();
        token = new CollectibleCasts(owner, "https://example.com/");
        vm.prank(owner);
        token.allowMinter(minter);
    }

    function testFuzz_Pause_OnlyOwner(address notOwner) public {
        vm.assume(notOwner != owner);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.pause();
    }

    function test_Pause_Success() public {
        assertFalse(token.paused());

        vm.prank(owner);
        token.pause();

        assertTrue(token.paused());
    }

    function testFuzz_Unpause_OnlyOwner(address notOwner) public {
        vm.assume(notOwner != owner);

        vm.prank(owner);
        token.pause();

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.unpause();
    }

    function test_Unpause_Success() public {
        vm.prank(owner);
        token.pause();
        assertTrue(token.paused());

        vm.prank(owner);
        token.unpause();

        assertFalse(token.paused());
    }

    function test_Mint_RevertsWhenPaused() public {
        bytes32 castHash = keccak256("test");

        vm.prank(owner);
        token.pause();

        vm.prank(minter);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.mint(recipient, castHash, creatorFid);
    }

    function test_Mint_SucceedsWhenUnpaused() public {
        bytes32 castHash = keccak256("test");

        vm.prank(owner);
        token.pause();
        vm.prank(owner);
        token.unpause();

        vm.prank(minter);
        token.mint(recipient, castHash, creatorFid);

        assertTrue(token.isMinted(castHash));
    }

    function test_TransferFrom_SucceedsWhenPaused() public {
        bytes32 castHash = keccak256("test");
        uint256 tokenId = uint256(castHash);
        address recipient2 = makeAddr("recipient2");

        vm.prank(minter);
        token.mint(recipient, castHash, creatorFid);

        vm.prank(owner);
        token.pause();

        vm.prank(recipient);
        token.transferFrom(recipient, recipient2, tokenId);

        assertEq(token.ownerOf(tokenId), recipient2);
    }

    function test_SafeTransferFrom_SucceedsWhenPaused() public {
        bytes32 castHash = keccak256("test");
        uint256 tokenId = uint256(castHash);
        address recipient2 = makeAddr("recipient2");

        vm.prank(minter);
        token.mint(recipient, castHash, creatorFid);

        vm.prank(owner);
        token.pause();

        vm.prank(recipient);
        token.safeTransferFrom(recipient, recipient2, tokenId);

        assertEq(token.ownerOf(tokenId), recipient2);
    }

    function testFuzz_Pause_EmitsEvent(address contractOwner) public {
        vm.assume(contractOwner != address(0));
        CollectibleCasts newToken = new CollectibleCasts(contractOwner, "https://example.com/");

        vm.expectEmit(true, false, false, true);
        emit Paused(contractOwner);

        vm.prank(contractOwner);
        newToken.pause();
    }

    function testFuzz_Unpause_EmitsEvent(address contractOwner) public {
        vm.assume(contractOwner != address(0));
        CollectibleCasts newToken = new CollectibleCasts(contractOwner, "https://example.com/");

        vm.prank(contractOwner);
        newToken.pause();

        vm.expectEmit(true, false, false, true);
        emit Unpaused(contractOwner);

        vm.prank(contractOwner);
        newToken.unpause();
    }

    event Paused(address account);
    event Unpaused(address account);
}
