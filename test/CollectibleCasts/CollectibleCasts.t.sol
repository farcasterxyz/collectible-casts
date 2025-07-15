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
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract CollectibleCastsTest is TestSuiteSetup {
    CollectibleCasts public token;
    MockERC721Receiver public validReceiver;
    MockNonERC721Receiver public invalidReceiver;

    function setUp() public override {
        super.setUp();
        token = new CollectibleCasts(address(this), "https://example.com/");
        validReceiver = new MockERC721Receiver();
        invalidReceiver = new MockNonERC721Receiver();
    }

    function testFuzz_AllowMinter_OnlyOwner(address minterAddr) public {
        // Test that owner can allow minter
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        assertTrue(token.minters(minterAddr));
    }

    function testFuzz_AllowMinter_RevertsWhenNotOwner(address minterAddr, address notOwner) public {
        // Ensure notOwner is different from the actual owner
        vm.assume(notOwner != token.owner());

        // Test that non-owner cannot allow minter
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.allowMinter(minterAddr);
    }

    function testFuzz_AllowMinter_EmitsEvent(address minterAddr) public {
        vm.expectEmit(true, false, false, true);
        emit ICollectibleCasts.MinterAllowed(minterAddr);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);
    }

    function testFuzz_DenyMinter_OnlyOwner(address minterAddr) public {
        // First allow the minter
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        assertTrue(token.minters(minterAddr));

        // Test that owner can deny minter
        vm.prank(token.owner());
        token.denyMinter(minterAddr);
        assertFalse(token.minters(minterAddr));
    }

    function testFuzz_DenyMinter_RevertsWhenNotOwner(address minterAddr, address notOwner) public {
        // Ensure notOwner is different from the actual owner
        vm.assume(notOwner != token.owner());

        // Test that non-owner cannot deny minter
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.denyMinter(minterAddr);
    }

    function testFuzz_DenyMinter_EmitsEvent(address minterAddr) public {
        // First allow the minter
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Then deny with event
        vm.expectEmit(true, false, false, true);
        emit ICollectibleCasts.MinterDenied(minterAddr);

        vm.prank(token.owner());
        token.denyMinter(minterAddr);
    }

    function testFuzz_Constructor_SetsOwner(address owner) public {
        vm.assume(owner != address(0));
        vm.prank(owner);
        CollectibleCasts newToken = new CollectibleCasts(owner, "https://example.com/");

        assertEq(newToken.owner(), owner);
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
        address creator
    ) public {
        // Ensure notMinter is not allowed
        vm.assume(!token.minters(notMinter));
        vm.assume(recipient != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        vm.prank(notMinter);
        vm.expectRevert(ICollectibleCasts.Unauthorized.selector);
        token.mint(recipient, castHash, fid, creator);
    }

    function testFuzz_Mint_RevertsWhenFidIsZero(address recipient, bytes32 castHash) public {
        // Bound inputs
        vm.assume(recipient != address(0));
        vm.assume(castHash != bytes32(0));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        vm.prank(minterAddr);
        vm.expectRevert(ICollectibleCasts.InvalidFid.selector);
        token.mint(recipient, castHash, 0, creator);
    }

    function testFuzz_Mint_SucceedsFirstTime(address recipient, bytes32 castHash, uint96 fid) public {
        vm.assume(recipient != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max)); // FID must be non-zero
        // Ensure recipient can receive ERC721
        vm.assume(recipient.code.length == 0 || recipient == address(validReceiver));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        // Set minter
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Mint as the minter with creator
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, creator);

        // Check that the recipient received the token
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.ownerOf(tokenId), recipient);
        assertEq(token.tokenFid(tokenId), fid);
        assertEq(token.tokenCreator(tokenId), creator);
    }

    function testFuzz_Mint_EmitsEvent(address recipient, bytes32 castHash, uint96 fid) public {
        vm.assume(recipient != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max)); // FID must be non-zero
        vm.assume(recipient.code.length == 0 || recipient == address(validReceiver));

        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Expect the Mint event
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.Mint(recipient, tokenId, castHash, fid, makeAddr("creator"));

        // Mint as the minter
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, makeAddr("creator"));
    }

    function testFuzz_Mint_ToValidContract(bytes32 castHash, uint96 fid) public {
        // Bound inputs
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Mint to a contract that implements ERC721Receiver
        vm.prank(minterAddr);
        token.mint(address(validReceiver), castHash, fid, creator);

        assertEq(token.balanceOf(address(validReceiver)), 1);
        assertEq(token.ownerOf(tokenId), address(validReceiver));
        assertEq(token.tokenFid(tokenId), fid);
    }

    function testFuzz_Mint_ToInvalidContract_Succeeds(bytes32 castHash, uint96 fid) public {
        // Bound inputs
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Mint to a contract that doesn't implement ERC721Receiver
        // This succeeds because _mint is used, not _safeMint
        vm.prank(minterAddr);
        token.mint(address(invalidReceiver), castHash, fid, creator);

        // Verify the token was minted
        assertEq(token.ownerOf(tokenId), address(invalidReceiver));
        assertEq(token.balanceOf(address(invalidReceiver)), 1);
    }

    function testFuzz_Mint_ToEOA(address recipient, bytes32 castHash, uint96 fid) public {
        // Test minting to EOAs only
        vm.assume(recipient != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max)); // FID must be non-zero
        vm.assume(recipient.code.length == 0); // Only EOAs
        vm.assume(recipient != address(this)); // Not the test contract

        // Set up minter
        address minterAddr = makeAddr("minter");
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        uint256 tokenId = uint256(castHash);

        // Mint as the minter
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, makeAddr("creator"));

        // Check that the recipient received the token
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.ownerOf(tokenId), recipient);
        // Check that the FID was stored
        assertEq(token.tokenFid(tokenId), fid);
    }

    function testFuzz_Mint_MultipleUniqueCasts(bytes32[5] memory castHashes, uint96 baseFid) public {
        // Test minting multiple unique casts
        vm.assume(baseFid > 0 && baseFid < type(uint96).max - 5); // Prevent overflow and ensure non-zero

        address minterAddr = makeAddr("minter");
        address recipient = makeAddr("recipient");
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        for (uint256 i = 0; i < castHashes.length; i++) {
            // Ensure non-zero and unique cast hashes
            vm.assume(castHashes[i] != bytes32(0));
            for (uint256 j = 0; j < i; j++) {
                vm.assume(castHashes[i] != castHashes[j]);
            }

            uint256 tokenId = uint256(castHashes[i]);
            uint96 fid = uint96(baseFid + i);

            vm.prank(minterAddr);
            token.mint(recipient, castHashes[i], fid, makeAddr("creator"));

            assertEq(token.ownerOf(tokenId), recipient);
            assertEq(token.tokenFid(uint256(castHashes[i])), fid);
        }
    }

    function testFuzz_Mint_RevertsOnDoubleMint(address recipient, bytes32 castHash, uint96 fid) public {
        // Bound inputs
        vm.assume(recipient != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        vm.assume(recipient.code.length == 0); // EOA for safe transfer
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // First mint should succeed
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, creator);

        // Second mint of same cast should revert
        vm.prank(minterAddr);
        vm.expectRevert(ICollectibleCasts.AlreadyMinted.selector);
        token.mint(recipient, castHash, fid, creator);
    }

    function testFuzz_Mint_RevertsOnDoubleMintDifferentRecipients(
        address recipient1,
        address recipient2,
        bytes32 castHash,
        uint96 fid1,
        uint96 fid2
    ) public {
        vm.assume(recipient1 != address(0));
        vm.assume(recipient2 != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        fid1 = uint96(_bound(uint256(fid1), 1, type(uint96).max)); // FID must be non-zero
        fid2 = uint96(_bound(uint256(fid2), 1, type(uint96).max)); // FID must be non-zero
        // Skip addresses that might be contracts without ERC721Receiver
        vm.assume(recipient1.code.length == 0 || recipient1 == address(validReceiver));
        vm.assume(recipient2.code.length == 0 || recipient2 == address(validReceiver));

        address minterAddr = makeAddr("minter");
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // First mint should succeed
        vm.prank(minterAddr);
        token.mint(recipient1, castHash, fid1, makeAddr("creator"));

        // Second mint of same cast should revert, even to different recipient with different FID
        vm.prank(minterAddr);
        vm.expectRevert(ICollectibleCasts.AlreadyMinted.selector);
        token.mint(recipient2, castHash, fid2, makeAddr("creator"));
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

        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return zero since token doesn't exist
        assertEq(receiver, address(0));
        assertEq(royaltyAmount, 0);
    }

    function test_RoyaltyInfo_ReturnsZeroWhenCreatorIsZeroAddress() public {
        // Test royalty when creator is zero address
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("zeroCreatorToken");
        uint256 tokenId = uint256(castHash);
        uint96 fid = 123;

        // Mint token with zero address as creator
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(makeAddr("recipient"), castHash, fid, address(0));

        uint256 salePrice = 1000 ether;
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return zero since creator is zero address
        assertEq(receiver, address(0));
        assertEq(royaltyAmount, 0);
    }

    function test_RoyaltyInfo_ReturnsCreatorRoyalty() public {
        // Set up a token with a creator
        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        bytes32 castHash = keccak256("royaltyTest");
        uint256 tokenId = uint256(castHash);
        uint96 fid = 123;

        // Mint token with creator
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(makeAddr("recipient"), castHash, fid, creator);

        // Test royalty calculation
        uint256 salePrice = 1000 ether;
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return 5% to creator
        assertEq(receiver, creator);
        assertEq(royaltyAmount, salePrice * ROYALTY_BPS / BPS_DENOMINATOR); // 5%
        assertEq(royaltyAmount, 50 ether); // 5% of 1000 ether
    }

    function testFuzz_RoyaltyInfo_ReturnsCreatorRoyalty(uint256 salePrice, bytes32 castHash, address creator) public {
        salePrice = _bound(salePrice, 0, 1000000 ether);
        vm.assume(creator != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero

        // Set up a token with a creator
        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);
        uint96 fid = 123;

        // Mint token with creator
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(makeAddr("recipient"), castHash, fid, creator);

        // Test royalty calculation
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return 5% to creator
        assertEq(receiver, creator);
        assertEq(royaltyAmount, salePrice * ROYALTY_BPS / BPS_DENOMINATOR); // 5%
        assertTrue(royaltyAmount <= salePrice);
    }

    // Royalty edge case tests
    function test_RoyaltyInfo_ZeroSalePrice() public {
        // Mint a token with creator
        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        bytes32 castHash = keccak256("zeroSalePriceTest");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, creator);

        // Test with zero sale price
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, 0);

        assertEq(receiver, creator);
        assertEq(royaltyAmount, 0); // 5% of 0 is 0
    }

    function test_RoyaltyInfo_MaxSalePrice() public {
        // Mint a token with creator
        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        bytes32 castHash = keccak256("maxSalePriceTest");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, creator);

        // Test with max uint256 sale price - this should revert due to overflow
        uint256 maxPrice = type(uint256).max;

        // The royalty calculation will overflow, so we expect a revert
        vm.expectRevert(); // Arithmetic overflow
        token.royaltyInfo(tokenId, maxPrice);
    }

    function test_RoyaltyInfo_LargeSafeSalePrice() public {
        // Mint a token with creator
        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        bytes32 castHash = keccak256("largeSalePriceTest");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, creator);

        // Test with largest safe price that won't overflow
        uint256 largePrice = type(uint256).max / ROYALTY_BPS;
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, largePrice);

        assertEq(receiver, creator);
        // Calculate expected royalty
        uint256 expectedRoyalty = (largePrice * ROYALTY_BPS) / BPS_DENOMINATOR;
        assertEq(royaltyAmount, expectedRoyalty);
        assertTrue(royaltyAmount > 0);
        assertTrue(royaltyAmount < largePrice);
    }

    function test_RoyaltyInfo_SmallAmounts() public {
        // Mint a token with creator
        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        bytes32 castHash = keccak256("smallAmountTest");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, creator);

        // Test with small amounts where royalty would round down to 0
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, 199); // 5% of 199 = 9.95, rounds to 9

        assertEq(receiver, creator);
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
        address creator = makeAddr("creator");
        bytes32 castHash = keccak256("mathTest");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, creator);

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
        // Test that castHash cannot be zero
        address minterAddr = makeAddr("minter");
        bytes32 castHash = bytes32(0); // This will result in tokenId = 0

        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        vm.expectRevert(ICollectibleCasts.InvalidInput.selector);
        token.mint(makeAddr("recipient"), castHash, 123, makeAddr("creator"));
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

        vm.prank(token.owner());
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

        vm.prank(token.owner());
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
        address notOwner = makeAddr("notOwner");
        string memory newContractURI = "https://custom.com/contract-metadata";

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.setContractURI(newContractURI);
    }

    function test_SetContractURI_UpdatesContractURI() public {
        string memory customContractURI = "https://custom.com/contract-metadata";

        // Initially, contractURI should return base + "contract"
        assertEq(token.contractURI(), "https://example.com/contract");

        // Set custom contract URI
        vm.prank(token.owner());
        token.setContractURI(customContractURI);

        // Now contractURI should return the custom URI
        assertEq(token.contractURI(), customContractURI);
    }

    function test_SetContractURI_EmitsEvent() public {
        string memory customContractURI = "https://custom.com/contract-metadata";

        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.ContractURIUpdated(customContractURI);

        vm.prank(token.owner());
        token.setContractURI(customContractURI);
    }

    function test_SetContractURI_EmptyStringFallsBackToDefault() public {
        string memory customContractURI = "https://custom.com/contract-metadata";

        // Set custom contract URI
        vm.prank(token.owner());
        token.setContractURI(customContractURI);
        assertEq(token.contractURI(), customContractURI);

        // Set empty string
        vm.prank(token.owner());
        token.setContractURI("");

        // Should fall back to base + "contract"
        assertEq(token.contractURI(), "https://example.com/contract");
    }

    function testFuzz_SetContractURI_UpdatesContractURI(string memory customURI) public {
        // Initially, contractURI should return base + "contract"
        assertEq(token.contractURI(), "https://example.com/contract");

        // Set custom contract URI
        vm.prank(token.owner());
        token.setContractURI(customURI);

        // If custom URI is not empty, it should be returned
        if (bytes(customURI).length > 0) {
            assertEq(token.contractURI(), customURI);
        } else {
            // Otherwise, fall back to default
            assertEq(token.contractURI(), "https://example.com/contract");
        }
    }

    function testFuzz_TokenData_ReturnsStoredData(bytes32 castHash, uint96 fid, address creator) public {
        // Bound inputs
        vm.assume(creator != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);
        string memory tokenURI = "https://example.com/specific-token";

        // Mint a token with URI
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, fid, creator, tokenURI);

        // Test tokenData function returns correct data
        ICollectibleCasts.TokenData memory data = token.tokenData(tokenId);
        assertEq(data.fid, fid);
        assertEq(data.creator, creator);
        assertEq(data.uri, tokenURI);
    }

    function test_TokenData_ReturnsEmptyForUnmintedToken() public view {
        // Test tokenData for unminted token returns empty struct
        uint256 tokenId = uint256(keccak256("unminted"));
        ICollectibleCasts.TokenData memory data = token.tokenData(tokenId);
        assertEq(data.fid, 0);
        assertEq(data.creator, address(0));
        assertEq(data.uri, "");
    }

    // isMinted tests
    function test_IsMinted_ReturnsFalseForUnmintedToken() public view {
        uint256 tokenId = uint256(keccak256("unmintedToken"));
        assertFalse(token.isMinted(tokenId));
    }

    function test_IsMintedWithCastHash_ReturnsFalseForUnmintedToken() public view {
        bytes32 castHash = keccak256("unmintedCastHash");
        assertFalse(token.isMinted(castHash));
    }

    function testFuzz_IsMinted_ReturnsTrueForMintedToken(bytes32 castHash, uint96 fid, address creator) public {
        // Bound inputs
        vm.assume(castHash != bytes32(0));
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);

        // Allow minter
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Mint token
        vm.prank(minterAddr);
        token.mint(alice, castHash, fid, creator);

        // Both functions should return true for minted token
        assertTrue(token.isMinted(tokenId));
        assertTrue(token.isMinted(castHash));
    }

    function testFuzz_IsMinted_ReturnsFalseForUnmintedToken(uint256 tokenId) public view {
        // Any unminted token should return false
        assertFalse(token.isMinted(tokenId));
    }

    function testFuzz_IsMintedWithCastHash_ReturnsFalseForUnmintedToken(bytes32 castHash) public view {
        // Any unminted castHash should return false
        assertFalse(token.isMinted(castHash));
    }

    function test_IsMinted_ReturnsTrueEvenAfterTransfer() public {
        bytes32 castHash = keccak256("transferTest");
        uint256 tokenId = uint256(castHash);
        uint96 fid = 123;
        address creator = makeAddr("creator");
        address recipient1 = alice;
        address recipient2 = bob;

        // Mint token
        address minterAddr = makeAddr("minter");
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(recipient1, castHash, fid, creator);

        // Verify it's minted
        assertTrue(token.isMinted(tokenId));
        assertTrue(token.isMinted(castHash));

        // Transfer the token
        vm.prank(recipient1);
        token.transferFrom(recipient1, recipient2, tokenId);

        // Should still return true after transfer
        assertTrue(token.isMinted(tokenId));
        assertTrue(token.isMinted(castHash));
    }

    function test_TokenFid_ReturnsZeroForUnmintedToken() public view {
        // Test tokenFid for unminted token returns 0
        uint256 tokenId = uint256(keccak256("unmintedFid"));
        assertEq(token.tokenFid(tokenId), 0);
    }

    // Edge case tests
    function testFuzz_Mint_MaxTokenId(address recipient, uint96 fid) public {
        // Bound inputs
        vm.assume(recipient != address(0));
        vm.assume(recipient.code.length == 0); // EOA for safe transfer
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        bytes32 maxCastHash = bytes32(type(uint256).max);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        vm.prank(minterAddr);
        token.mint(recipient, maxCastHash, fid, creator);

        uint256 tokenId = uint256(maxCastHash);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.ownerOf(tokenId), recipient);
        assertEq(token.tokenFid(tokenId), fid);
    }

    function testFuzz_Mint_ZeroTokenId(address recipient, uint96 fid) public {
        // Test that zero castHash (resulting in tokenId 0) is rejected
        vm.assume(recipient != address(0));
        vm.assume(recipient.code.length == 0); // EOA for safe transfer
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        bytes32 zeroCastHash = bytes32(0);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        vm.prank(minterAddr);
        vm.expectRevert(ICollectibleCasts.InvalidInput.selector);
        token.mint(recipient, zeroCastHash, fid, creator);
    }

    // setBaseURI tests

    function test_SetBaseURI_OnlyOwner() public {
        address notOwner = makeAddr("notOwner");
        string memory newBaseURI = "https://newapi.example.com/";

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.setBaseURI(newBaseURI);
    }

    function testFuzz_SetBaseURI_UpdatesBaseURI(string memory newBaseURI) public {
        // Set new base URI
        vm.prank(token.owner());
        token.setBaseURI(newBaseURI);

        // Verify it affects contractURI
        // contractURI should append "contract" to the base URI
        string memory expectedContractURI = string.concat(newBaseURI, "contract");
        assertEq(token.contractURI(), expectedContractURI);

        // Verify it affects token URI when no specific URI is set
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("test");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, makeAddr("creator"));

        // For ERC721, when no specific URI is set, it appends tokenId to base URI
        // If base URI is empty, tokenURI returns empty string
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

        vm.prank(token.owner());
        token.setBaseURI(newBaseURI);
    }

    function test_SetBaseURI_BatchMetadataUpdate() public {
        // First mint some tokens
        address minterAddr = makeAddr("minter");
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Mint multiple tokens
        bytes32[3] memory castHashes = [bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3))];

        for (uint256 i = 0; i < castHashes.length; i++) {
            vm.prank(minterAddr);
            token.mint(makeAddr("recipient"), castHashes[i], uint96(i + 1), makeAddr("creator"));
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

        vm.prank(token.owner());
        token.setBaseURI(newBaseURI);

        // Verify all token URIs are updated
        for (uint256 i = 0; i < castHashes.length; i++) {
            assertEq(
                token.tokenURI(uint256(castHashes[i])),
                string.concat(newBaseURI, Strings.toString(uint256(castHashes[i])))
            );
        }
    }

    // setTokenURIs tests

    function test_BatchSetTokenURIs_OnlyOwner() public {
        address notOwner = makeAddr("notOwner");
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

        vm.prank(token.owner());
        vm.expectRevert(ICollectibleCasts.InvalidInput.selector);
        token.setTokenURIs(tokenIds, uris);
    }

    function test_BatchSetTokenURIs_AllowsSettingForNonExistentToken() public {
        uint256[] memory tokenIds = new uint256[](1);
        string[] memory uris = new string[](1);
        tokenIds[0] = 123; // Non-existent token
        uris[0] = "https://example.com/123";

        // Should not revert when setting URI for non-existent token
        vm.prank(token.owner());
        token.setTokenURIs(tokenIds, uris);

        // But tokenURI should still revert for unminted token
        vm.expectRevert();
        token.tokenURI(123);
    }

    function testFuzz_BatchSetTokenURIs_UpdatesExistingTokens(bytes32[3] memory castHashes, string[3] memory newURIs)
        public
    {
        // Ensure non-zero and unique cast hashes
        vm.assume(castHashes[0] != bytes32(0) && castHashes[1] != bytes32(0) && castHashes[2] != bytes32(0));
        vm.assume(castHashes[0] != castHashes[1] && castHashes[0] != castHashes[2] && castHashes[1] != castHashes[2]);

        address minterAddr = makeAddr("minter");
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Mint tokens
        uint256[] memory tokenIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = uint256(castHashes[i]);
            vm.prank(minterAddr);
            token.mint(alice, castHashes[i], uint96(i + 1), makeAddr("creator"));
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
        vm.prank(token.owner());
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
        // Bound inputs
        vm.assume(from != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        vm.assume(from.code.length == 0); // EOA for safe transfer
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        // Mint token
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, creator);

        // Try to transfer to zero address - should revert
        vm.prank(from);
        vm.expectRevert(); // ERC721 should revert on transfer to zero address
        token.transferFrom(from, address(0), tokenId);
    }

    function testFuzz_Transfer_Success(address from, address to, bytes32 castHash, uint96 fid) public {
        // Bound inputs
        vm.assume(from != address(0) && to != address(0));
        vm.assume(from != to);
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        vm.assume(from.code.length == 0 && to.code.length == 0); // EOAs for safe transfer
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        // Mint token
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, creator);

        // For ERC721, we transfer the entire token (no amount)
        vm.prank(from);
        token.transferFrom(from, to, tokenId);

        // Check new ownership
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
        // Bound inputs
        vm.assume(from != address(0) && to != address(0) && notOwner != address(0));
        vm.assume(from != to && from != notOwner);
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        vm.assume(from.code.length == 0 && to.code.length == 0); // EOAs for safe transfer
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        // Mint token to 'from'
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, creator);

        // Verify ownership
        assertEq(token.ownerOf(tokenId), from);

        // Try to transfer from non-owner - should revert
        vm.prank(notOwner);
        vm.expectRevert(); // ERC721 should revert when not owner/approved
        token.transferFrom(from, to, tokenId);
    }

    function testFuzz_SafeTransferFrom_ToContract(address from, bytes32 castHash, uint96 fid) public {
        // Bound inputs
        vm.assume(from != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        vm.assume(from.code.length == 0); // EOA
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        // Mint token to 'from'
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, creator);

        // Transfer to valid receiver contract
        vm.prank(from);
        token.safeTransferFrom(from, address(validReceiver), tokenId);

        // Check ownership changed
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(address(validReceiver)), 1);
        assertEq(token.ownerOf(tokenId), address(validReceiver));
    }

    function testFuzz_SafeTransferFrom_WithData(address from, bytes32 castHash, uint96 fid, bytes memory data) public {
        // Bound inputs
        vm.assume(from != address(0));
        vm.assume(castHash != bytes32(0)); // CastHash must be non-zero
        vm.assume(from.code.length == 0); // EOA
        fid = uint96(_bound(uint256(fid), 1, type(uint96).max));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        // Mint token to 'from'
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, creator);

        // Transfer to valid receiver contract with data
        vm.prank(from);
        token.safeTransferFrom(from, address(validReceiver), tokenId, data);

        // Check ownership changed
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(address(validReceiver)), 1);
        assertEq(token.ownerOf(tokenId), address(validReceiver));
    }
}
