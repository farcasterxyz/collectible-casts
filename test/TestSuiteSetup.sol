// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

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

/// @notice Mock ERC1155 receiver that accepts tokens
contract MockERC1155Receiver is IERC1155Receiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

/// @notice Mock non-ERC1155 receiver contract for testing failed transfers
contract MockNonERC1155Receiver {
// Contract that doesn't implement ERC1155Receiver
// This simulates a contract that cannot receive ERC1155 tokens
}
