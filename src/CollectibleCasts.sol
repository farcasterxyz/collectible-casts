// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {IERC2981} from "openzeppelin-contracts/contracts/interfaces/IERC2981.sol";
import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {ICollectibleCasts} from "./interfaces/ICollectibleCasts.sol";

/// @title CollectibleCasts
/// @notice ERC-721 token representing collectible Farcaster casts
contract CollectibleCasts is ERC721, Ownable2Step, ICollectibleCasts, IERC2981 {
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant ROYALTY_BPS = 500;

    mapping(address => bool) public minters;
    mapping(uint256 => ICollectibleCasts.TokenData) internal _tokenData;

    string internal _baseURIString;
    string internal _contractURIString;

    constructor(address owner, string memory baseURIString) ERC721("CollectibleCasts", "CASTS") Ownable(owner) {
        _baseURIString = baseURIString;
    }

    function mint(address to, bytes32 castHash, uint256 creatorFid, address creator) external {
        if (!minters[msg.sender]) revert Unauthorized();
        if (castHash == bytes32(0)) revert InvalidInput();
        if (creatorFid == 0) revert InvalidFid();

        uint256 tokenId = uint256(castHash);
        if (_tokenData[tokenId].fid != 0) revert AlreadyMinted();

        _tokenData[tokenId].fid = creatorFid;
        _tokenData[tokenId].creator = creator;

        _mint(to, tokenId);
        emit Mint(to, tokenId, castHash, creatorFid, creator);
    }

    function mint(address to, bytes32 castHash, uint256 creatorFid, address creator, string memory tokenUri) external {
        if (!minters[msg.sender]) revert Unauthorized();
        if (castHash == bytes32(0)) revert InvalidInput();
        if (creatorFid == 0) revert InvalidFid();

        uint256 tokenId = uint256(castHash);
        if (_tokenData[tokenId].fid != 0) revert AlreadyMinted();

        _tokenData[tokenId].fid = creatorFid;
        _tokenData[tokenId].creator = creator;
        _tokenData[tokenId].uri = tokenUri;

        _mint(to, tokenId);
        emit Mint(to, tokenId, castHash, creatorFid, creator);
    }

    function setBaseURI(string memory baseURI_) external onlyOwner {
        _baseURIString = baseURI_;
        emit BaseURISet(baseURI_);
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function setContractURI(string memory contractURI_) external onlyOwner {
        _contractURIString = contractURI_;
        emit ContractURIUpdated(contractURI_);
    }

    function setTokenURIs(uint256[] memory tokenIds, string[] memory uris) external onlyOwner {
        if (tokenIds.length != uris.length) revert InvalidInput();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _tokenData[tokenIds[i]].uri = uris[i];
            emit MetadataUpdate(tokenIds[i]);
        }
    }

    function allowMinter(address account) external onlyOwner {
        minters[account] = true;
        emit MinterAllowed(account);
    }

    function denyMinter(address account) external onlyOwner {
        minters[account] = false;
        emit MinterDenied(account);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721, ICollectibleCasts)
        returns (string memory)
    {
        _requireOwned(tokenId);

        string memory tokenURIString = _tokenData[tokenId].uri;
        if (bytes(tokenURIString).length > 0) {
            return tokenURIString;
        }

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string.concat(baseURI, Strings.toString(tokenId)) : "";
    }

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

    function contractURI() external view returns (string memory) {
        if (bytes(_contractURIString).length > 0) {
            return _contractURIString;
        }

        return string.concat(_baseURIString, "contract");
    }

    function tokenFid(uint256 tokenId) external view returns (uint256) {
        return _tokenData[tokenId].fid;
    }

    function tokenCreator(uint256 tokenId) external view returns (address) {
        return _tokenData[tokenId].creator;
    }

    function tokenData(uint256 tokenId) external view returns (ICollectibleCasts.TokenData memory) {
        return _tokenData[tokenId];
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIString;
    }
}
