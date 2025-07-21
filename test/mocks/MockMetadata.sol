// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IMetadata} from "../../src/interfaces/IMetadata.sol";
import {ICollectibleCasts} from "../../src/interfaces/ICollectibleCasts.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract MockMetadata is IMetadata {
    using Strings for uint256;

    ICollectibleCasts public nftContract;

    constructor(address _nftContract) {
        nftContract = ICollectibleCasts(_nftContract);
    }

    function contractURI() external pure returns (string memory) {
        return "https://metadata.com/mock-contract";
    }

    function tokenURI(uint256 tokenId) external pure returns (string memory) {
        return string.concat("https://metadata.com/mock-token-", tokenId.toString());
    }

    // Functions that trigger callbacks to CollectibleCasts

    function updateTokenMetadata(uint256 tokenId) external {
        // Simulate metadata update and notify the NFT contract
        nftContract.emitMetadataUpdate(tokenId);
    }

    function updateBatchMetadata(uint256 fromTokenId, uint256 toTokenId) external {
        // Simulate batch metadata update and notify the NFT contract
        nftContract.emitBatchMetadataUpdate(fromTokenId, toTokenId);
    }

    function updateContractMetadata() external {
        // Simulate contract metadata update and notify the NFT contract
        nftContract.emitContractURIUpdated();
    }

    // Function that tries to call all three callbacks
    function updateAllMetadata(uint256 tokenId, uint256 fromTokenId, uint256 toTokenId) external {
        nftContract.emitMetadataUpdate(tokenId);
        nftContract.emitBatchMetadataUpdate(fromTokenId, toTokenId);
        nftContract.emitContractURIUpdated();
    }
}
