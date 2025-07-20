// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IMetadata
 * @notice NFT metadata interface
 */
interface IMetadata {
    /**
     * @notice Returns the contract-level metadata URI
     * @return The URI containing contract metadata in JSON format
     */
    function contractURI() external view returns (string memory);

    /**
     * @notice Returns the metadata URI for a specific token
     * @param tokenId The ID of the token to query
     * @return The URI containing token metadata in JSON format
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}
