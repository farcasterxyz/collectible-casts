// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface ICollectibleCast {
    // Token data stored per token ID
    struct TokenData {
        uint256 fid;
        address creator;
        string uri;
    }

    // Custom errors
    error Unauthorized();
    error AlreadyMinted();
    error TransferNotAllowed();
    error InvalidModule();
    error InvalidFid();
    error InvalidInput();
    error TokenDoesNotExist();

    // Events
    event CastMinted(
        address indexed to, bytes32 indexed castHash, uint256 indexed tokenId, uint256 fid, address creator
    );
    event SetTransferValidator(address indexed previousValidator, address indexed newValidator);
    event BaseURISet(string baseURI);
    event MinterAllowed(address indexed account);
    event MinterDenied(address indexed account);

    function mint(address to, bytes32 castHash, uint256 creatorFid, address creator, string memory tokenURI) external;
    function setModule(bytes32 module, address addr) external;
    function setBaseURI(string memory baseURI_) external;
    function batchSetTokenURIs(uint256[] memory tokenIds, string[] memory uris) external;
    function allowMinter(address account) external;
    function denyMinter(address account) external;

    // View functions
    function allowedMinters(address account) external view returns (bool);
    function transferValidator() external view returns (address);
    function tokenData(uint256 tokenId) external view returns (TokenData memory);
    function tokenFid(uint256 tokenId) external view returns (uint256);
    function tokenCreator(uint256 tokenId) external view returns (address);
    function exists(uint256 tokenId) external view returns (bool);
    function uri(uint256 tokenId) external view returns (string memory);
    function contractURI() external view returns (string memory);
}
