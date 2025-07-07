// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IRoyalties {
    function royaltyInfo(uint256 tokenId, uint256 salePrice, address creator) 
        external 
        view 
        returns (address receiver, uint256 royaltyAmount);
}