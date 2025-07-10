// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";

contract MockCollectibleCast is ICollectibleCast {
    mapping(address => bool) public allowedMinters;
    mapping(uint256 => TokenData) private _tokenData;
    mapping(bytes32 => bool) public minted;
    uint256 public nextTokenId = 1;

    address public transferValidator;
    address public royalties;
    string public baseURI;

    // Track mint calls for testing
    struct MintCall {
        address to;
        bytes32 castHash;
        uint256 creatorFid;
        address creator;
        string tokenURI;
    }

    MintCall[] public mintCalls;

    function mint(address to, bytes32 castHash, uint256 creatorFid, address creator, string memory tokenURI) external {
        if (!allowedMinters[msg.sender]) revert Unauthorized();
        if (minted[castHash]) revert AlreadyMinted();
        if (creatorFid == 0) revert InvalidFid();

        uint256 tokenId = nextTokenId++;
        minted[castHash] = true;

        _tokenData[tokenId] = TokenData({fid: creatorFid, creator: creator, uri: tokenURI});

        mintCalls.push(
            MintCall({to: to, castHash: castHash, creatorFid: creatorFid, creator: creator, tokenURI: tokenURI})
        );

        emit CastMinted(to, castHash, tokenId, creatorFid, creator);
    }

    function setModule(bytes32 module, address addr) external {
        if (module == "TRANSFER_VALIDATOR") {
            transferValidator = addr;
            emit SetTransferValidator(transferValidator, addr);
        } else if (module == "ROYALTIES") {
            royalties = addr;
            emit SetRoyalties(royalties, addr);
        }
    }

    function setBaseURI(string memory baseURI_) external {
        baseURI = baseURI_;
        emit BaseURISet(baseURI_);
    }

    function batchSetTokenURIs(uint256[] memory tokenIds, string[] memory uris) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _tokenData[tokenIds[i]].uri = uris[i];
        }
    }

    function allowMinter(address account) external {
        allowedMinters[account] = true;
        emit MinterAllowed(account);
    }

    function denyMinter(address account) external {
        allowedMinters[account] = false;
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

    function exists(uint256 tokenId) external view returns (bool) {
        return _tokenData[tokenId].fid != 0;
    }

    function uri(uint256) external view returns (string memory) {
        return baseURI;
    }

    function contractURI() external view returns (string memory) {
        return baseURI;
    }

    // Helper functions for testing
    function getMintCallCount() external view returns (uint256) {
        return mintCalls.length;
    }

    function getMintCall(uint256 index) external view returns (MintCall memory) {
        return mintCalls[index];
    }
}
