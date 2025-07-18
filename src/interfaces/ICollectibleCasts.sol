// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title ICollectibleCasts
 * @notice Interface for minting and managing Farcaster collectible cast NFTs
 */
interface ICollectibleCasts {
    /**
     * @notice Token metadata storage
     * @param fid Farcaster ID of the cast creator
     * @param creator Creator's primary address at mint time (receives optional royalties)
     * @param uri Optional custom metadata URI
     */
    struct TokenData {
        uint96 fid;
        address creator;
        string uri;
    }

    error Unauthorized(); // Caller is unauthorized for this operation
    error AlreadyMinted(); // Token with this cast hash already exists
    error InvalidFid(); // Farcaster ID is zero or invalid
    error InvalidInput(); // Input parameters are malformed or invalid

    /**
     * @notice Emitted when a cast NFT is minted
     * @param to Recipient address
     * @param tokenId Token ID (uint256 representation of cast hash)
     * @param castHash Unique Farcaster cast identifier
     * @param fid Creator's Farcaster ID
     * @param creator Creator's primary address at mint time
     */
    event Mint(address indexed to, uint256 indexed tokenId, bytes32 indexed castHash, uint96 fid, address creator);

    event BaseURISet(string baseURI); // Base metadata URI updated
    event MetadataUpdate(uint256 _tokenId); // Single token metadata updated (ERC-4906)
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId); // Multiple token metadata updated (ERC-4906)
    event ContractURIUpdated(string contractURI); // Contract-level metadata URI updated
    event MinterAllowed(address indexed account); // Address granted minting permission
    event MinterDenied(address indexed account); // Address revoked minting permission

    /**
     * @notice Mints a cast NFT
     * @param to Recipient address
     * @param castHash Unique cast identifier
     * @param creatorFid Creator's Farcaster ID
     * @param creator Creator's primary address at mint time
     * @dev Token ID = uint256(castHash)
     */
    function mint(address to, bytes32 castHash, uint96 creatorFid, address creator) external;

    /**
     * @notice Mints a cast NFT with custom metadata
     * @param to Recipient address
     * @param castHash Unique cast identifier
     * @param creatorFid Creator's Farcaster ID
     * @param creator Creator's primary address at mint time
     * @param tokenUri Custom metadata URI
     * @dev Custom URI takes precedence over base URI
     */
    function mint(address to, bytes32 castHash, uint96 creatorFid, address creator, string memory tokenUri) external;

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
     * @notice Batch updates token URIs
     * @param tokenIds Token IDs to update
     * @param uris Corresponding new URIs
     * @dev Owner only. Arrays must match length.
     */
    function setTokenURIs(uint256[] memory tokenIds, string[] memory uris) external;

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
     * @notice Get complete token data
     * @param tokenId Token to query
     * @return Token metadata struct
     */
    function tokenData(uint256 tokenId) external view returns (TokenData memory);

    /**
     * @notice Gets cast creator's Farcaster ID
     * @param tokenId Token to query
     * @return Creator's FID
     */
    function tokenFid(uint256 tokenId) external view returns (uint96);

    /**
     * @notice Gets cast creator's primary address
     * @param tokenId Token to query
     * @return Creator's address (royalty recipient)
     */
    function tokenCreator(uint256 tokenId) external view returns (address);

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
}
