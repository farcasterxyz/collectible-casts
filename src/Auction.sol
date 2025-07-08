// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "./interfaces/IAuction.sol";

contract Auction is IAuction {
    error InvalidAddress();

    address public immutable collectibleCast;
    address public immutable minter;
    address public immutable usdc;
    address public immutable treasury;

    constructor(address _collectibleCast, address _minter, address _usdc, address _treasury) {
        if (_collectibleCast == address(0)) revert InvalidAddress();
        if (_minter == address(0)) revert InvalidAddress();
        if (_usdc == address(0)) revert InvalidAddress();
        if (_treasury == address(0)) revert InvalidAddress();

        collectibleCast = _collectibleCast;
        minter = _minter;
        usdc = _usdc;
        treasury = _treasury;
    }
}
