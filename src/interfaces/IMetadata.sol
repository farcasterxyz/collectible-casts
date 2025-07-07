// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IMetadata {
    // Events
    event BaseURISet(string oldBaseURI, string newBaseURI);

    // Functions
    function uri(uint256 tokenId) external view returns (string memory);
    function contractURI() external view returns (string memory);
    function setBaseURI(string memory baseURI) external;
}
