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
        (address bob,) = makeAddrAndKey("bob");
        assertTrue(alice1 != bob);
    }

    function testFuzz_MakeAddr_GeneratesDeterministicAddresses(string memory name) public {
        // Test that makeAddr is deterministic for any string
        address addr1 = makeAddr(name);
        address addr2 = makeAddr(name);

        assertEq(addr1, addr2);
        assertTrue(addr1 != address(0));
    }

    function testFuzz_MakeAddrAndKey_GeneratesDeterministicAddresses(string memory name) public {
        // Test that makeAddrAndKey is deterministic for any string
        (address addr1, uint256 pk1) = makeAddrAndKey(name);
        (address addr2, uint256 pk2) = makeAddrAndKey(name);

        assertEq(addr1, addr2);
        assertEq(pk1, pk2);
        assertTrue(addr1 != address(0));
        assertTrue(pk1 != 0);
    }

    function testFuzz_MakeAddr_GeneratesUniqueAddresses(string memory name1, string memory name2) public {
        vm.assume(keccak256(bytes(name1)) != keccak256(bytes(name2)));

        address addr1 = makeAddr(name1);
        address addr2 = makeAddr(name2);

        assertTrue(addr1 != addr2);
    }
}
