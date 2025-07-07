// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CollectibleCast} from "../../src/CollectibleCast.sol";

contract CollectibleCastTest is Test {
    CollectibleCast public token;
    
    function test_Constructor_SetsOwner() public {
        address owner = makeAddr("owner");
        vm.prank(owner);
        token = new CollectibleCast();
        
        assertEq(token.owner(), owner);
    }
}