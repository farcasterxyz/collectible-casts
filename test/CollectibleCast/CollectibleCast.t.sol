// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CollectibleCast} from "../../src/CollectibleCast.sol";
import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CollectibleCastTest is Test {
    CollectibleCast public token;
    
    function setUp() public {
        token = new CollectibleCast();
    }
    
    function testFuzz_SetMinter_OnlyOwner(address newMinter, address notOwner) public {
        // Ensure notOwner is different from the actual owner
        vm.assume(notOwner != token.owner());
        vm.assume(notOwner != address(0));
        
        // Test that owner can set minter
        vm.prank(token.owner());
        token.setMinter(newMinter);
        assertEq(token.minter(), newMinter);
        
        // Test that non-owner cannot set minter
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.setMinter(makeAddr("anotherMinter"));
    }
    
    function test_Constructor_SetsOwner() public {
        address owner = makeAddr("owner");
        vm.prank(owner);
        CollectibleCast newToken = new CollectibleCast();
        
        assertEq(newToken.owner(), owner);
    }
    
    function testFuzz_Constructor_SetsOwner(address owner) public {
        // Skip zero address and this contract
        vm.assume(owner != address(0));
        vm.assume(owner != address(this));
        
        vm.prank(owner);
        CollectibleCast newToken = new CollectibleCast();
        
        assertEq(newToken.owner(), owner);
    }
    
    function test_SupportsERC1155Interface() public view {
        // ERC-1155 interface ID
        bytes4 erc1155InterfaceId = 0xd9b67a26;
        assertTrue(token.supportsInterface(erc1155InterfaceId));
        
        // ERC-165 interface ID (supportsInterface itself)
        bytes4 erc165InterfaceId = 0x01ffc9a7;
        assertTrue(token.supportsInterface(erc165InterfaceId));
    }
    
    function test_Mint_RevertsWhenNotMinter() public {
        address notMinter = makeAddr("notMinter");
        address recipient = makeAddr("recipient");
        bytes32 castHash = keccak256("cast1");
        uint256 fid = 1;
        
        vm.prank(notMinter);
        vm.expectRevert(ICollectibleCast.Unauthorized.selector);
        token.mint(recipient, castHash, fid);
    }
    
    function test_Mint_SucceedsFirstTime() public {
        // First, we need to set a minter
        address minterAddr = makeAddr("minter");
        address recipient = makeAddr("recipient");
        bytes32 castHash = keccak256("cast1");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 1;
        
        // Set minter (we'll need to add this function)
        token.setMinter(minterAddr);
        
        // Mint as the minter
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid);
        
        // Check that the recipient received the token
        assertEq(token.balanceOf(recipient, tokenId), 1);
    }
    
    function testFuzz_Mint_SucceedsFirstTime(address recipient, bytes32 castHash, uint256 fid) public {
        // Skip invalid addresses
        vm.assume(recipient != address(0));
        
        // Set up minter
        address minterAddr = makeAddr("minter");
        token.setMinter(minterAddr);
        
        uint256 tokenId = uint256(castHash);
        
        // Mint as the minter
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid);
        
        // Check that the recipient received the token
        assertEq(token.balanceOf(recipient, tokenId), 1);
        // Check that the FID was stored
        assertEq(token.castHashToFid(castHash), fid);
    }
}