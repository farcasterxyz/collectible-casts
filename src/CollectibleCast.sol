// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ICollectibleCast} from "./interfaces/ICollectibleCast.sol";

contract CollectibleCast is ERC1155, Ownable2Step, ICollectibleCast {
    // Minter contract address
    address public minter;
    
    // Mapping to track if a token has been minted
    mapping(uint256 => bool) public hasMinted;
    
    // Mapping from cast hash to FID
    mapping(bytes32 => uint256) public castHashToFid;
    
    constructor() ERC1155("") Ownable(msg.sender) {}
    
    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }
    
    function mint(address to, bytes32 castHash, uint256 fid) external {
        if (msg.sender != minter) revert Unauthorized();
        
        uint256 tokenId = uint256(castHash);
        if (hasMinted[tokenId]) revert AlreadyMinted();
        
        hasMinted[tokenId] = true;
        castHashToFid[castHash] = fid;
        
        _mint(to, tokenId, 1, "");
    }
}