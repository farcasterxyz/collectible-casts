// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

contract MockNonERC721Receiver {
// This contract does not implement IERC721Receiver
// It will cause transfers to fail when using safeTransferFrom
}
