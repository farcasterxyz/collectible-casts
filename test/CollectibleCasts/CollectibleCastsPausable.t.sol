// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {CollectibleCasts} from "../../src/CollectibleCasts.sol";
import {ICollectibleCasts} from "../../src/interfaces/ICollectibleCasts.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract CollectibleCastsPausableTest is TestSuiteSetup {
    CollectibleCasts public token;
    address public minter = makeAddr("minter");
    address public recipient = makeAddr("recipient");
    address public creator = makeAddr("creator");
    uint96 public creatorFid = 12345;

    function setUp() public override {
        super.setUp();
        token = new CollectibleCasts(address(this), "https://example.com/");
        
        // Allow minter
        token.allowMinter(minter);
    }

    function test_Pause_OnlyOwner() public {
        address notOwner = makeAddr("notOwner");
        
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.pause();
    }

    function test_Pause_Success() public {
        assertFalse(token.paused());
        
        vm.prank(token.owner());
        token.pause();
        
        assertTrue(token.paused());
    }

    function test_Unpause_OnlyOwner() public {
        // First pause the contract
        vm.prank(token.owner());
        token.pause();
        
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.unpause();
    }

    function test_Unpause_Success() public {
        // First pause the contract
        vm.prank(token.owner());
        token.pause();
        assertTrue(token.paused());
        
        vm.prank(token.owner());
        token.unpause();
        
        assertFalse(token.paused());
    }

    function test_Mint_RevertsWhenPaused() public {
        bytes32 castHash = keccak256("test");
        
        // Pause the contract
        vm.prank(token.owner());
        token.pause();
        
        // Try to mint
        vm.prank(minter);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.mint(recipient, castHash, creatorFid, creator);
    }

    function test_MintWithUri_RevertsWhenPaused() public {
        bytes32 castHash = keccak256("test");
        string memory tokenUri = "https://example.com/token";
        
        // Pause the contract
        vm.prank(token.owner());
        token.pause();
        
        // Try to mint with URI
        vm.prank(minter);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.mint(recipient, castHash, creatorFid, creator, tokenUri);
    }

    function test_Mint_SucceedsWhenUnpaused() public {
        bytes32 castHash = keccak256("test");
        
        // Pause and unpause the contract
        vm.prank(token.owner());
        token.pause();
        vm.prank(token.owner());
        token.unpause();
        
        // Should be able to mint
        vm.prank(minter);
        token.mint(recipient, castHash, creatorFid, creator);
        
        assertTrue(token.isMinted(castHash));
    }

    function test_TransferFrom_SucceedsWhenPaused() public {
        bytes32 castHash = keccak256("test");
        uint256 tokenId = uint256(castHash);
        address recipient2 = makeAddr("recipient2");
        
        // Mint token first
        vm.prank(minter);
        token.mint(recipient, castHash, creatorFid, creator);
        
        // Pause the contract
        vm.prank(token.owner());
        token.pause();
        
        // Transfer should still work
        vm.prank(recipient);
        token.transferFrom(recipient, recipient2, tokenId);
        
        assertEq(token.ownerOf(tokenId), recipient2);
    }

    function test_SafeTransferFrom_SucceedsWhenPaused() public {
        bytes32 castHash = keccak256("test");
        uint256 tokenId = uint256(castHash);
        address recipient2 = makeAddr("recipient2");
        
        // Mint token first
        vm.prank(minter);
        token.mint(recipient, castHash, creatorFid, creator);
        
        // Pause the contract
        vm.prank(token.owner());
        token.pause();
        
        // Safe transfer should still work
        vm.prank(recipient);
        token.safeTransferFrom(recipient, recipient2, tokenId);
        
        assertEq(token.ownerOf(tokenId), recipient2);
    }

    function testFuzz_Pause_EmitsEvent(address owner) public {
        vm.assume(owner != address(0));
        CollectibleCasts newToken = new CollectibleCasts(owner, "https://example.com/");
        
        vm.expectEmit(true, false, false, true);
        emit Paused(owner);
        
        vm.prank(owner);
        newToken.pause();
    }

    function testFuzz_Unpause_EmitsEvent(address owner) public {
        vm.assume(owner != address(0));
        CollectibleCasts newToken = new CollectibleCasts(owner, "https://example.com/");
        
        // First pause
        vm.prank(owner);
        newToken.pause();
        
        vm.expectEmit(true, false, false, true);
        emit Unpaused(owner);
        
        vm.prank(owner);
        newToken.unpause();
    }

    // Events from Pausable
    event Paused(address account);
    event Unpaused(address account);
}