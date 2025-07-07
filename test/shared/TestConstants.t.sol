// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TestConstants} from "./TestConstants.sol";

contract TestConstantsTest is Test {
    function test_Constants_Exist() public pure {
        // Test that we can access USDC address
        address usdc = TestConstants.USDC;
        assertEq(usdc, 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    }
    
    function test_MakeAddr_GeneratesDeterministicAddresses() public {
        // Test that makeAddr generates deterministic addresses
        address treasury1 = makeAddr("treasury");
        address treasury2 = makeAddr("treasury");
        
        assertEq(treasury1, treasury2);
        assertTrue(treasury1 != address(0));
    }
    
    function test_MakeAddrAndKey_GeneratesDeterministicAddresses() public {
        // Test that makeAddrAndKey generates deterministic addresses with keys
        (address alice1, uint256 pk1) = makeAddrAndKey("alice");
        (address alice2, uint256 pk2) = makeAddrAndKey("alice");
        
        assertEq(alice1, alice2);
        assertEq(pk1, pk2);
        
        // Test that different names generate different addresses
        (address bob, ) = makeAddrAndKey("bob");
        assertTrue(alice1 != bob);
    }
}