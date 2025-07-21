// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IMetadata} from "./IMetadata.sol";

/**
 * @title ICollectibleCasts
 * @notice Interface for minting and managing Farcaster collectible cast NFTs
 */
interface ICollectibleCasts {
    error Unauthorized(); // Caller is unauthorized for this operation
    error AlreadyMinted(); // Token with this cast hash already exists
    error InvalidFid(); // Farcaster ID is zero or invalid
    error InvalidInput(); // Input parameters are malformed or invalid

    /**
     * @notice Emitted when a cast NFT is minted
     * @param to Recipient address
     * @param tokenId Token ID (uint256 representation of cast hash)
     * @param fid Creator's Farcaster ID
     * @param castHash Unique Farcaster cast identifier
     */
    event Mint(address indexed to, uint256 indexed tokenId, uint256 indexed fid, bytes32 castHash);

    event BaseURISet(string baseURI); // Base metadata URI updated
    event MetadataUpdate(uint256 _tokenId); // Single token metadata updated (ERC-4906)
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId); // Multiple token metadata updated (ERC-4906)
    event ContractURIUpdated(); // Contract-level metadata URI updated
    event MinterAllowed(address indexed account); // Address granted minting permission
    event MinterDenied(address indexed account); // Address revoked minting permission
    event MetadataModuleUpdated(address indexed newModule); // Metadata module address updated

    /**
     * @notice Mints a cast NFT
     * @param to Recipient address
     * @param castHash Unique cast identifier
     * @param creatorFid Creator's Farcaster ID
     * @dev Token ID = uint256(castHash)
     */
    function mint(address to, bytes32 castHash, uint256 creatorFid) external;

    /**
     * @notice Sets base URI for token metadata
     * @param baseURI_ New base URI
     * @dev Owner only. Emits BatchMetadataUpdate.
     */
    function setBaseURI(string memory baseURI_) external;

    /**
     * @notice Sets contract metadata URI
     * @param contractURI_ New contract URI
     * @dev Owner only. For marketplace collection metadata.
     */
    function setContractURI(string memory contractURI_) external;

    /**
     * @notice Grants minting permission
     * @param account Address to allow
     * @dev Owner only
     */
    function allowMinter(address account) external;

    /**
     * @notice Revokes minting permission
     * @param account Address to deny
     * @dev Owner only
     */
    function denyMinter(address account) external;

    /**
     * @notice Checks minting permission
     * @param account Address to check
     * @return Has minting permission
     */
    function minters(address account) external view returns (bool);

    /**
     * @notice Gets cast creator's Farcaster ID
     * @param tokenId Token to query
     * @return Creator's FID
     */
    function tokenFid(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Gets token metadata URI
     * @param tokenId Token to query
     * @return Complete metadata URI
     * @dev Custom URI takes precedence over base URI + tokenId
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /**
     * @notice Gets contract metadata URI
     * @return Contract-level metadata URI
     */
    function contractURI() external view returns (string memory);

    /**
     * @notice Checks if token exists
     * @param tokenId Token to check
     * @return Token has been minted
     */
    function isMinted(uint256 tokenId) external view returns (bool);

    /**
     * @notice Checks if cast has been minted
     * @param castHash Cast identifier to check
     * @return Cast has been minted
     */
    function isMinted(bytes32 castHash) external view returns (bool);

    /**
     * @notice Sets the metadata module for delegating metadata functionality
     * @param module Address of the metadata module (can be address(0) to disable)
     * @dev Owner only. Emits MetadataModuleUpdated, ContractURIUpdated, and BatchMetadataUpdate.
     */
    function setMetadataModule(address module) external;

    /**
     * @notice Gets the current metadata module address
     * @return The address of the metadata module (addess(0) if not set)
     */
    function metadata() external view returns (IMetadata);
}
