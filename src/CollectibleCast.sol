// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICollectibleCast} from "./interfaces/ICollectibleCast.sol";
import {ITransferValidator} from "./interfaces/ITransferValidator.sol";

contract CollectibleCast is ERC1155, Ownable2Step, ICollectibleCast, IERC2981 {
    // Minter contract address
    address public minter;

    // Metadata contract address
    address public metadataModule;

    // Transfer validator contract address
    address public transferValidatorModule;

    // Royalties module address
    address public royaltiesModule;

    // Mapping to track if a token has been minted
    mapping(uint256 => bool) public hasMinted;

    // Mapping from cast hash to FID
    mapping(bytes32 => uint256) public castHashToFid;

    // Mapping from token ID to creator address
    mapping(uint256 => address) public tokenCreator;

    constructor() ERC1155("") Ownable(msg.sender) {}

    function setMinter(address _minter) external onlyOwner {
        address previousMinter = minter;
        minter = _minter;
        emit MinterSet(previousMinter, _minter);
    }

    function mint(address to, bytes32 castHash, uint256 fid, address creator) external {
        if (msg.sender != minter) revert Unauthorized();

        uint256 tokenId = uint256(castHash);
        if (hasMinted[tokenId]) revert AlreadyMinted();

        hasMinted[tokenId] = true;
        castHashToFid[castHash] = fid;
        tokenCreator[tokenId] = creator;

        _mint(to, tokenId, 1, "");
        emit CastMinted(to, castHash, tokenId, fid);
    }

    function setMetadataModule(address _metadata) external onlyOwner {
        address previousMetadata = metadataModule;
        metadataModule = _metadata;
        emit MetadataModuleSet(previousMetadata, _metadata);
    }

    function setTransferValidatorModule(address _validator) external onlyOwner {
        address previousValidator = transferValidatorModule;
        transferValidatorModule = _validator;
        emit TransferValidatorModuleSet(previousValidator, _validator);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        virtual
        override
    {
        // If transferValidatorModule is set and this is not a mint operation, validate the transfer
        if (transferValidatorModule != address(0) && from != address(0)) {
            bool isAllowed =
                ITransferValidator(transferValidatorModule).validateTransfer(msg.sender, from, to, ids, values);
            if (!isAllowed) revert TransferNotAllowed();
        }

        super._update(from, to, ids, values);
    }

    function setRoyaltiesModule(address _royalties) external onlyOwner {
        address previousRoyalties = royaltiesModule;
        royaltiesModule = _royalties;
        emit RoyaltiesModuleSet(previousRoyalties, _royalties);
    }

    // ERC-2981 implementation that delegates to royalties module
    function royaltyInfo(uint256 tokenId, uint256 salePrice) 
        external 
        view 
        override 
        returns (address receiver, uint256 royaltyAmount) 
    {
        if (royaltiesModule == address(0)) {
            return (address(0), 0);
        }
        
        address creator = tokenCreator[tokenId];
        if (creator == address(0)) {
            return (address(0), 0);
        }
        
        // For now, return 5% royalty to the creator directly
        receiver = creator;
        royaltyAmount = (salePrice * 500) / 10000; // 5%
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}
