// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ICollectibleCasts} from "../../src/interfaces/ICollectibleCasts.sol";

contract MockCollectibleCasts is ICollectibleCasts {
    mapping(address => bool) public minters;
    mapping(uint256 => TokenData) private _tokenData;
    mapping(bytes32 => bool) public minted;
    uint256 public nextTokenId = 1;

    string public baseURI;
    string public contractURIString;

    // Track mint calls for testing
    struct MintCall {
        address to;
        bytes32 castHash;
        uint256 creatorFid;
        address creator;
        string tokenURI;
    }

    MintCall[] public mintCalls;

    // Mint without custom tokenUri
    function mint(address to, bytes32 castHash, uint256 creatorFid, address creator) external {
        if (!minters[msg.sender]) revert Unauthorized();
        if (minted[castHash]) revert AlreadyMinted();
        if (creatorFid == 0) revert InvalidFid();

        uint256 tokenId = nextTokenId++;
        minted[castHash] = true;

        _tokenData[tokenId] = TokenData({fid: creatorFid, creator: creator, uri: ""});

        mintCalls.push(
            MintCall({to: to, castHash: castHash, creatorFid: creatorFid, creator: creator, tokenURI: ""})
        );

        emit Mint(to, tokenId, castHash, creatorFid, creator);
    }

    // Mint with custom tokenUri
    function mint(address to, bytes32 castHash, uint256 creatorFid, address creator, string memory tokenUri) external {
        if (!minters[msg.sender]) revert Unauthorized();
        if (minted[castHash]) revert AlreadyMinted();
        if (creatorFid == 0) revert InvalidFid();

        uint256 tokenId = nextTokenId++;
        minted[castHash] = true;

        _tokenData[tokenId] = TokenData({fid: creatorFid, creator: creator, uri: tokenUri});

        mintCalls.push(
            MintCall({to: to, castHash: castHash, creatorFid: creatorFid, creator: creator, tokenURI: tokenUri})
        );

        emit Mint(to, tokenId, castHash, creatorFid, creator);
    }


    function setBaseURI(string memory baseURI_) external {
        baseURI = baseURI_;
        emit BaseURISet(baseURI_);
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function setContractURI(string memory contractURI_) external {
        contractURIString = contractURI_;
        emit ContractURIUpdated(contractURI_);
    }

    function setTokenURIs(uint256[] memory tokenIds, string[] memory uris) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _tokenData[tokenIds[i]].uri = uris[i];
        }
    }

    function allowMinter(address account) external {
        minters[account] = true;
        emit MinterAllowed(account);
    }

    function denyMinter(address account) external {
        minters[account] = false;
        emit MinterDenied(account);
    }

    function tokenData(uint256 tokenId) external view returns (TokenData memory) {
        return _tokenData[tokenId];
    }

    function tokenFid(uint256 tokenId) external view returns (uint256) {
        return _tokenData[tokenId].fid;
    }

    function tokenCreator(uint256 tokenId) external view returns (address) {
        return _tokenData[tokenId].creator;
    }


    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return _tokenData[tokenId].uri;
    }

    function contractURI() external view returns (string memory) {
        if (bytes(contractURIString).length > 0) {
            return contractURIString;
        }
        return string.concat(baseURI, "contract");
    }

    // Helper functions for testing
    function getMintCallCount() external view returns (uint256) {
        return mintCalls.length;
    }

    function getMintCall(uint256 index) external view returns (MintCall memory) {
        return mintCalls[index];
    }
}
