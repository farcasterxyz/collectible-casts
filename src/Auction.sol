// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "./interfaces/IAuction.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract Auction is IAuction, Ownable2Step {
    error InvalidAddress();

    struct AuctionParams {
        uint256 minBid;
        uint256 minBidIncrement; // in basis points (10000 = 100%)
        uint256 duration;
        uint256 antiSnipeExtension;
        uint256 antiSnipeThreshold;
    }

    address public immutable collectibleCast;
    address public immutable minter;
    address public immutable usdc;
    address public immutable treasury;

    AuctionParams private _defaultParams;

    constructor(address _collectibleCast, address _minter, address _usdc, address _treasury) Ownable(msg.sender) {
        if (_collectibleCast == address(0)) revert InvalidAddress();
        if (_minter == address(0)) revert InvalidAddress();
        if (_usdc == address(0)) revert InvalidAddress();
        if (_treasury == address(0)) revert InvalidAddress();

        collectibleCast = _collectibleCast;
        minter = _minter;
        usdc = _usdc;
        treasury = _treasury;

        // Set default parameters
        _defaultParams = AuctionParams({
            minBid: 1e6, // 1 USDC (6 decimals)
            minBidIncrement: 1000, // 10% in basis points
            duration: 24 hours,
            antiSnipeExtension: 15 minutes,
            antiSnipeThreshold: 15 minutes
        });
    }

    function setDefaultParams(AuctionParams memory params) external onlyOwner {
        _defaultParams = params;
    }

    function defaultParams() external view returns (AuctionParams memory) {
        return _defaultParams;
    }
}
