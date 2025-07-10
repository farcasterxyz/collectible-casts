// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {MockERC1155Receiver} from "../mocks/MockERC1155Receiver.sol";
import {MockNonERC1155Receiver} from "../mocks/MockNonERC1155Receiver.sol";
import {CollectibleCast} from "../../src/CollectibleCast.sol";
import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract CollectibleCastTest is TestSuiteSetup {
    CollectibleCast public token;
    MockERC1155Receiver public validReceiver;
    MockNonERC1155Receiver public invalidReceiver;

    function setUp() public override {
        super.setUp();
        token = new CollectibleCast(address(this), "https://example.com/");
        validReceiver = new MockERC1155Receiver();
        invalidReceiver = new MockNonERC1155Receiver();
    }

    function testFuzz_AllowMinter_OnlyOwner(address minterAddr, address notOwner) public {
        // Ensure notOwner is different from the actual owner
        vm.assume(notOwner != token.owner());
        vm.assume(notOwner != address(0));

        // Test that owner can allow minter
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        assertTrue(token.allowedMinters(minterAddr));

        // Test that non-owner cannot allow minter
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.allowMinter(makeAddr("anotherMinter"));
    }

    function testFuzz_AllowMinter_EmitsEvent(address minterAddr) public {
        vm.expectEmit(true, false, false, true);
        emit ICollectibleCast.MinterAllowed(minterAddr);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);
    }

    function testFuzz_DenyMinter_OnlyOwner(address minterAddr, address notOwner) public {
        // Ensure notOwner is different from the actual owner
        vm.assume(notOwner != token.owner());
        vm.assume(notOwner != address(0));

        // First allow the minter
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        assertTrue(token.allowedMinters(minterAddr));

        // Test that owner can deny minter
        vm.prank(token.owner());
        token.denyMinter(minterAddr);
        assertFalse(token.allowedMinters(minterAddr));

        // Test that non-owner cannot deny minter
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.denyMinter(makeAddr("anotherMinter"));
    }

    function testFuzz_DenyMinter_EmitsEvent(address minterAddr) public {
        // First allow the minter
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Then deny with event
        vm.expectEmit(true, false, false, true);
        emit ICollectibleCast.MinterDenied(minterAddr);

        vm.prank(token.owner());
        token.denyMinter(minterAddr);
    }

    function testFuzz_Constructor_SetsOwner(address owner) public {
        // Skip zero address and this contract
        vm.assume(owner != address(0));
        vm.assume(owner != address(this));

        vm.prank(owner);
        CollectibleCast newToken = new CollectibleCast(owner, "https://example.com/");

        assertEq(newToken.owner(), owner);
    }

    function test_SupportsERC1155Interface() public view {
        // ERC-1155 interface ID
        bytes4 erc1155InterfaceId = 0xd9b67a26;
        assertTrue(token.supportsInterface(erc1155InterfaceId));

        // ERC-165 interface ID (supportsInterface itself)
        bytes4 erc165InterfaceId = 0x01ffc9a7;
        assertTrue(token.supportsInterface(erc165InterfaceId));
    }

    function testFuzz_Mint_RevertsWhenNotAllowedMinter(
        address notMinter,
        address recipient,
        bytes32 castHash,
        uint256 fid
    ) public {
        // Ensure notMinter is not allowed
        vm.assume(!token.allowedMinters(notMinter));
        vm.assume(recipient != address(0));
        vm.assume(fid != 0); // Need non-zero FID

        vm.prank(notMinter);
        vm.expectRevert(ICollectibleCast.Unauthorized.selector);
        token.mint(recipient, castHash, fid, makeAddr("creator"), "");
    }

    function testFuzz_Mint_RevertsWhenFidIsZero(address recipient, bytes32 castHash) public {
        // Bound inputs
        vm.assume(recipient != address(0));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        vm.prank(minterAddr);
        vm.expectRevert(ICollectibleCast.InvalidFid.selector);
        token.mint(recipient, castHash, 0, creator, "");
    }

    function testFuzz_Mint_SucceedsFirstTime(address recipient, bytes32 castHash, uint256 fid) public {
        vm.assume(recipient != address(0));
        vm.assume(fid != 0); // FID must be non-zero
        // Ensure recipient can receive ERC1155
        vm.assume(recipient.code.length == 0 || recipient == address(validReceiver));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        // Set minter
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Mint as the minter with creator
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, creator, "");

        // Check that the recipient received the token
        assertEq(token.balanceOf(recipient, tokenId), 1);
        assertEq(token.tokenFid(tokenId), fid);
        assertEq(token.tokenCreator(tokenId), creator);
    }

    function testFuzz_Mint_EmitsEvent(address recipient, bytes32 castHash, uint256 fid) public {
        vm.assume(recipient != address(0));
        vm.assume(fid != 0); // FID must be non-zero
        vm.assume(recipient.code.length == 0 || recipient == address(validReceiver));

        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Expect the CastMinted event
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCast.CastMinted(recipient, castHash, tokenId, fid, makeAddr("creator"));

        // Mint as the minter
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, makeAddr("creator"), "");
    }

    function testFuzz_Mint_ToValidContract(bytes32 castHash, uint256 fid) public {
        // Bound inputs
        fid = _bound(fid, 1, type(uint256).max);

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Mint to a contract that implements ERC1155Receiver
        vm.prank(minterAddr);
        token.mint(address(validReceiver), castHash, fid, creator, "");

        assertEq(token.balanceOf(address(validReceiver), tokenId), 1);
        assertEq(token.tokenFid(tokenId), fid);
    }

    function testFuzz_Mint_ToInvalidContract_Reverts(bytes32 castHash, uint256 fid) public {
        // Bound inputs
        fid = _bound(fid, 1, type(uint256).max);

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Attempt to mint to a contract that doesn't implement ERC1155Receiver
        vm.prank(minterAddr);
        vm.expectRevert(); // ERC1155 will revert
        token.mint(address(invalidReceiver), castHash, fid, creator, "");
    }

    function testFuzz_Mint_ToEOA(address recipient, bytes32 castHash, uint256 fid) public {
        // Test minting to EOAs only
        vm.assume(recipient != address(0));
        vm.assume(fid != 0); // FID must be non-zero
        vm.assume(recipient.code.length == 0); // Only EOAs
        vm.assume(recipient != address(this)); // Not the test contract

        // Set up minter
        address minterAddr = makeAddr("minter");
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        uint256 tokenId = uint256(castHash);

        // Mint as the minter
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, makeAddr("creator"), "");

        // Check that the recipient received the token
        assertEq(token.balanceOf(recipient, tokenId), 1);
        // Check that the FID was stored
        assertEq(token.tokenFid(tokenId), fid);
    }

    function testFuzz_Mint_MultipleUniqueCasts(bytes32[5] memory castHashes, uint256 baseFid) public {
        // Test minting multiple unique casts
        vm.assume(baseFid > 0 && baseFid < type(uint256).max - 5); // Prevent overflow and ensure non-zero

        address minterAddr = makeAddr("minter");
        address recipient = makeAddr("recipient");
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        for (uint256 i = 0; i < castHashes.length; i++) {
            // Ensure unique cast hashes
            for (uint256 j = 0; j < i; j++) {
                vm.assume(castHashes[i] != castHashes[j]);
            }

            uint256 tokenId = uint256(castHashes[i]);
            uint256 fid = baseFid + i;

            vm.prank(minterAddr);
            token.mint(recipient, castHashes[i], fid, makeAddr("creator"), "");

            assertEq(token.balanceOf(recipient, tokenId), 1);
            assertEq(token.tokenFid(uint256(castHashes[i])), fid);
        }
    }

    function testFuzz_Mint_RevertsOnDoubleMint(address recipient, bytes32 castHash, uint256 fid) public {
        // Bound inputs
        vm.assume(recipient != address(0));
        vm.assume(recipient.code.length == 0); // EOA for safe transfer
        fid = _bound(fid, 1, type(uint256).max);

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // First mint should succeed
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, creator, "");

        // Second mint of same cast should revert
        vm.prank(minterAddr);
        vm.expectRevert(ICollectibleCast.AlreadyMinted.selector);
        token.mint(recipient, castHash, fid, creator, "");
    }

    function testFuzz_Mint_RevertsOnDoubleMint(
        address recipient1,
        address recipient2,
        bytes32 castHash,
        uint256 fid1,
        uint256 fid2
    ) public {
        vm.assume(recipient1 != address(0));
        vm.assume(recipient2 != address(0));
        vm.assume(fid1 != 0 && fid2 != 0); // FIDs must be non-zero
        // Skip addresses that might be contracts without ERC1155Receiver
        vm.assume(recipient1.code.length == 0 || recipient1 == address(validReceiver));
        vm.assume(recipient2.code.length == 0 || recipient2 == address(validReceiver));

        address minterAddr = makeAddr("minter");
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // First mint should succeed
        vm.prank(minterAddr);
        token.mint(recipient1, castHash, fid1, makeAddr("creator"), "");

        // Second mint of same cast should revert, even to different recipient with different FID
        vm.prank(minterAddr);
        vm.expectRevert(ICollectibleCast.AlreadyMinted.selector);
        token.mint(recipient2, castHash, fid2, makeAddr("creator"), "");
    }

    // Royalty Constants Tests

    function test_RoyaltyConstants() public view {
        assertEq(token.BPS_DENOMINATOR(), 10000);
        assertEq(token.ROYALTY_BPS(), 500);
    }

    function test_SetModule_RevertsWithInvalidModule() public {
        vm.prank(token.owner());
        vm.expectRevert(ICollectibleCast.InvalidModule.selector);
        token.setModule("invalidModule", makeAddr("someAddress"));
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
        uint256 fid = 123;

        // Mint token with zero address as creator
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(makeAddr("recipient"), castHash, fid, address(0), "");

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
        uint256 fid = 123;

        // Mint token with creator
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(makeAddr("recipient"), castHash, fid, creator, "");

        // Test royalty calculation
        uint256 salePrice = 1000 ether;
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return 5% to creator
        assertEq(receiver, creator);
        assertEq(royaltyAmount, salePrice * token.ROYALTY_BPS() / token.BPS_DENOMINATOR()); // 5%
        assertEq(royaltyAmount, 50 ether); // 5% of 1000 ether
    }

    function testFuzz_RoyaltyInfo_ReturnsCreatorRoyalty(uint256 salePrice, bytes32 castHash, address creator) public {
        salePrice = _bound(salePrice, 0, 1000000 ether);
        vm.assume(creator != address(0));

        // Set up a token with a creator
        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 123;

        // Mint token with creator
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(makeAddr("recipient"), castHash, fid, creator, "");

        // Test royalty calculation
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return 5% to creator
        assertEq(receiver, creator);
        assertEq(royaltyAmount, salePrice * token.ROYALTY_BPS() / token.BPS_DENOMINATOR()); // 5%
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
        token.mint(alice, castHash, 123, creator, "");

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
        token.mint(alice, castHash, 123, creator, "");

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
        token.mint(alice, castHash, 123, creator, "");

        // Test with largest safe price that won't overflow
        uint256 largePrice = type(uint256).max / token.ROYALTY_BPS();
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, largePrice);

        assertEq(receiver, creator);
        // Calculate expected royalty
        uint256 expectedRoyalty = (largePrice * token.ROYALTY_BPS()) / token.BPS_DENOMINATOR();
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
        token.mint(alice, castHash, 123, creator, "");

        // Test with small amounts where royalty would round down to 0
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, 199); // 5% of 199 = 9.95, rounds to 9

        assertEq(receiver, creator);
        assertEq(royaltyAmount, 9); // 199 * 500 / 10000 = 9

        // Test with very small amount
        (, royaltyAmount) = token.royaltyInfo(tokenId, 19); // 5% of 19 = 0.95, rounds to 0
        assertEq(royaltyAmount, 0);
    }

    function testFuzz_RoyaltyInfo_MathematicalCorrectness(uint256 salePrice) public {
        // Bound sale price to avoid overflow
        salePrice = _bound(salePrice, 0, type(uint256).max / token.ROYALTY_BPS());

        // Mint a token with creator
        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        bytes32 castHash = keccak256("mathTest");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, creator, "");

        // Get royalty
        (, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Verify mathematical properties
        uint256 expectedRoyalty = (salePrice * token.ROYALTY_BPS()) / token.BPS_DENOMINATOR();
        assertEq(royaltyAmount, expectedRoyalty);

        // Verify royalty is never more than 5%
        if (salePrice > 0) {
            uint256 royaltyPercentage = (royaltyAmount * token.BPS_DENOMINATOR()) / salePrice;
            assertLe(royaltyPercentage, token.ROYALTY_BPS());
        }
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

        // Test that uri returns the token-specific URI
        assertEq(token.uri(tokenId), specificURI);
    }

    function test_Uri_FallsBackToBaseURI() public {
        // Mint a token without a specific URI
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("test");
        uint256 tokenId = uint256(castHash);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, 123, makeAddr("creator"), "");

        // Test that uri returns base URI pattern
        string memory actualUri = token.uri(tokenId);
        // Note: OpenZeppelin's ERC1155 doesn't auto-append tokenId, it just returns the base URI
        // The expected behavior is to return the base URI as-is
        string memory expectedUri = "https://example.com/";
        assertEq(actualUri, expectedUri);
    }

    function test_ContractURI_ReturnsBaseURIPlusContract() public view {
        // Test that contractURI returns baseURI + "contract"
        string memory expectedUri = "https://example.com/contract";
        assertEq(token.contractURI(), expectedUri);
    }

    function testFuzz_TokenData_ReturnsStoredData(bytes32 castHash, uint256 fid, address creator) public {
        // Bound inputs
        vm.assume(creator != address(0));
        fid = _bound(fid, 1, type(uint256).max);

        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);
        string memory tokenURI = "https://example.com/specific-token";

        // Mint a token with URI
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, fid, creator, tokenURI);

        // Test tokenData function returns correct data
        ICollectibleCast.TokenData memory data = token.tokenData(tokenId);
        assertEq(data.fid, fid);
        assertEq(data.creator, creator);
        assertEq(data.uri, tokenURI);
    }

    function test_TokenData_ReturnsEmptyForUnmintedToken() public view {
        // Test tokenData for unminted token returns empty struct
        uint256 tokenId = uint256(keccak256("unminted"));
        ICollectibleCast.TokenData memory data = token.tokenData(tokenId);
        assertEq(data.fid, 0);
        assertEq(data.creator, address(0));
        assertEq(data.uri, "");
    }

    function test_TokenFid_ReturnsZeroForUnmintedToken() public view {
        // Test tokenFid for unminted token returns 0
        uint256 tokenId = uint256(keccak256("unmintedFid"));
        assertEq(token.tokenFid(tokenId), 0);
    }

    function testFuzz_Exists_ReturnsTrueForMintedToken(bytes32 castHash, uint256 fid) public {
        // Bound inputs
        fid = _bound(fid, 1, type(uint256).max);

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        // Before minting, exists should return false
        assertFalse(token.exists(tokenId));

        // Mint a token
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, fid, creator, "");

        // After minting, exists should return true
        assertTrue(token.exists(tokenId));
    }

    function test_Exists_ReturnsFalseForUnmintedToken() public view {
        // For any unminted token, exists should return false
        uint256 tokenId = uint256(keccak256("unmintedExists"));
        assertFalse(token.exists(tokenId));
    }

    // Edge case tests
    function testFuzz_Mint_MaxTokenId(address recipient, uint256 fid) public {
        // Bound inputs
        vm.assume(recipient != address(0));
        vm.assume(recipient.code.length == 0); // EOA for safe transfer
        fid = _bound(fid, 1, type(uint256).max);

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        bytes32 maxCastHash = bytes32(type(uint256).max);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        vm.prank(minterAddr);
        token.mint(recipient, maxCastHash, fid, creator, "");

        uint256 tokenId = uint256(maxCastHash);
        assertEq(token.balanceOf(recipient, tokenId), 1);
        assertEq(token.tokenFid(tokenId), fid);
        assertTrue(token.exists(tokenId));
    }

    function testFuzz_Mint_ZeroTokenId(address recipient, uint256 fid) public {
        // Bound inputs
        vm.assume(recipient != address(0));
        vm.assume(recipient.code.length == 0); // EOA for safe transfer
        fid = _bound(fid, 1, type(uint256).max);

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        bytes32 zeroCastHash = bytes32(0);

        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        vm.prank(minterAddr);
        token.mint(recipient, zeroCastHash, fid, creator, "");

        uint256 tokenId = uint256(zeroCastHash); // Should be 0
        assertEq(token.balanceOf(recipient, tokenId), 1);
        assertEq(token.tokenFid(tokenId), fid);
        assertTrue(token.exists(tokenId));
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
        token.mint(alice, castHash, 123, makeAddr("creator"), "");

        // OpenZeppelin's ERC1155 just returns the base URI as-is, doesn't append tokenId
        string memory expectedTokenURI = newBaseURI;
        assertEq(token.uri(tokenId), expectedTokenURI);
    }

    function test_SetBaseURI_EmitsEvent() public {
        string memory newBaseURI = "https://newapi.example.com/";

        vm.expectEmit(true, false, false, true);
        emit ICollectibleCast.BaseURISet(newBaseURI);

        vm.prank(token.owner());
        token.setBaseURI(newBaseURI);
    }

    // batchSetTokenURIs tests

    function test_BatchSetTokenURIs_OnlyOwner() public {
        address notOwner = makeAddr("notOwner");
        uint256[] memory tokenIds = new uint256[](1);
        string[] memory uris = new string[](1);
        tokenIds[0] = 123;
        uris[0] = "https://example.com/123";

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.batchSetTokenURIs(tokenIds, uris);
    }

    function test_BatchSetTokenURIs_RevertsWithMismatchedArrays() public {
        uint256[] memory tokenIds = new uint256[](2);
        string[] memory uris = new string[](1);
        tokenIds[0] = 123;
        tokenIds[1] = 456;
        uris[0] = "https://example.com/123";

        vm.prank(token.owner());
        vm.expectRevert(ICollectibleCast.InvalidInput.selector);
        token.batchSetTokenURIs(tokenIds, uris);
    }

    function test_BatchSetTokenURIs_RevertsForNonExistentToken() public {
        uint256[] memory tokenIds = new uint256[](1);
        string[] memory uris = new string[](1);
        tokenIds[0] = 123; // Non-existent token
        uris[0] = "https://example.com/123";

        vm.prank(token.owner());
        vm.expectRevert(ICollectibleCast.TokenDoesNotExist.selector);
        token.batchSetTokenURIs(tokenIds, uris);
    }

    function testFuzz_BatchSetTokenURIs_UpdatesExistingTokens(bytes32[3] memory castHashes, string[3] memory newURIs)
        public
    {
        // Ensure unique cast hashes
        vm.assume(castHashes[0] != castHashes[1] && castHashes[0] != castHashes[2] && castHashes[1] != castHashes[2]);

        address minterAddr = makeAddr("minter");
        vm.prank(token.owner());
        token.allowMinter(minterAddr);

        // Mint tokens
        uint256[] memory tokenIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = uint256(castHashes[i]);
            vm.prank(minterAddr);
            token.mint(alice, castHashes[i], i + 1, makeAddr("creator"), "");
        }

        // Prepare arrays for batch update
        string[] memory uris = new string[](3);
        for (uint256 i = 0; i < 3; i++) {
            uris[i] = newURIs[i];
        }

        // Expect URI events
        for (uint256 i = 0; i < 3; i++) {
            vm.expectEmit(true, true, false, true);
            emit IERC1155.URI(newURIs[i], tokenIds[i]);
        }

        // Update URIs
        vm.prank(token.owner());
        token.batchSetTokenURIs(tokenIds, uris);

        // Verify updates
        for (uint256 i = 0; i < 3; i++) {
            // When an empty URI is set, it falls back to base URI
            if (bytes(newURIs[i]).length == 0) {
                assertEq(token.uri(tokenIds[i]), "https://example.com/");
            } else {
                assertEq(token.uri(tokenIds[i]), newURIs[i]);
            }
        }
    }

    function testFuzz_Transfer_ToZeroAddress_Reverts(address from, bytes32 castHash, uint256 fid) public {
        // Bound inputs
        vm.assume(from != address(0));
        vm.assume(from.code.length == 0); // EOA for safe transfer
        fid = _bound(fid, 1, type(uint256).max);

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        // Mint token
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, creator, "");

        // Try to transfer to zero address - should revert
        vm.prank(from);
        vm.expectRevert(); // ERC1155 should revert on transfer to zero address
        token.safeTransferFrom(from, address(0), tokenId, 1, "");
    }

    function testFuzz_Transfer_ZeroAmount(address from, address to, bytes32 castHash, uint256 fid) public {
        // Bound inputs
        vm.assume(from != address(0) && to != address(0));
        vm.assume(from != to);
        vm.assume(from.code.length == 0 && to.code.length == 0); // EOAs for safe transfer
        fid = _bound(fid, 1, type(uint256).max);

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        // Mint token
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, creator, "");

        // Transfer 0 amount should succeed but not change balances
        vm.prank(from);
        token.safeTransferFrom(from, to, tokenId, 0, "");

        // Balances should be unchanged
        assertEq(token.balanceOf(from, tokenId), 1);
        assertEq(token.balanceOf(to, tokenId), 0);
    }

    function testFuzz_Transfer_MoreThanBalance_Reverts(
        address from,
        address to,
        bytes32 castHash,
        uint256 fid,
        uint256 excessAmount
    ) public {
        // Bound inputs
        vm.assume(from != address(0) && to != address(0));
        vm.assume(from != to);
        vm.assume(from.code.length == 0 && to.code.length == 0); // EOAs for safe transfer
        fid = _bound(fid, 1, type(uint256).max);
        excessAmount = _bound(excessAmount, 2, type(uint256).max); // At least 2 (more than balance of 1)

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        // Mint token (balance = 1)
        vm.prank(token.owner());
        token.allowMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, creator, "");

        // Verify balance is 1
        assertEq(token.balanceOf(from, tokenId), 1);

        // Try to transfer more than balance - should revert
        vm.prank(from);
        vm.expectRevert(); // ERC1155 should revert with insufficient balance
        token.safeTransferFrom(from, to, tokenId, excessAmount, "");
    }
}
