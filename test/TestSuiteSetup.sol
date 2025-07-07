// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

abstract contract TestSuiteSetup is Test {
    function setUp() public virtual {
        // Base setup can be extended by inheriting contracts
    }
}