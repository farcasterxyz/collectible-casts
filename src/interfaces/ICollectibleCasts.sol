// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface ICollectibleCasts {
    // Token data stored per token ID
    struct TokenData {
        uint256 fid;
        address creator;
        string uri;
    }

    // Custom errors
    error Unauthorized();
    error AlreadyMinted();
    error InvalidFid();
    error InvalidInput();

    // Events
    event Mint(address indexed to, uint256 indexed tokenId, bytes32 indexed castHash, uint256 fid, address creator);
    event BaseURISet(string baseURI);
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
    event ContractURIUpdated(string contractURI);
    event MinterAllowed(address indexed account);
    event MinterDenied(address indexed account);

    function mint(address to, bytes32 castHash, uint256 creatorFid, address creator) external;
    function mint(address to, bytes32 castHash, uint256 creatorFid, address creator, string memory tokenUri) external;
    function setBaseURI(string memory baseURI_) external;
    function setContractURI(string memory contractURI_) external;
    function setTokenURIs(uint256[] memory tokenIds, string[] memory uris) external;
    function allowMinter(address account) external;
    function denyMinter(address account) external;

    // View functions
    function minters(address account) external view returns (bool);
    function tokenData(uint256 tokenId) external view returns (TokenData memory);
    function tokenFid(uint256 tokenId) external view returns (uint256);
    function tokenCreator(uint256 tokenId) external view returns (address);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function contractURI() external view returns (string memory);
}
