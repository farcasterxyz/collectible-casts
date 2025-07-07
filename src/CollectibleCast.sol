// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICollectibleCast} from "./interfaces/ICollectibleCast.sol";
import {ITransferValidator} from "./interfaces/ITransferValidator.sol";
import {IRoyalties} from "./interfaces/IRoyalties.sol";

contract CollectibleCast is ERC1155, Ownable2Step, ICollectibleCast, IERC2981 {
    // Token data stored per token ID
    struct TokenData {
        uint256 fid;
        address creator;
    }

    // Minter contract address
    address public minter;

    // Metadata contract address
    address public metadataModule;

    // Transfer validator contract address
    address public transferValidatorModule;

    // Royalties module address
    address public royaltiesModule;

    // Mapping from token ID to token data
    mapping(uint256 => TokenData) public tokenData;

    constructor() ERC1155("") Ownable(msg.sender) {}

    function setModule(bytes32 module, address addr) external onlyOwner {
        if (module == "minter") {
            address previousMinter = minter;
            minter = addr;
            emit MinterSet(previousMinter, addr);
        } else if (module == "metadata") {
            address previousMetadata = metadataModule;
            metadataModule = addr;
            emit MetadataModuleSet(previousMetadata, addr);
        } else if (module == "transferValidator") {
            address previousValidator = transferValidatorModule;
            transferValidatorModule = addr;
            emit TransferValidatorModuleSet(previousValidator, addr);
        } else if (module == "royalties") {
            address previousRoyalties = royaltiesModule;
            royaltiesModule = addr;
            emit RoyaltiesModuleSet(previousRoyalties, addr);
        } else {
            revert InvalidModule();
        }
    }

    function mint(address to, bytes32 castHash, uint256 fid, address creator) external {
        if (msg.sender != minter) revert Unauthorized();
        if (fid == 0) revert InvalidFid();

        uint256 tokenId = uint256(castHash);
        // Check if already minted by checking if FID is non-zero
        if (tokenData[tokenId].fid != 0) revert AlreadyMinted();

        tokenData[tokenId] = TokenData({
            fid: fid,
            creator: creator
        });

        _mint(to, tokenId, 1, "");
        emit CastMinted(to, castHash, tokenId, fid);
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
        
        address creator = tokenData[tokenId].creator;
        if (creator == address(0)) {
            return (address(0), 0);
        }
        
        // Delegate to royalties module
        return IRoyalties(royaltiesModule).royaltyInfo(tokenId, salePrice, creator);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    // Getter functions for backward compatibility
    function hasMinted(uint256 tokenId) external view returns (bool) {
        return tokenData[tokenId].fid != 0;
    }

    function castHashToFid(bytes32 castHash) external view returns (uint256) {
        return tokenData[uint256(castHash)].fid;
    }

    function tokenCreator(uint256 tokenId) external view returns (address) {
        return tokenData[tokenId].creator;
    }
}
