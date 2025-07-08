// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";

contract MockCollectibleCast is ICollectibleCast {
    address public minter;
    address public metadata;
    address public transferValidator;
    address public royalties;

    mapping(uint256 => TokenData) private _tokenData;
    mapping(uint256 => bool) private _exists;

    function mint(address to, bytes32 castHash, uint256 fid, address creator) external {
        if (msg.sender != minter) revert Unauthorized();

        uint256 tokenId = uint256(castHash);
        if (_exists[tokenId]) revert AlreadyMinted();

        _tokenData[tokenId] = TokenData({fid: fid, creator: creator});
        _exists[tokenId] = true;

        emit CastMinted(to, castHash, tokenId, fid, creator);
    }

    function setModule(bytes32 module, address addr) external {
        if (module == keccak256("minter")) {
            emit SetMinter(minter, addr);
            minter = addr;
        } else if (module == keccak256("metadata")) {
            emit SetMetadata(metadata, addr);
            metadata = addr;
        } else if (module == keccak256("transferValidator")) {
            emit SetTransferValidator(transferValidator, addr);
            transferValidator = addr;
        } else if (module == keccak256("royalties")) {
            emit SetRoyalties(royalties, addr);
            royalties = addr;
        } else {
            revert InvalidModule();
        }
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
        return _exists[tokenId];
    }

    function uri(uint256) external pure returns (string memory) {
        return "";
    }

    function contractURI() external pure returns (string memory) {
        return "";
    }
}
