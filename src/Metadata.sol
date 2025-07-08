// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IMetadata} from "./interfaces/IMetadata.sol";

contract Metadata is IMetadata, Ownable2Step {
    string public baseURI;

    constructor(string memory _baseURI, address _owner) Ownable(_owner) {
        baseURI = _baseURI;
    }

    // External permissioned functions
    function setBaseURI(string memory _baseURI) external onlyOwner {
        string memory oldBaseURI = baseURI;
        baseURI = _baseURI;
        emit BaseURISet(oldBaseURI, _baseURI);
    }

    // View functions
    function contractURI() external view returns (string memory) {
        return string.concat(baseURI, "contract");
    }

    function uri(uint256 tokenId) external view returns (string memory) {
        return string.concat(baseURI, Strings.toString(tokenId));
    }
}
