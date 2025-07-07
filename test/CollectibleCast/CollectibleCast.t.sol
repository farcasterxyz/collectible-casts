// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CollectibleCast} from "../../src/CollectibleCast.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract CollectibleCastTest is Test {
    CollectibleCast public token;
    
    function setUp() public {
        token = new CollectibleCast();
    }
    
    function test_Constructor_SetsOwner() public {
        address owner = makeAddr("owner");
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
}