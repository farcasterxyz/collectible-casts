// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CollectibleCast} from "../../src/CollectibleCast.sol";
import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockERC1155Receiver, MockNonERC1155Receiver} from "./mocks/MockERC1155Receiver.sol";

contract CollectibleCastTest is Test {
    CollectibleCast public token;
    MockERC1155Receiver public validReceiver;
    MockNonERC1155Receiver public invalidReceiver;
    
    function setUp() public {
        token = new CollectibleCast();
        validReceiver = new MockERC1155Receiver();
        invalidReceiver = new MockNonERC1155Receiver();
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
    
    function test_Mint_ToValidContract() public {
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("cast2");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 2;
        
        token.setMinter(minterAddr);
        
        // Mint to a contract that implements ERC1155Receiver
        vm.prank(minterAddr);
        token.mint(address(validReceiver), castHash, fid);
        
        assertEq(token.balanceOf(address(validReceiver), tokenId), 1);
        assertEq(token.castHashToFid(castHash), fid);
    }
    
    function test_Mint_ToInvalidContract_Reverts() public {
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("cast3");
        uint256 fid = 3;
        
        token.setMinter(minterAddr);
        
        // Attempt to mint to a contract that doesn't implement ERC1155Receiver
        vm.prank(minterAddr);
        vm.expectRevert(); // ERC1155 will revert
        token.mint(address(invalidReceiver), castHash, fid);
    }
    
    function testFuzz_Mint_ToEOA(address recipient, bytes32 castHash, uint256 fid) public {
        // Test minting to EOAs only
        vm.assume(recipient != address(0));
        vm.assume(recipient.code.length == 0); // Only EOAs
        vm.assume(recipient != address(this)); // Not the test contract
        
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
    
    function testFuzz_Mint_MultipleUniqueCasts(bytes32[5] memory castHashes, uint256 baseFid) public {
        // Test minting multiple unique casts
        vm.assume(baseFid < type(uint256).max - 5); // Prevent overflow
        
        address minterAddr = makeAddr("minter");
        address recipient = makeAddr("recipient");
        token.setMinter(minterAddr);
        
        for (uint i = 0; i < castHashes.length; i++) {
            // Ensure unique cast hashes
            for (uint j = 0; j < i; j++) {
                vm.assume(castHashes[i] != castHashes[j]);
            }
            
            uint256 tokenId = uint256(castHashes[i]);
            uint256 fid = baseFid + i;
            
            vm.prank(minterAddr);
            token.mint(recipient, castHashes[i], fid);
            
            assertEq(token.balanceOf(recipient, tokenId), 1);
            assertEq(token.castHashToFid(castHashes[i]), fid);
        }
    }
}