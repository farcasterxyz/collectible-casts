// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

/// @title TestSuiteSetup
/// @notice Base test contract providing common test utilities and constants
abstract contract TestSuiteSetup is Test {
    // Constants
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint256 public constant ROYALTY_BPS = 500; // 5%

    // Test actors
    address public alice;
    address public bob;
    address public charlie;

    function setUp() public virtual {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
    }

    // Helper functions
    function _assumeClean(address addr) internal view {
        vm.assume(addr != address(0));
        vm.assume(addr.code.length == 0);
    }

    function _boundPk(uint256 pk) internal pure returns (uint256) {
        return _bound(pk, 1, type(uint256).max);
    }
}
