// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {MockERC721Receiver} from "../mocks/MockERC721Receiver.sol";
import {MockNonERC721Receiver} from "../mocks/MockNonERC721Receiver.sol";
import {CollectibleCasts} from "../../src/CollectibleCasts.sol";
import {ICollectibleCasts} from "../../src/interfaces/ICollectibleCasts.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract CollectibleCastsTest is TestSuiteSetup {
    CollectibleCasts public token;
    MockERC721Receiver public validReceiver;
    MockNonERC721Receiver public invalidReceiver;

    address owner = makeAddr("owner");
    address minter = makeAddr("minter");
    address creator = makeAddr("creator");
    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        token = new CollectibleCasts(owner, "https://example.com/");
        validReceiver = new MockERC721Receiver();
        invalidReceiver = new MockNonERC721Receiver();
    }

    function testFuzz_AllowMinter_OnlyOwner(address minterAddr) public {
        vm.prank(owner);
        token.allowMinter(minterAddr);
        assertTrue(token.minters(minterAddr));
    }

    function testFuzz_AllowMinter_RevertsWhenNotOwner(address minterAddr, address notOwner) public {
        vm.assume(notOwner != owner);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.allowMinter(minterAddr);
    }

    function testFuzz_AllowMinter_EmitsEvent(address minterAddr) public {
        vm.expectEmit(true, false, false, true);
        emit ICollectibleCasts.MinterAllowed(minterAddr);

        vm.prank(owner);
        token.allowMinter(minterAddr);
    }

    function testFuzz_DenyMinter_OnlyOwner(address minterAddr) public {
        vm.prank(owner);
        token.allowMinter(minterAddr);
        assertTrue(token.minters(minterAddr));

        vm.prank(owner);
        token.denyMinter(minterAddr);
        assertFalse(token.minters(minterAddr));
    }

    function testFuzz_DenyMinter_RevertsWhenNotOwner(address minterAddr, address notOwner) public {
        vm.assume(notOwner != owner);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.denyMinter(minterAddr);
    }

    function testFuzz_DenyMinter_EmitsEvent(address minterAddr) public {
        vm.prank(owner);
        token.allowMinter(minterAddr);

        // Then deny with event
        vm.expectEmit(true, false, false, true);
        emit ICollectibleCasts.MinterDenied(minterAddr);

        vm.prank(owner);
        token.denyMinter(minterAddr);
    }

    function testFuzz_Constructor_SetsOwner(address ownerAddr) public {
        vm.assume(ownerAddr != address(0));
        vm.prank(ownerAddr);
        CollectibleCasts newToken = new CollectibleCasts(ownerAddr, "https://example.com/");

        assertEq(newToken.owner(), ownerAddr);
    }

    function test_SupportsERC721Interface() public view {
        // ERC-721 interface ID
        bytes4 erc721InterfaceId = 0x80ac58cd;
        assertTrue(token.supportsInterface(erc721InterfaceId));

        // ERC-165 interface ID (supportsInterface itself)
        bytes4 erc165InterfaceId = 0x01ffc9a7;
        assertTrue(token.supportsInterface(erc165InterfaceId));
    }

    function testFuzz_Mint_RevertsWhenNotAllowedMinter(
        address notMinter,
        address recipient,
        bytes32 castHash,
        uint96 fid,
        address _creator
    ) public {
        vm.assume(!token.minters(notMinter));
        vm.assume(recipient != address(0));
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        vm.prank(notMinter);
        vm.expectRevert(ICollectibleCasts.Unauthorized.selector);
        token.mint(recipient, castHash, fid, _creator);
    }

    function testFuzz_Mint_RevertsWhenFidIsZero(address recipient, bytes32 castHash) public {
        vm.assume(recipient != address(0));
        vm.assume(castHash != bytes32(0));

        vm.prank(owner);
        token.allowMinter(minter);

        vm.prank(minter);
        vm.expectRevert(ICollectibleCasts.InvalidFid.selector);
        token.mint(recipient, castHash, 0, creator);
    }

    function testFuzz_Mint_Succeeds(address recipient, bytes32 castHash, uint96 fid) public {
        vm.assume(recipient != address(0));
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minter);

        vm.prank(minter);
        token.mint(recipient, castHash, fid, creator);

        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.ownerOf(tokenId), recipient);
        assertEq(token.tokenFid(tokenId), fid);
        assertEq(token.tokenCreator(tokenId), creator);
    }

    function testFuzz_Mint_EmitsEvent(address recipient, bytes32 castHash, uint96 fid) public {
        vm.assume(recipient != address(0));
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minter);

        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.Mint(recipient, tokenId, castHash, fid, creator);

        vm.prank(minter);
        token.mint(recipient, castHash, fid, creator);
    }

    function testFuzz_Mint_ToERC721Receiver(bytes32 castHash, uint96 fid) public {
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minter);

        vm.prank(minter);
        token.mint(address(validReceiver), castHash, fid, creator);

        assertEq(token.balanceOf(address(validReceiver)), 1);
        assertEq(token.ownerOf(tokenId), address(validReceiver));
        assertEq(token.tokenFid(tokenId), fid);
    }

    function testFuzz_Mint_ToNonReceiver_Succeeds(bytes32 castHash, uint96 fid) public {
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minter);

        vm.prank(minter);
        token.mint(address(invalidReceiver), castHash, fid, creator);

        assertEq(token.ownerOf(tokenId), address(invalidReceiver));
        assertEq(token.balanceOf(address(invalidReceiver)), 1);
    }

    function testFuzz_Mint_MultipleCasts(bytes32[5] memory castHashes, uint96 baseFid) public {
        vm.prank(owner);
        token.allowMinter(minter);
        baseFid = uint96(_bound(uint256(baseFid), 1, type(uint96).max - 5));

        for (uint256 i = 0; i < castHashes.length; i++) {
            vm.assume(castHashes[i] != bytes32(0));
            for (uint256 j = 0; j < i; j++) {
                vm.assume(castHashes[i] != castHashes[j]);
            }

            uint256 tokenId = uint256(castHashes[i]);
            uint96 fid = uint96(baseFid + i);

            vm.prank(minter);
            token.mint(receiver, castHashes[i], fid, creator);

            assertEq(token.ownerOf(tokenId), receiver);
            assertEq(token.tokenFid(uint256(castHashes[i])), fid);
        }
    }

    function testFuzz_Mint_RevertsOnDoubleMint(address recipient, bytes32 castHash, uint96 fid) public {
        vm.assume(recipient != address(0));
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        vm.prank(owner);
        token.allowMinter(minter);

        vm.prank(minter);
        token.mint(recipient, castHash, fid, creator);

        vm.prank(minter);
        vm.expectRevert(ICollectibleCasts.AlreadyMinted.selector);
        token.mint(recipient, castHash, fid, creator);
    }

    function testFuzz_Mint_RevertsOnDoubleMintDifferentRecipients(
        address alice,
        address bob,
        bytes32 castHash,
        uint96 fid1,
        uint96 fid2
    ) public {
        vm.assume(alice != address(0));
        vm.assume(bob != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        fid1 = uint96(_bound(uint256(fid1), 1, type(uint96).max)); // FID must be non-zero
        fid2 = uint96(_bound(uint256(fid2), 1, type(uint96).max)); // FID must be non-zero
        // No need to check for EOA since we're using regular mint, not safeMint

        address minterAddr = makeAddr("minter");
        vm.prank(owner);
        token.allowMinter(minterAddr);

        // First mint should succeed
        vm.prank(minterAddr);
        token.mint(alice, castHash, fid1, makeAddr("creator"));

        // Second mint of same cast should revert, even to different recipient with different FID
        vm.prank(minterAddr);
        vm.expectRevert(ICollectibleCasts.AlreadyMinted.selector);
        token.mint(bob, castHash, fid2, makeAddr("creator"));
    }

    function test_SupportsERC2981Interface() public view {
        // ERC-2981 interface ID
        bytes4 erc2981InterfaceId = 0x2a55205a;
        assertTrue(token.supportsInterface(erc2981InterfaceId));
    }

    function test_RoyaltyInfo_ReturnsZeroForUnmintedToken() public view {
        // Test royalty for unminted token
        bytes32 castHash = keccak256("unmintedRoyaltyTest");
        uint256 tokenId = uint256(castHash);
        uint256 salePrice = 1000 ether;

        (address royaltyReceiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return zero since token doesn't exist
        assertEq(royaltyReceiver, address(0));
        assertEq(royaltyAmount, 0);
    }

    function test_RoyaltyInfo_ReturnsZeroWhenCreatorIsZeroAddress() public {
        // Test royalty when creator is zero address
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("zeroCreatorToken");
        uint256 tokenId = uint256(castHash);
        uint96 fid = 123;

        // Mint token with zero address as creator
        vm.prank(owner);
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(makeAddr("recipient"), castHash, fid, address(0));

        uint256 salePrice = 1000 ether;
        (address royaltyReceiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return zero since creator is zero address
        assertEq(royaltyReceiver, address(0));
        assertEq(royaltyAmount, 0);
    }

    function test_RoyaltyInfo_ReturnsCreatorRoyalty() public {
        // Set up a token with a creator
        address minterAddr = makeAddr("minter");
        address testCreator = makeAddr("testCreator");
        bytes32 castHash = keccak256("royaltyTest");
        uint256 tokenId = uint256(castHash);
        uint96 fid = 123;

        // Mint token with creator
        vm.prank(owner);
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(receiver, castHash, fid, testCreator);

        // Test royalty calculation
        uint256 salePrice = 1000 ether;
        (address royaltyReceiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return 5% to creator
        assertEq(royaltyReceiver, testCreator);
        assertEq(royaltyAmount, salePrice * ROYALTY_BPS / BPS_DENOMINATOR); // 5%
        assertEq(royaltyAmount, 50 ether); // 5% of 1000 ether
    }

    function testFuzz_RoyaltyInfo_ReturnsCreatorRoyalty(uint256 salePrice, bytes32 castHash, address testCreator)
        public
    {
        salePrice = _bound(salePrice, 0, 1000000 ether);
        vm.assume(testCreator != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero

        // Set up a token with a creator
        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);
        uint96 fid = 123;

        // Mint token with creator
        vm.prank(owner);
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(makeAddr("recipient"), castHash, fid, testCreator);

        // Test royalty calculation
        (address royaltyReceiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return 5% to creator
        assertEq(royaltyReceiver, testCreator);
        assertEq(royaltyAmount, salePrice * ROYALTY_BPS / BPS_DENOMINATOR); // 5%
        assertTrue(royaltyAmount <= salePrice);
    }

    // Royalty edge case tests
    function test_RoyaltyInfo_ZeroSalePrice() public {
        // Mint a token with creator
        address minterAddr = makeAddr("minter");
        address testCreator = makeAddr("testCreator");
        bytes32 castHash = keccak256("zeroSalePriceTest");
        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, testCreator);

        // Test with zero sale price
        (address royaltyReceiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, 0);

        assertEq(royaltyReceiver, testCreator);
        assertEq(royaltyAmount, 0); // 5% of 0 is 0
    }

    function test_RoyaltyInfo_MaxSalePrice() public {
        // Mint a token with creator
        address minterAddr = makeAddr("minter");
        address testCreator = makeAddr("testCreator");
        bytes32 castHash = keccak256("maxSalePriceTest");
        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, testCreator);

        // Test with max uint256 sale price - this should revert due to overflow
        uint256 maxPrice = type(uint256).max;

        // The royalty calculation will overflow, so we expect a revert
        vm.expectRevert(); // Arithmetic overflow
        token.royaltyInfo(tokenId, maxPrice);
    }

    function test_RoyaltyInfo_LargeSafeSalePrice() public {
        // Mint a token with creator
        address minterAddr = makeAddr("minter");
        address testCreator = makeAddr("testCreator");
        bytes32 castHash = keccak256("largeSalePriceTest");
        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, testCreator);

        // Test with largest safe price that won't overflow
        uint256 largePrice = type(uint256).max / ROYALTY_BPS;
        (address royaltyReceiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, largePrice);

        assertEq(royaltyReceiver, testCreator);
        // Calculate expected royalty
        uint256 expectedRoyalty = (largePrice * ROYALTY_BPS) / BPS_DENOMINATOR;
        assertEq(royaltyAmount, expectedRoyalty);
        assertTrue(royaltyAmount > 0);
        assertTrue(royaltyAmount < largePrice);
    }

    function test_RoyaltyInfo_SmallAmounts() public {
        // Mint a token with creator
        address minterAddr = makeAddr("minter");
        address testCreator = makeAddr("testCreator");
        bytes32 castHash = keccak256("smallAmountTest");
        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, testCreator);

        // Test with small amounts where royalty would round down to 0
        (address royaltyReceiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, 199); // 5% of 199 = 9.95, rounds to 9

        assertEq(royaltyReceiver, testCreator);
        assertEq(royaltyAmount, 9); // 199 * ROYALTY_BPS / BPS_DENOMINATOR = 9

        // Test with very small amount
        (, royaltyAmount) = token.royaltyInfo(tokenId, 19); // 5% of 19 = 0.95, rounds to 0
        assertEq(royaltyAmount, 0);
    }

    function testFuzz_RoyaltyInfo_MathematicalCorrectness(uint256 salePrice) public {
        // Bound sale price to avoid overflow
        salePrice = _bound(salePrice, 0, type(uint256).max / ROYALTY_BPS);

        // Mint a token with creator
        address minterAddr = makeAddr("minter");
        address testCreator = makeAddr("testCreator");
        bytes32 castHash = keccak256("mathTest");
        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, testCreator);

        // Get royalty
        (, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Verify mathematical properties
        uint256 expectedRoyalty = (salePrice * ROYALTY_BPS) / BPS_DENOMINATOR;
        assertEq(royaltyAmount, expectedRoyalty);

        // Verify royalty is never more than 5%
        if (salePrice > 0) {
            uint256 royaltyPercentage = (royaltyAmount * BPS_DENOMINATOR) / salePrice;
            assertLe(royaltyPercentage, ROYALTY_BPS);
        }
    }

    function test_TokenURI_ReturnsEmptyWhenNoBaseURI() public {
        // Create a new token instance with empty base URI
        CollectibleCasts emptyBaseToken = new CollectibleCasts(address(this), "");

        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("emptyBaseTest");
        uint256 tokenId = uint256(castHash);

        emptyBaseToken.allowMinter(minterAddr);
        vm.prank(minterAddr);
        emptyBaseToken.mint(makeAddr("recipient"), castHash, 123, makeAddr("creator"));

        // tokenURI should return empty string when no specific URI and no base URI
        assertEq(emptyBaseToken.tokenURI(tokenId), "");
    }

    function test_TokenURI_WithTokenIdZero() public {
        bytes32 castHash = bytes32(0);

        vm.prank(owner);
        token.allowMinter(minter);

        vm.prank(minter);
        vm.expectRevert(ICollectibleCasts.InvalidInput.selector);
        token.mint(receiver, castHash, 123, creator);
    }

    function test_TokenURI_RevertsForNonExistentToken() public {
        uint256 nonExistentTokenId = 999;

        // Should revert when querying URI for non-existent token
        vm.expectRevert();
        token.tokenURI(nonExistentTokenId);
    }

    function test_Uri_ReturnsTokenSpecificURI() public {
        // Mint a token with a specific URI
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("test");
        uint256 tokenId = uint256(castHash);
        string memory specificURI = "https://custom.example.com/token123";

        vm.prank(owner);
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, makeAddr("creator"), specificURI);

        // Test that tokenURI returns the token-specific URI
        assertEq(token.tokenURI(tokenId), specificURI);
    }

    function test_Uri_FallsBackToBaseURI() public {
        // Mint a token without a specific URI
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("test");
        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, makeAddr("creator"));

        // Test that tokenURI returns base URI pattern
        string memory actualUri = token.tokenURI(tokenId);
        // For ERC721, when no specific URI is set, it appends tokenId to base URI
        string memory expectedUri = string(abi.encodePacked("https://example.com/", vm.toString(tokenId)));
        assertEq(actualUri, expectedUri);
    }

    function test_ContractURI_ReturnsBaseURIPlusContract() public view {
        // Test that contractURI returns baseURI + "contract"
        string memory expectedUri = "https://example.com/contract";
        assertEq(token.contractURI(), expectedUri);
    }

    function test_SetContractURI_OnlyOwner() public {
        string memory newContractURI = "https://custom.com/contract-metadata";

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, minter));
        token.setContractURI(newContractURI);
    }

    function test_SetContractURI_UpdatesContractURI() public {
        string memory customContractURI = "https://custom.com/contract-metadata";

        // Initially, contractURI should return base + "contract"
        assertEq(token.contractURI(), "https://example.com/contract");

        // Set custom contract URI
        vm.prank(owner);
        token.setContractURI(customContractURI);

        // Now contractURI should return the custom URI
        assertEq(token.contractURI(), customContractURI);
    }

    function test_SetContractURI_EmitsEvent() public {
        string memory customContractURI = "https://custom.com/contract-metadata";

        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.ContractURIUpdated(customContractURI);

        vm.prank(owner);
        token.setContractURI(customContractURI);
    }

    function test_SetContractURI_EmptyStringFallsBackToDefault() public {
        string memory customContractURI = "https://custom.com/contract-metadata";

        // Set custom contract URI
        vm.prank(owner);
        token.setContractURI(customContractURI);
        assertEq(token.contractURI(), customContractURI);

        // Set empty string
        vm.prank(owner);
        token.setContractURI("");

        // Should fall back to base + "contract"
        assertEq(token.contractURI(), "https://example.com/contract");
    }

    function testFuzz_SetContractURI_UpdatesContractURI(string memory customURI) public {
        // Initially, contractURI should return base + "contract"
        assertEq(token.contractURI(), "https://example.com/contract");

        // Set custom contract URI
        vm.prank(owner);
        token.setContractURI(customURI);

        // If custom URI is not empty, it should be returned
        if (bytes(customURI).length > 0) {
            assertEq(token.contractURI(), customURI);
        } else {
            // Otherwise, fall back to default
            assertEq(token.contractURI(), "https://example.com/contract");
        }
    }

    function testFuzz_TokenData_ReturnsStoredData(bytes32 castHash, uint96 fid, address testCreator) public {
        // Bound inputs
        vm.assume(testCreator != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);
        string memory tokenURI = "https://example.com/specific-token";

        // Mint a token with URI
        vm.prank(owner);
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, fid, testCreator, tokenURI);

        // Test tokenData function returns correct data
        ICollectibleCasts.TokenData memory data = token.tokenData(tokenId);
        assertEq(data.fid, fid);
        assertEq(data.creator, testCreator);
        assertEq(data.uri, tokenURI);
    }

    function test_TokenData_ReturnsEmptyForUnmintedToken() public view {
        uint256 tokenId = uint256(keccak256("unminted"));
        ICollectibleCasts.TokenData memory data = token.tokenData(tokenId);
        assertEq(data.fid, 0);
        assertEq(data.creator, address(0));
        assertEq(data.uri, "");
    }

    function testFuzz_IsMinted_ReturnsTrueForMintedToken(bytes32 castHash, uint96 fid, address testCreator) public {
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minter);

        vm.prank(minter);
        token.mint(alice, castHash, fid, testCreator);

        assertTrue(token.isMinted(tokenId));
        assertTrue(token.isMinted(castHash));
    }

    function testFuzz_IsMinted_ReturnsFalseForUnmintedToken(uint256 tokenId) public view {
        assertFalse(token.isMinted(tokenId));
    }

    function testFuzz_IsMintedWithCastHash_ReturnsFalseForUnmintedToken(bytes32 castHash) public view {
        assertFalse(token.isMinted(castHash));
    }

    function test_IsMinted_ReturnsTrueEvenAfterTransfer() public {
        bytes32 castHash = keccak256("transferTest");
        uint256 tokenId = uint256(castHash);
        uint96 fid = 123;

        vm.prank(owner);
        token.allowMinter(minter);
        vm.prank(minter);
        token.mint(alice, castHash, fid, creator);

        assertTrue(token.isMinted(tokenId));
        assertTrue(token.isMinted(castHash));

        vm.prank(alice);
        token.transferFrom(alice, bob, tokenId);

        assertTrue(token.isMinted(tokenId));
        assertTrue(token.isMinted(castHash));
    }

    function test_TokenFid_ReturnsZeroForUnmintedToken() public view {
        uint256 tokenId = uint256(keccak256("unmintedFid"));
        assertEq(token.tokenFid(tokenId), 0);
    }

    function testFuzz_Mint_CastHash(address recipient, uint96 fid, bytes32 castHash) public {
        vm.assume(recipient != address(0));
        vm.assume(castHash != bytes32(0));
        // No EOA restriction needed - using regular mint, not safeMint
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        vm.prank(owner);
        token.allowMinter(minter);

        vm.prank(minter);
        token.mint(recipient, castHash, fid, creator);

        uint256 tokenId = uint256(castHash);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.ownerOf(tokenId), recipient);
        assertEq(token.tokenFid(tokenId), fid);
    }

    function testFuzz_Mint_ZeroTokenId(address recipient, uint96 fid) public {
        vm.assume(recipient != address(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        bytes32 zeroCastHash = bytes32(0);

        vm.prank(owner);
        token.allowMinter(minter);

        vm.prank(minter);
        vm.expectRevert(ICollectibleCasts.InvalidInput.selector);
        token.mint(recipient, zeroCastHash, fid, creator);
    }

    function test_SetBaseURI_OnlyOwner(address notOwner) public {
        vm.assume(notOwner != owner);
        string memory newBaseURI = "https://newapi.example.com/";

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.setBaseURI(newBaseURI);
    }

    function testFuzz_SetBaseURI_UpdatesBaseURI(string memory newBaseURI) public {
        vm.prank(owner);
        token.setBaseURI(newBaseURI);

        string memory expectedContractURI = string.concat(newBaseURI, "contract");
        assertEq(token.contractURI(), expectedContractURI);

        bytes32 castHash = keccak256("castHash");
        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minter);
        vm.prank(minter);
        token.mint(alice, castHash, 123, creator);

        string memory expectedTokenURI;
        if (bytes(newBaseURI).length > 0) {
            expectedTokenURI = string(abi.encodePacked(newBaseURI, vm.toString(tokenId)));
        } else {
            expectedTokenURI = "";
        }
        assertEq(token.tokenURI(tokenId), expectedTokenURI);
    }

    function test_SetBaseURI_EmitsEvent() public {
        string memory newBaseURI = "https://newapi.example.com/";

        vm.expectEmit(true, false, false, true);
        emit ICollectibleCasts.BaseURISet(newBaseURI);

        vm.expectEmit(false, false, false, true);
        emit ICollectibleCasts.BatchMetadataUpdate(0, type(uint256).max);

        vm.prank(owner);
        token.setBaseURI(newBaseURI);
    }

    function test_SetBaseURI_BatchMetadataUpdate() public {
        vm.prank(owner);
        token.allowMinter(minter);

        // Mint multiple tokens
        bytes32[3] memory castHashes = [bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3))];

        for (uint256 i = 0; i < castHashes.length; i++) {
            vm.prank(minter);
            token.mint(receiver, castHashes[i], uint96(i + 1), creator);
        }

        // Check initial URIs
        for (uint256 i = 0; i < castHashes.length; i++) {
            assertEq(
                token.tokenURI(uint256(castHashes[i])),
                string.concat("https://example.com/", Strings.toString(uint256(castHashes[i])))
            );
        }

        // Update base URI and verify BatchMetadataUpdate event
        string memory newBaseURI = "https://newapi.example.com/";

        vm.expectEmit(false, false, false, true);
        emit ICollectibleCasts.BatchMetadataUpdate(0, type(uint256).max);

        vm.prank(owner);
        token.setBaseURI(newBaseURI);

        // Verify all token URIs are updated
        for (uint256 i = 0; i < castHashes.length; i++) {
            assertEq(
                token.tokenURI(uint256(castHashes[i])),
                string.concat(newBaseURI, Strings.toString(uint256(castHashes[i])))
            );
        }
    }

    function test_BatchSetTokenURIs_OnlyOwner(address notOwner) public {
        vm.assume(notOwner != owner);

        uint256[] memory tokenIds = new uint256[](1);
        string[] memory uris = new string[](1);
        tokenIds[0] = 123;
        uris[0] = "https://example.com/123";

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.setTokenURIs(tokenIds, uris);
    }

    function test_BatchSetTokenURIs_RevertsWithMismatchedArrays() public {
        uint256[] memory tokenIds = new uint256[](2);
        string[] memory uris = new string[](1);
        tokenIds[0] = 123;
        tokenIds[1] = 456;
        uris[0] = "https://example.com/123";

        vm.prank(owner);
        vm.expectRevert(ICollectibleCasts.InvalidInput.selector);
        token.setTokenURIs(tokenIds, uris);
    }

    function test_BatchSetTokenURIs_AllowsSettingForNonExistentToken() public {
        uint256[] memory tokenIds = new uint256[](1);
        string[] memory uris = new string[](1);
        tokenIds[0] = 123;
        uris[0] = "https://example.com/123";

        // Should not revert when setting URI for non-existent token
        vm.prank(owner);
        token.setTokenURIs(tokenIds, uris);

        // But tokenURI should still revert for unminted token
        vm.expectRevert();
        token.tokenURI(123);
    }

    function testFuzz_BatchSetTokenURIs_UpdatesExistingTokens(bytes32[3] memory castHashes, string[3] memory newURIs)
        public
    {
        vm.assume(castHashes[0] != bytes32(0) && castHashes[1] != bytes32(0) && castHashes[2] != bytes32(0));
        vm.assume(castHashes[0] != castHashes[1] && castHashes[0] != castHashes[2] && castHashes[1] != castHashes[2]);

        vm.prank(owner);
        token.allowMinter(minter);

        // Mint tokens
        uint256[] memory tokenIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = uint256(castHashes[i]);
            vm.prank(minter);
            token.mint(alice, castHashes[i], uint96(i + 1), creator);
        }

        // Prepare arrays for batch update
        string[] memory uris = new string[](3);
        for (uint256 i = 0; i < 3; i++) {
            uris[i] = newURIs[i];
        }

        // Expect MetadataUpdate events
        for (uint256 i = 0; i < 3; i++) {
            vm.expectEmit(true, false, false, true);
            emit ICollectibleCasts.MetadataUpdate(tokenIds[i]);
        }

        // Update URIs
        vm.prank(owner);
        token.setTokenURIs(tokenIds, uris);

        // Verify updates
        for (uint256 i = 0; i < 3; i++) {
            // When an empty URI is set, it falls back to base URI + tokenId
            if (bytes(newURIs[i]).length == 0) {
                assertEq(
                    token.tokenURI(tokenIds[i]),
                    string(abi.encodePacked("https://example.com/", vm.toString(tokenIds[i])))
                );
            } else {
                assertEq(token.tokenURI(tokenIds[i]), newURIs[i]);
            }
        }
    }

    function testFuzz_Transfer_ToZeroAddress_Reverts(address from, bytes32 castHash, uint96 fid) public {
        vm.assume(from != address(0));
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minter);
        vm.prank(minter);
        token.mint(from, castHash, fid, creator);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0)));
        token.transferFrom(from, address(0), tokenId);
    }

    function testFuzz_Transfer_Success(address from, address to, bytes32 castHash, uint96 fid) public {
        vm.assume(from != address(0) && to != address(0));
        vm.assume(from != to);
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minter);
        vm.prank(minter);
        token.mint(from, castHash, fid, creator);

        vm.prank(from);
        token.transferFrom(from, to, tokenId);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), 1);
        assertEq(token.ownerOf(tokenId), to);
    }

    function testFuzz_Transfer_NotOwner_Reverts(
        address from,
        address to,
        address notOwner,
        bytes32 castHash,
        uint96 fid
    ) public {
        vm.assume(from != address(0) && to != address(0) && notOwner != address(0));
        vm.assume(from != to && from != notOwner);
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minter);
        vm.prank(minter);
        token.mint(from, castHash, fid, creator);

        assertEq(token.ownerOf(tokenId), from);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, notOwner, tokenId));
        token.transferFrom(from, to, tokenId);
    }

    function testFuzz_SafeTransferFrom_ToContract(address from, bytes32 castHash, uint96 fid) public {
        vm.assume(from != address(0) && from != address(validReceiver));
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        address testCreator = makeAddr("testCreator");
        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minter);
        vm.prank(minter);
        token.mint(from, castHash, fid, creator);

        vm.prank(from);
        token.safeTransferFrom(from, address(validReceiver), tokenId);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(address(validReceiver)), 1);
        assertEq(token.ownerOf(tokenId), address(validReceiver));
    }

    function testFuzz_SafeTransferFrom_WithData(address from, bytes32 castHash, uint96 fid, bytes memory data) public {
        vm.assume(from != address(0) && from != address(validReceiver));
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        uint256 tokenId = uint256(castHash);

        vm.prank(owner);
        token.allowMinter(minter);
        vm.prank(minter);
        token.mint(from, castHash, fid, creator);

        vm.prank(from);
        token.safeTransferFrom(from, address(validReceiver), tokenId, data);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(address(validReceiver)), 1);
        assertEq(token.ownerOf(tokenId), address(validReceiver));
    }

    // Additional tests for mint() with URI parameter
    function testFuzz_MintWithUri_Success(
        address to,
        bytes32 castHash,
        uint96 fid,
        address tokenCreator,
        string memory tokenUri
    ) public {
        vm.assume(to != address(0));
        vm.assume(castHash != bytes32(0));
        vm.assume(fid > 0);
        
        vm.prank(owner);
        token.allowMinter(minter);
        
        // Calculate expected token ID
        uint256 expectedTokenId = uint256(castHash);
        
        // Expect mint event (same as regular mint)
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.Mint(to, expectedTokenId, castHash, fid, tokenCreator);
        
        vm.prank(minter);
        token.mint(to, castHash, fid, tokenCreator, tokenUri);
        
        // Verify token was minted correctly
        assertEq(token.ownerOf(expectedTokenId), to);
        assertEq(token.tokenFid(expectedTokenId), fid);
        assertEq(token.tokenCreator(expectedTokenId), tokenCreator);
        
        // Verify URI was set
        if (bytes(tokenUri).length > 0) {
            assertEq(token.tokenURI(expectedTokenId), tokenUri);
        } else {
            // Empty URI falls back to base URI pattern
            string memory expectedUri = string(abi.encodePacked("https://example.com/", Strings.toString(expectedTokenId)));
            assertEq(token.tokenURI(expectedTokenId), expectedUri);
        }
    }

    function test_MintWithUri_EmptyString() public {
        vm.prank(owner);
        token.allowMinter(minter);
        
        bytes32 castHash = keccak256("empty-uri-test");
        string memory emptyUri = "";
        uint256 tokenId = uint256(castHash);
        
        vm.prank(minter);
        token.mint(alice, castHash, 123, alice, emptyUri);
        
        // With empty URI, should fall back to base URI + tokenId
        string memory expectedUri = string(abi.encodePacked("https://example.com/", Strings.toString(tokenId)));
        assertEq(token.tokenURI(tokenId), expectedUri);
    }

    function test_MintWithUri_VeryLongUri() public {
        vm.prank(owner);
        token.allowMinter(minter);
        
        bytes32 castHash = keccak256("long-uri-test");
        // Create a very long URI (1000+ characters)
        string memory longUri = "https://example.com/";
        for (uint i = 0; i < 49; i++) {
            longUri = string(abi.encodePacked(longUri, "verylongpathsegment/"));
        }
        
        uint256 tokenId = uint256(castHash);
        
        vm.prank(minter);
        token.mint(alice, castHash, 123, alice, longUri);
        
        assertEq(token.tokenURI(tokenId), longUri);
    }

    function test_MintWithUri_OverwritesWithSetTokenURIs() public {
        vm.prank(owner);
        token.allowMinter(minter);
        
        bytes32 castHash = keccak256("overwrite-uri-test");
        string memory initialUri = "https://initial.com/metadata.json";
        string memory newUri = "https://new.com/metadata.json";
        uint256 tokenId = uint256(castHash);
        
        // Mint with initial URI
        vm.prank(minter);
        token.mint(alice, castHash, 123, alice, initialUri);
        
        assertEq(token.tokenURI(tokenId), initialUri);
        
        // Overwrite with setTokenURIs
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        string[] memory uris = new string[](1);
        uris[0] = newUri;
        
        vm.prank(owner);
        token.setTokenURIs(tokenIds, uris);
        
        assertEq(token.tokenURI(tokenId), newUri);
    }

    function testFuzz_MintWithUri_RevertsWhenNotAllowedMinter(
        address notMinter,
        address to,
        bytes32 castHash,
        uint96 fid,
        address tokenCreator,
        string memory tokenUri
    ) public {
        vm.assume(notMinter != address(0));
        vm.assume(!token.minters(notMinter));
        vm.assume(to != address(0));
        vm.assume(castHash != bytes32(0));
        vm.assume(fid > 0);
        
        vm.prank(notMinter);
        vm.expectRevert(ICollectibleCasts.Unauthorized.selector);
        token.mint(to, castHash, fid, tokenCreator, tokenUri);
    }

    function test_MintWithUri_RevertsOnDoubleMint() public {
        vm.prank(owner);
        token.allowMinter(minter);
        
        bytes32 castHash = keccak256("double-mint-uri-test");
        string memory uri1 = "https://first.com/metadata.json";
        string memory uri2 = "https://second.com/metadata.json";
        
        // First mint succeeds
        vm.prank(minter);
        token.mint(alice, castHash, 123, alice, uri1);
        
        // Second mint with same castHash fails
        vm.prank(minter);
        vm.expectRevert(ICollectibleCasts.AlreadyMinted.selector);
        token.mint(bob, castHash, 456, bob, uri2);
    }

    function test_MintWithUri_RevertsWithZeroCastHash() public {
        vm.prank(owner);
        token.allowMinter(minter);
        
        bytes32 zeroCastHash = bytes32(0);
        string memory uri = "https://example.com/metadata.json";
        
        vm.prank(minter);
        vm.expectRevert(ICollectibleCasts.InvalidInput.selector);
        token.mint(alice, zeroCastHash, 123, alice, uri);
    }

    function testFuzz_MintWithUri_RevertsWithZeroFid(
        address to,
        bytes32 castHash,
        address tokenCreator,
        string memory tokenUri
    ) public {
        vm.assume(to != address(0));
        vm.assume(castHash != bytes32(0));
        
        vm.prank(owner);
        token.allowMinter(minter);
        
        vm.prank(minter);
        vm.expectRevert(ICollectibleCasts.InvalidFid.selector);
        token.mint(to, castHash, 0, tokenCreator, tokenUri);
    }
}
