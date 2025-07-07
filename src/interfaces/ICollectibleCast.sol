// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface ICollectibleCast {
    function mint(address to, bytes32 castHash, uint256 fid) external;
}