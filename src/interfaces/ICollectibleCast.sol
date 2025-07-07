// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface ICollectibleCast {
    // Custom errors
    error Unauthorized();
    error AlreadyMinted();
    error TransferNotAllowed();

    // Events
    event MinterSet(address indexed previousMinter, address indexed newMinter);
    event CastMinted(address indexed to, bytes32 indexed castHash, uint256 indexed tokenId, uint256 fid);
    event MetadataModuleSet(address indexed previousMetadata, address indexed newMetadata);
    event TransferValidatorModuleSet(address indexed previousValidator, address indexed newValidator);
    event RoyaltiesModuleSet(address indexed previousRoyalties, address indexed newRoyalties);

    function mint(address to, bytes32 castHash, uint256 fid, address creator) external;
    function setMetadataModule(address metadata) external;
    function setTransferValidatorModule(address validator) external;
    function setRoyaltiesModule(address royalties) external;
}
