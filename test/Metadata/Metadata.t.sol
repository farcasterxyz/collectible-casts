// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {Metadata} from "../../src/Metadata.sol";
import {IMetadata} from "../../src/interfaces/IMetadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MetadataTest is TestSuiteSetup {
    Metadata public metadata;
    string constant BASE_URI = "https://api.example.com/metadata/";

    function setUp() public override {
        super.setUp();
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

    // Edge case tests
    function test_Uri_MaxTokenId() public view {
        // Test with maximum possible token ID
        uint256 maxTokenId = type(uint256).max;
        string memory uri = metadata.uri(maxTokenId);

        // Should not revert and should include the token ID
        assertTrue(bytes(uri).length > bytes(BASE_URI).length);

        string memory expectedUri = string.concat(BASE_URI, vm.toString(maxTokenId));
        assertEq(uri, expectedUri);
    }

    function test_Uri_ZeroTokenId() public view {
        // Test with zero token ID
        string memory expectedUri = string.concat(BASE_URI, "0");
        assertEq(metadata.uri(0), expectedUri);
    }

    function test_SetBaseURI_EmptyString() public {
        // Test setting empty base URI
        metadata.setBaseURI("");

        // URI should just be the token ID
        assertEq(metadata.uri(123), "123");
        assertEq(metadata.contractURI(), "contract");
        assertEq(metadata.baseURI(), "");
    }

    function test_SetBaseURI_VeryLongString() public {
        // Test with very long base URI
        string memory longBaseUri = "";
        for (uint256 i = 0; i < 50; i++) {
            longBaseUri = string.concat(longBaseUri, "verylongstringpart");
        }

        metadata.setBaseURI(longBaseUri);

        // Should handle long strings without issues
        string memory uri = metadata.uri(123);
        assertTrue(bytes(uri).length > 500); // Should be very long
        assertEq(metadata.baseURI(), longBaseUri);
    }

    function testFuzz_SetBaseURI_HandlesSpecialCharacters(string memory baseUri) public {
        // Test with various special characters and edge cases
        vm.assume(bytes(baseUri).length < 1000); // Reasonable length limit to avoid gas issues

        metadata.setBaseURI(baseUri);

        // Should not revert and should return concatenated string
        string memory uri = metadata.uri(123);
        assertEq(metadata.baseURI(), baseUri);

        // Verify concatenation works correctly
        string memory expectedUri = string.concat(baseUri, "123");
        assertEq(uri, expectedUri);
    }

    function test_ContractURI_WithSpecialCharacters() public {
        // Test contract URI with special characters in base URI
        string memory specialBaseUri = "https://api.example.com/special!@#$%^&*()_+/";
        metadata.setBaseURI(specialBaseUri);

        string memory expectedContractUri = string.concat(specialBaseUri, "contract");
        assertEq(metadata.contractURI(), expectedContractUri);
    }

    function test_SetBaseURI_WithUnicodeCharacters() public {
        // Test with Unicode characters
        string memory unicodeBaseUri = unicode"https://api.example.com/🚀🌟/";
        metadata.setBaseURI(unicodeBaseUri);

        assertEq(metadata.baseURI(), unicodeBaseUri);
        string memory uri = metadata.uri(123);
        assertEq(uri, string.concat(unicodeBaseUri, "123"));
    }
}
