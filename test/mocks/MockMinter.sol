// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IMinter} from "../../src/interfaces/IMinter.sol";

contract MockMinter is IMinter {
    address public immutable token;
    mapping(address => bool) public allowed;

    // Track last mint call
    bool public mintCalled;
    address public lastMintTo;
    bytes32 public lastCastHash;
    uint256 public lastFid;
    address public lastCreator;

    constructor(address _token) {
        token = _token;
    }

    function mint(address to, bytes32 castHash, uint256 creatorFid, address creator) external {
        if (!allowed[msg.sender]) revert Unauthorized();

        mintCalled = true;
        lastMintTo = to;
        lastCastHash = castHash;
        lastFid = creatorFid;
        lastCreator = creator;

        // In real implementation, this would call token.mint()
    }

    function allow(address account) external {
        allowed[account] = true;
        emit Allow(account);
    }

    function deny(address account) external {
        allowed[account] = false;
        emit Deny(account);
    }
}
