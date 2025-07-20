// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {CollectibleCasts} from "../../src/CollectibleCasts.sol";
import {ICollectibleCasts} from "../../src/interfaces/ICollectibleCasts.sol";
import {IMetadata} from "../../src/interfaces/IMetadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract MockMetadata is IMetadata {
    string public baseURI;
    string public customContractURI;

    constructor(string memory _baseURI) {
        baseURI = _baseURI;
    }

    function contractURI() external view returns (string memory) {
        if (bytes(customContractURI).length > 0) {
            return customContractURI;
        }
        return string.concat(baseURI, "mock-contract");
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return string.concat(baseURI, "mock-token-", Strings.toString(tokenId));
    }

    function setCustomContractURI(string memory uri) external {
        customContractURI = uri;
    }
}

contract CollectibleCastsMetadataTest is TestSuiteSetup {
    CollectibleCasts public token;
    MockMetadata public metadataModule;

    address owner = makeAddr("owner");
    address minter = makeAddr("minter");
    bytes32 castHash = keccak256("test-cast");
    uint96 creatorFid = 123;
    uint256 tokenId;

    event MetadataModuleUpdated(address indexed newModule);
    event ContractURIUpdated();
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    function setUp() public override {
        super.setUp();
        token = new CollectibleCasts(owner, "https://example.com/");
        metadataModule = new MockMetadata("https://metadata.com/");
        tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minter);

        vm.prank(minter);
        token.mint(alice, castHash, creatorFid);
    }

    function test_MetadataModule_StartsAsZeroAddress() public {
        assertEq(address(token.metadata()), address(0));
    }

    function test_SetMetadataModule_OnlyOwner() public {
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));
        assertEq(address(token.metadata()), address(metadataModule));
    }

    function testFuzz_SetMetadataModule_RevertsWhenNotOwner(address notOwner) public {
        vm.assume(notOwner != owner);
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.setMetadataModule(address(metadataModule));
    }

    function test_SetMetadataModule_EmitsEvents() public {
        vm.expectEmit(true, false, false, false);
        emit MetadataModuleUpdated(address(metadataModule));
        vm.expectEmit(false, false, false, false);
        emit ContractURIUpdated();
        vm.expectEmit(false, false, false, true);
        emit BatchMetadataUpdate(0, type(uint256).max);

        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));
    }

    function test_ContractURI_UsesModuleWhenSet() public {
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        assertEq(token.contractURI(), "https://metadata.com/mock-contract");
    }

    function test_ContractURI_FallsBackToDefaultWhenNoModule() public {
        assertEq(token.contractURI(), "https://example.com/contract");
    }

    function test_TokenURI_UsesModuleWhenSet() public {
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        assertEq(token.tokenURI(tokenId), string.concat("https://metadata.com/mock-token-", Strings.toString(tokenId)));
    }

    function test_TokenURI_FallsBackToDefaultWhenNoModule() public {
        assertEq(token.tokenURI(tokenId), string.concat("https://example.com/", Strings.toString(tokenId)));
    }

    function test_SetMetadataModule_CanUpdateModule() public {
        MockMetadata newModule = new MockMetadata("https://new-metadata.com/");

        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        vm.prank(owner);
        token.setMetadataModule(address(newModule));

        assertEq(address(token.metadata()), address(newModule));
        assertEq(token.contractURI(), "https://new-metadata.com/mock-contract");
    }

    function test_SetMetadataModule_CanSetToZeroAddress() public {
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        vm.prank(owner);
        token.setMetadataModule(address(0));

        assertEq(address(token.metadata()), address(0));
        assertEq(token.contractURI(), "https://example.com/contract");
    }

    function test_TokenURI_RevertsForNonexistentToken() public {
        uint256 nonExistentTokenId = uint256(keccak256("nonexistent"));

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, nonExistentTokenId));
        token.tokenURI(nonExistentTokenId);
    }
}
