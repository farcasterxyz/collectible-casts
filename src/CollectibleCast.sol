// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {IERC2981} from "openzeppelin-contracts/contracts/interfaces/IERC2981.sol";
import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {ICollectibleCast} from "./interfaces/ICollectibleCast.sol";

/// @title CollectibleCast
/// @notice ERC-721 token representing collectible Farcaster casts
/// @dev Uses a modular architecture with swappable components for minting, metadata, transfers, and royalties
contract CollectibleCast is ERC721, Ownable2Step, ICollectibleCast, IERC2981 {
    // Constants for royalty calculations
    uint256 public constant BPS_DENOMINATOR = 10000; // 100% = 10000 basis points
    uint256 public constant ROYALTY_BPS = 500; // 5%

    // Mapping of allowed minters
    mapping(address => bool) public allowedMinters;

    // Mapping from token ID to token data
    mapping(uint256 => ICollectibleCast.TokenData) internal _tokenData;

    // Base URI for all tokens
    string private _baseURIString;

    constructor(address _owner, string memory baseURI_) ERC721("CollectibleCast", "CAST") Ownable(_owner) {
        _baseURIString = baseURI_;
    }

    // External/public state-changing functions
    function mint(address to, bytes32 castHash, uint256 creatorFid, address creator, string memory tokenUri) external {
        if (!allowedMinters[msg.sender]) revert Unauthorized();
        if (creatorFid == 0) revert InvalidFid();

        uint256 tokenId = uint256(castHash);
        // Check if already minted by checking if FID is non-zero
        if (_tokenData[tokenId].fid != 0) revert AlreadyMinted();

        _tokenData[tokenId] = ICollectibleCast.TokenData({fid: creatorFid, creator: creator, uri: tokenUri});

        _mint(to, tokenId);
        emit CastMinted(to, castHash, tokenId, creatorFid, creator);
    }

    // External permissioned functions
    /// @notice Updates a module address (currently no modules are supported)
    function setModule(bytes32, address) external onlyOwner {
        // No modules currently supported
        revert InvalidModule();
    }

    // View functions
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    // Override ERC721 tokenURI function to use token-specific URI or base URI
    function tokenURI(uint256 tokenId) public view virtual override(ERC721, ICollectibleCast) returns (string memory) {
        // Check if token exists
        _requireOwned(tokenId);

        string memory tokenURIString = _tokenData[tokenId].uri;

        // If token has specific URI, use it
        if (bytes(tokenURIString).length > 0) {
            return tokenURIString;
        }

        // Otherwise fall back to base URI pattern
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, _toString(tokenId))) : "";
    }

    // Override base URI function
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIString;
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
        return string.concat(_baseURIString, "contract");
    }

    // Set base URI for all tokens
    function setBaseURI(string memory baseURI_) external onlyOwner {
        _baseURIString = baseURI_;
        emit BaseURISet(baseURI_);
    }

    // Batch set token-specific URIs for backfilling
    function batchSetTokenURIs(uint256[] memory tokenIds, string[] memory uris) external onlyOwner {
        if (tokenIds.length != uris.length) revert InvalidInput();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            // Only allow setting URI for existing tokens
            if (_tokenData[tokenIds[i]].fid == 0) revert TokenDoesNotExist();
            _tokenData[tokenIds[i]].uri = uris[i];
            emit MetadataUpdate(tokenIds[i]);
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

    // Internal helper to convert uint256 to string
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
