// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Metadata} from "../../src/Metadata.sol";
import {IMetadata} from "../../src/interfaces/IMetadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MetadataTest is Test {
    Metadata public metadata;
    string constant BASE_URI = "https://api.example.com/metadata/";

    function setUp() public {
        metadata = new Metadata(BASE_URI);
    }

    function test_Constructor_SetsOwnerAndBaseUri() public {
        address owner = makeAddr("owner");
        string memory baseUri = "https://api.example.com/metadata/";

        vm.prank(owner);
        metadata = new Metadata(baseUri);

        assertEq(metadata.owner(), owner);
        assertEq(metadata.baseURI(), baseUri);
    }

    function testFuzz_Constructor_SetsOwnerAndBaseUri(address owner, string memory baseUri) public {
        vm.assume(owner != address(0));

        vm.prank(owner);
        metadata = new Metadata(baseUri);

        assertEq(metadata.owner(), owner);
        assertEq(metadata.baseURI(), baseUri);
    }

    function test_ContractURI_ReturnsCorrectFormat() public view {
        string memory contractUri = metadata.contractURI();
        assertEq(contractUri, string.concat(BASE_URI, "contract"));
    }

    function test_Uri_ReturnsCorrectTokenUri() public view {
        uint256 tokenId = 12345;
        string memory tokenUri = metadata.uri(tokenId);
        assertEq(tokenUri, string.concat(BASE_URI, "12345"));
    }

    function testFuzz_Uri_HandlesAllTokenIds(uint256 tokenId) public view {
        string memory tokenUri = metadata.uri(tokenId);
        string memory expectedUri = string.concat(BASE_URI, vm.toString(tokenId));
        assertEq(tokenUri, expectedUri);
    }

    function test_SetBaseURI_RevertsWhenNotOwner() public {
        address notOwner = makeAddr("notOwner");
        string memory newBaseUri = "https://new.example.com/";

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        metadata.setBaseURI(newBaseUri);
    }

    function test_SetBaseURI_UpdatesUris() public {
        string memory newBaseUri = "https://new.example.com/";
        
        metadata.setBaseURI(newBaseUri);
        
        assertEq(metadata.baseURI(), newBaseUri);
        assertEq(metadata.contractURI(), string.concat(newBaseUri, "contract"));
        assertEq(metadata.uri(123), string.concat(newBaseUri, "123"));
    }

    function test_SetBaseURI_EmitsEvent() public {
        string memory oldBaseUri = metadata.baseURI();
        string memory newBaseUri = "https://new.example.com/";
        
        vm.expectEmit(true, true, false, true);
        emit IMetadata.BaseURISet(oldBaseUri, newBaseUri);
        
        metadata.setBaseURI(newBaseUri);
    }

    function testFuzz_SetBaseURI_UpdatesUris(string memory newBaseUri) public {
        metadata.setBaseURI(newBaseUri);
        
        assertEq(metadata.baseURI(), newBaseUri);
        assertEq(metadata.contractURI(), string.concat(newBaseUri, "contract"));
        assertEq(metadata.uri(0), string.concat(newBaseUri, "0"));
    }
}