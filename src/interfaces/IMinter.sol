// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IMinter {
    // Custom errors
    error InvalidToken();

    // Functions
    function mint(address to, bytes32 castHash, uint256 fid, address creator) external;
}
