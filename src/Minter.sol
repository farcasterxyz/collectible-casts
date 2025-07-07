// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IMinter} from "./interfaces/IMinter.sol";
import {ICollectibleCast} from "./interfaces/ICollectibleCast.sol";

contract Minter is IMinter {
    address public immutable token;

    constructor(address _token) {
        if (_token == address(0)) revert InvalidToken();
        token = _token;
    }

    function mint(address to, bytes32 castHash, uint256 fid, address creator) external {
        ICollectibleCast(token).mint(to, castHash, fid, creator);
    }
}