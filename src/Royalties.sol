// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IRoyalties} from "./interfaces/IRoyalties.sol";

contract Royalties is IRoyalties {
    uint256 public constant BPS_DENOMINATOR = 10000; // 100% = 10000 basis points
    uint256 public constant ROYALTY_BPS = 500; // 5%

    function royaltyInfo(uint256, uint256 salePrice, address creator)
        external
        pure
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = creator;
        royaltyAmount = (salePrice * ROYALTY_BPS) / BPS_DENOMINATOR;
    }
}
