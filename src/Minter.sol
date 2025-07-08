// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {ICollectibleCast} from "./interfaces/ICollectibleCast.sol";

contract Minter is IMinter, Ownable2Step {
    address public token;

    // Mapping to track allowed addresses
    mapping(address => bool) public allowed;

    constructor(address _owner) Ownable(_owner) {}

    modifier onlyAllowed() {
        if (!allowed[msg.sender]) revert Unauthorized();
        _;
    }

    // External/public state-changing functions
    function mint(address to, bytes32 castHash, uint256 creatorFid, address creator) external onlyAllowed {
        ICollectibleCast(token).mint(to, castHash, creatorFid, creator);
    }

    // External permissioned functions
    function setToken(address _token) external onlyOwner {
        if (_token == address(0)) revert InvalidToken();
        if (token != address(0)) revert TokenAlreadySet();
        token = _token;
        emit TokenSet(_token);
    }

    function allow(address account) external onlyOwner {
        allowed[account] = true;
        emit Allow(account);
    }

    function deny(address account) external onlyOwner {
        allowed[account] = false;
        emit Deny(account);
    }
}
