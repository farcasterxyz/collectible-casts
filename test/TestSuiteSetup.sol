// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

/// @title TestSuiteSetup
/// @notice Base test contract providing common test utilities and constants
abstract contract TestSuiteSetup is Test {
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint256 public constant ROYALTY_BPS = 500;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public alice;
    address public bob;
    address public charlie;

    function setUp() public virtual {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
    }
}
