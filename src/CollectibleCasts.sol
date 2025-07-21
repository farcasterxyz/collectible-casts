// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ICollectibleCasts} from "./interfaces/ICollectibleCasts.sol";
import {IMetadata} from "./interfaces/IMetadata.sol";

/**
 * @title CollectibleCasts
 * @notice Farcaster collectible casts
 * @custom:security-contact security@merklemanufactory.com
 */
contract CollectibleCasts is ERC721, Ownable2Step, Pausable, ICollectibleCasts {
    /// @dev Optional metadata module
    IMetadata public metadata;

    /// @dev Mapping of address to auth status
    mapping(address account => bool authorized) public minters;

    /// @dev Mapping of token ID to creator's Farcaster ID
    mapping(uint256 tokenId => uint256 fid) internal _tokenFids;

    /// @dev Base URI for token metadata
    string internal _baseURIString;

    /// @dev Contract metadata URI
    string internal _contractURIString;

    /**
     * @notice Creates CollectibleCasts contract
     * @param owner Contract owner address
     * @param baseURIString Base metadata URI
     */
    constructor(address owner, string memory baseURIString)
        ERC721("Farcaster collectible casts", "CASTS")
        Ownable(owner)
    {
        _baseURIString = baseURIString;
    }

    /// @inheritdoc ICollectibleCasts
    function mint(address to, bytes32 castHash, uint256 creatorFid) external whenNotPaused {
        if (!minters[msg.sender]) revert Unauthorized();
        if (castHash == bytes32(0)) revert InvalidInput();
        if (creatorFid == 0) revert InvalidFid();

        uint256 tokenId = uint256(castHash);
        if (_tokenFids[tokenId] != 0) revert AlreadyMinted();

        _tokenFids[tokenId] = creatorFid;

        _mint(to, tokenId);
        emit Mint(to, tokenId, creatorFid, castHash);
    }

    /// @inheritdoc ICollectibleCasts
    function setBaseURI(string memory baseURI_) external onlyOwner {
        _baseURIString = baseURI_;
        emit BaseURISet(baseURI_);
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    /// @inheritdoc ICollectibleCasts
    function setContractURI(string memory contractURI_) external onlyOwner {
        _contractURIString = contractURI_;
        emit ContractURIUpdated();
    }

    /// @inheritdoc ICollectibleCasts
    function allowMinter(address account) external onlyOwner {
        minters[account] = true;
        emit MinterAllowed(account);
    }

    /// @inheritdoc ICollectibleCasts
    function denyMinter(address account) external onlyOwner {
        minters[account] = false;
        emit MinterDenied(account);
    }

    /// @inheritdoc ICollectibleCasts
    function setMetadataModule(address module) external onlyOwner {
        metadata = IMetadata(module);
        emit MetadataModuleUpdated(module);
        emit ContractURIUpdated();
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    /// @inheritdoc ICollectibleCasts
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721, ICollectibleCasts)
        returns (string memory)
    {
        _requireOwned(tokenId);

        if (address(metadata) != address(0)) {
            return metadata.tokenURI(tokenId);
        }

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string.concat(baseURI, Strings.toString(tokenId)) : "";
    }

    /// @inheritdoc ICollectibleCasts
    function contractURI() external view returns (string memory) {
        if (address(metadata) != address(0)) {
            return metadata.contractURI();
        }

        if (bytes(_contractURIString).length > 0) {
            return _contractURIString;
        }

        return string.concat(_baseURIString, "contract");
    }

    /// @inheritdoc ICollectibleCasts
    function tokenFid(uint256 tokenId) external view returns (uint256) {
        return _tokenFids[tokenId];
    }

    /// @inheritdoc ICollectibleCasts
    function isMinted(uint256 tokenId) external view returns (bool) {
        return _tokenFids[tokenId] != 0;
    }

    /// @inheritdoc ICollectibleCasts
    function isMinted(bytes32 castHash) external view returns (bool) {
        return _tokenFids[uint256(castHash)] != 0;
    }

    /**
     * @notice Pauses all minting operations
     * @dev Only callable by contract owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resumes all minting operations
     * @dev Only callable by contract owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @dev Returns base URI for token metadata
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIString;
    }
}
