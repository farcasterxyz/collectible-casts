// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import {IERC2981} from "openzeppelin-contracts/contracts/interfaces/IERC2981.sol";
import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {ICollectibleCast} from "./interfaces/ICollectibleCast.sol";

/// @title CollectibleCast
/// @notice ERC-1155 token representing collectible Farcaster casts
/// @dev Uses a modular architecture with swappable components for minting, metadata, transfers, and royalties
contract CollectibleCast is ERC1155, Ownable2Step, ICollectibleCast, IERC2981 {
    // Constants for royalty calculations
    uint256 public constant BPS_DENOMINATOR = 10000; // 100% = 10000 basis points
    uint256 public constant ROYALTY_BPS = 500; // 5%

    // Mapping of allowed minters
    mapping(address => bool) public allowedMinters;

    // Mapping from token ID to token data
    mapping(uint256 => ICollectibleCast.TokenData) internal _tokenData;

    constructor(address _owner, string memory baseURI_) ERC1155(baseURI_) Ownable(_owner) {}

    // External/public state-changing functions
    function mint(address to, bytes32 castHash, uint256 creatorFid, address creator, string memory tokenURI) external {
        if (!allowedMinters[msg.sender]) revert Unauthorized();
        if (creatorFid == 0) revert InvalidFid();

        uint256 tokenId = uint256(castHash);
        // Check if already minted by checking if FID is non-zero
        if (_tokenData[tokenId].fid != 0) revert AlreadyMinted();

        _tokenData[tokenId] = ICollectibleCast.TokenData({fid: creatorFid, creator: creator, uri: tokenURI});

        _mint(to, tokenId, 1, "");
        emit CastMinted(to, castHash, tokenId, creatorFid, creator);
    }

    // External permissioned functions
    /// @notice Updates a module address (currently no modules are supported)
    function setModule(bytes32, address) external onlyOwner {
        // No modules currently supported
        revert InvalidModule();
    }

    // View functions
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    // Override ERC1155 uri function to use token-specific URI or base URI
    function uri(uint256 tokenId) public view virtual override(ERC1155, ICollectibleCast) returns (string memory) {
        string memory tokenURI = _tokenData[tokenId].uri;

        // If token has specific URI, use it
        if (bytes(tokenURI).length > 0) {
            return tokenURI;
        }

        // Otherwise fall back to base URI pattern from ERC1155
        return super.uri(tokenId);
    }

    // ERC-2981 implementation
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        address creator = _tokenData[tokenId].creator;
        if (creator == address(0)) {
            return (address(0), 0);
        }

        receiver = creator;
        royaltyAmount = (salePrice * ROYALTY_BPS) / BPS_DENOMINATOR;
    }

    // Contract-level metadata
    function contractURI() external view returns (string memory) {
        string memory baseURI = super.uri(0);
        return string.concat(baseURI, "contract");
    }

    // Set base URI for all tokens
    function setBaseURI(string memory baseURI_) external onlyOwner {
        _setURI(baseURI_);
        emit BaseURISet(baseURI_);
    }

    // Batch set token-specific URIs for backfilling
    function batchSetTokenURIs(uint256[] memory tokenIds, string[] memory uris) external onlyOwner {
        if (tokenIds.length != uris.length) revert InvalidInput();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            // Only allow setting URI for existing tokens
            if (_tokenData[tokenIds[i]].fid == 0) revert TokenDoesNotExist();
            _tokenData[tokenIds[i]].uri = uris[i];
            emit URI(uris[i], tokenIds[i]);
        }
    }

    // Allow an address to mint tokens
    function allowMinter(address account) external onlyOwner {
        allowedMinters[account] = true;
        emit MinterAllowed(account);
    }

    // Deny an address from minting tokens
    function denyMinter(address account) external onlyOwner {
        allowedMinters[account] = false;
        emit MinterDenied(account);
    }

    // Getter functions
    function tokenFid(uint256 tokenId) external view returns (uint256) {
        return _tokenData[tokenId].fid;
    }

    function tokenCreator(uint256 tokenId) external view returns (address) {
        return _tokenData[tokenId].creator;
    }

    function tokenData(uint256 tokenId) external view returns (ICollectibleCast.TokenData memory) {
        return _tokenData[tokenId];
    }

    // Check if a token exists (has been minted)
    function exists(uint256 tokenId) external view returns (bool) {
        return _tokenData[tokenId].fid != 0;
    }
}
