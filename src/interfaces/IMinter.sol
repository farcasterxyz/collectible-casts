// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IMinter {
    // Custom errors
    error InvalidToken();
    error Unauthorized();

    // Events
    event Allow(address indexed account);
    event Deny(address indexed account);

    // Functions
    function mint(address to, bytes32 castHash, uint256 fid, address creator) external;
    function allow(address account) external;
    function deny(address account) external;
    function allowed(address account) external view returns (bool);
}
