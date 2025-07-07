// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface ICollectibleCast {
    // Token data stored per token ID
    struct TokenData {
        uint256 fid;
        address creator;
    }

    // Custom errors
    error Unauthorized();
    error AlreadyMinted();
    error TransferNotAllowed();
    error InvalidModule();
    error InvalidFid();

    // Events
    event MinterSet(address indexed previousMinter, address indexed newMinter);
    event CastMinted(address indexed to, bytes32 indexed castHash, uint256 indexed tokenId, uint256 fid);
    event MetadataModuleSet(address indexed previousMetadata, address indexed newMetadata);
    event TransferValidatorModuleSet(address indexed previousValidator, address indexed newValidator);
    event RoyaltiesModuleSet(address indexed previousRoyalties, address indexed newRoyalties);

    function mint(address to, bytes32 castHash, uint256 fid, address creator) external;
    function setModule(bytes32 module, address addr) external;

    // View functions
    function minter() external view returns (address);
    function metadataModule() external view returns (address);
    function transferValidatorModule() external view returns (address);
    function royaltiesModule() external view returns (address);
    function tokenData(uint256 tokenId) external view returns (TokenData memory);
    function castHashToFid(bytes32 castHash) external view returns (uint256);
    function tokenCreator(uint256 tokenId) external view returns (address);
    function uri(uint256 tokenId) external view returns (string memory);
    function contractURI() external view returns (string memory);
}
