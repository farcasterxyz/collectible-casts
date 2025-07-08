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
        uint256 extension;
        uint256 extensionThreshold;
    }

    event AuthorizerAllowed(address indexed authorizer);
    event AuthorizerDenied(address indexed authorizer);
    event TreasurySet(address indexed oldTreasury, address indexed newTreasury);

    address public immutable collectibleCast;
    address public immutable minter;
    address public immutable usdc;
    address public treasury;

    AuctionParams private _defaultParams;
    mapping(address => bool) public authorizers;

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
            extension: 15 minutes,
            extensionThreshold: 15 minutes
        });
    }

    function setDefaultParams(AuctionParams memory params) external onlyOwner {
        _defaultParams = params;
    }

    function defaultParams() external view returns (AuctionParams memory) {
        return _defaultParams;
    }

    function allowAuthorizer(address authorizer) external onlyOwner {
        if (authorizer == address(0)) revert InvalidAddress();
        authorizers[authorizer] = true;
        emit AuthorizerAllowed(authorizer);
    }

    function denyAuthorizer(address authorizer) external onlyOwner {
        authorizers[authorizer] = false;
        emit AuthorizerDenied(authorizer);
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert InvalidAddress();
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasurySet(oldTreasury, _treasury);
    }
}
