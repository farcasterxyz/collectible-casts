// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TestConstants} from "./TestConstants.sol";

contract TestConstantsTest is Test {
    function test_Constants_Exist() public pure {
        // Test that we can access USDC address
        address usdc = TestConstants.USDC;
        assertEq(usdc, 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
        
        // Test that we have test addresses
        address alice = TestConstants.ALICE;
        address bob = TestConstants.BOB;
        address treasury = TestConstants.TREASURY;
        
        assertTrue(alice != address(0));
        assertTrue(bob != address(0));
        assertTrue(treasury != address(0));
        assertTrue(alice != bob);
        assertTrue(alice != treasury);
        assertTrue(bob != treasury);
    }
}