// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {MockERC1155Receiver} from "../mocks/MockERC1155Receiver.sol";
import {MockNonERC1155Receiver} from "../mocks/MockNonERC1155Receiver.sol";
import {CollectibleCast} from "../../src/CollectibleCast.sol";
import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";
import {Royalties} from "../../src/Royalties.sol";
import {TransferValidator} from "../../src/TransferValidator.sol";
import {Metadata} from "../../src/Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract CollectibleCastTest is TestSuiteSetup {
    CollectibleCast public token;
    MockERC1155Receiver public validReceiver;
    MockNonERC1155Receiver public invalidReceiver;

    function setUp() public override {
        super.setUp();
        token = new CollectibleCast(
            address(this),
            address(0),
            address(0),
            address(0),
            address(0)
        );
        validReceiver = new MockERC1155Receiver();
        invalidReceiver = new MockNonERC1155Receiver();
    }

    function testFuzz_SetMinter_OnlyOwner(address newMinter, address notOwner) public {
        // Ensure notOwner is different from the actual owner
        vm.assume(notOwner != token.owner());
        vm.assume(notOwner != address(0));

        // Test that owner can set minter
        vm.prank(token.owner());
        token.setModule("minter", newMinter);
        assertEq(token.minter(), newMinter);

        // Test that non-owner cannot set minter
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.setModule("minter", makeAddr("anotherMinter"));
    }

    function testFuzz_SetMinter_EmitsEvent(address firstMinter, address secondMinter) public {
        // First set
        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.SetMinter(address(0), firstMinter);

        vm.prank(token.owner());
        token.setModule("minter", firstMinter);

        // Second set
        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.SetMinter(firstMinter, secondMinter);

        vm.prank(token.owner());
        token.setModule("minter", secondMinter);
    }

    function testFuzz_Constructor_SetsOwner(address owner) public {
        // Skip zero address and this contract
        vm.assume(owner != address(0));
        vm.assume(owner != address(this));

        vm.prank(owner);
        CollectibleCast newToken = new CollectibleCast(
            owner,
            address(0),
            address(0),
            address(0),
            address(0)
        );

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

    function testFuzz_Mint_RevertsWhenNotMinter(address notMinter, address recipient, bytes32 castHash, uint256 fid)
        public
    {
        // Ensure notMinter is not the actual minter
        vm.assume(notMinter != token.minter());
        vm.assume(recipient != address(0));
        vm.assume(fid != 0); // Need non-zero FID

        vm.prank(notMinter);
        vm.expectRevert(ICollectibleCast.Unauthorized.selector);
        token.mint(recipient, castHash, fid, makeAddr("creator"));
    }

    function test_Mint_RevertsWhenFidIsZero() public {
        address minterAddr = makeAddr("minter");
        address recipient = makeAddr("recipient");
        bytes32 castHash = keccak256("testCast");

        token.setModule("minter", minterAddr);

        vm.prank(minterAddr);
        vm.expectRevert(ICollectibleCast.InvalidFid.selector);
        token.mint(recipient, castHash, 0, makeAddr("creator"));
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
        token.setModule("minter", minterAddr);

        // Mint as the minter with creator
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, creator);

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

        token.setModule("minter", minterAddr);

        // Expect the CastMinted event
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCast.CastMinted(recipient, castHash, tokenId, fid, makeAddr("creator"));

        // Mint as the minter
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, makeAddr("creator"));
    }

    function test_Mint_ToValidContract() public {
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("cast2");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 2;

        token.setModule("minter", minterAddr);

        // Mint to a contract that implements ERC1155Receiver
        vm.prank(minterAddr);
        token.mint(address(validReceiver), castHash, fid, makeAddr("creator"));

        assertEq(token.balanceOf(address(validReceiver), tokenId), 1);
        assertEq(token.tokenFid(tokenId), fid);
    }

    function test_Mint_ToInvalidContract_Reverts() public {
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("cast3");
        uint256 fid = 3;

        token.setModule("minter", minterAddr);

        // Attempt to mint to a contract that doesn't implement ERC1155Receiver
        vm.prank(minterAddr);
        vm.expectRevert(); // ERC1155 will revert
        token.mint(address(invalidReceiver), castHash, fid, makeAddr("creator"));
    }

    function testFuzz_Mint_ToEOA(address recipient, bytes32 castHash, uint256 fid) public {
        // Test minting to EOAs only
        vm.assume(recipient != address(0));
        vm.assume(fid != 0); // FID must be non-zero
        vm.assume(recipient.code.length == 0); // Only EOAs
        vm.assume(recipient != address(this)); // Not the test contract

        // Set up minter
        address minterAddr = makeAddr("minter");
        token.setModule("minter", minterAddr);

        uint256 tokenId = uint256(castHash);

        // Mint as the minter
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, makeAddr("creator"));

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
        token.setModule("minter", minterAddr);

        for (uint256 i = 0; i < castHashes.length; i++) {
            // Ensure unique cast hashes
            for (uint256 j = 0; j < i; j++) {
                vm.assume(castHashes[i] != castHashes[j]);
            }

            uint256 tokenId = uint256(castHashes[i]);
            uint256 fid = baseFid + i;

            vm.prank(minterAddr);
            token.mint(recipient, castHashes[i], fid, makeAddr("creator"));

            assertEq(token.balanceOf(recipient, tokenId), 1);
            assertEq(token.tokenFid(uint256(castHashes[i])), fid);
        }
    }

    function test_Mint_RevertsOnDoubleMint() public {
        address minterAddr = makeAddr("minter");
        address recipient = makeAddr("recipient");
        bytes32 castHash = keccak256("duplicateCast");
        uint256 fid = 456;

        token.setModule("minter", minterAddr);

        // First mint should succeed
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, makeAddr("creator"));

        // Second mint of same cast should revert
        vm.prank(minterAddr);
        vm.expectRevert(ICollectibleCast.AlreadyMinted.selector);
        token.mint(recipient, castHash, fid, makeAddr("creator"));
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
        token.setModule("minter", minterAddr);

        // First mint should succeed
        vm.prank(minterAddr);
        token.mint(recipient1, castHash, fid1, makeAddr("creator"));

        // Second mint of same cast should revert, even to different recipient with different FID
        vm.prank(minterAddr);
        vm.expectRevert(ICollectibleCast.AlreadyMinted.selector);
        token.mint(recipient2, castHash, fid2, makeAddr("creator"));
    }

    // Module Management Tests

    function test_SetMetadataModule_RevertsWhenNotOwner() public {
        address notOwner = makeAddr("notOwner");
        address metadataAddr = makeAddr("metadata");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.setModule("metadata", metadataAddr);
    }

    function testFuzz_SetMetadataModule_UpdatesAddress(address metadataAddr) public {
        vm.prank(token.owner());
        token.setModule("metadata", metadataAddr);

        assertEq(token.metadata(), metadataAddr);
    }

    function testFuzz_SetMetadataModule_EmitsEvent(address firstMetadata, address secondMetadata) public {
        // First set
        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.SetMetadata(address(0), firstMetadata);
        vm.expectEmit(false, false, false, true);
        emit IERC1155.URI("", 0);

        vm.prank(token.owner());
        token.setModule("metadata", firstMetadata);

        // Second set
        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.SetMetadata(firstMetadata, secondMetadata);
        vm.expectEmit(false, false, false, true);
        emit IERC1155.URI("", 0);

        vm.prank(token.owner());
        token.setModule("metadata", secondMetadata);
    }

    // TransferValidator Tests

    function test_SetTransferValidatorModule_RevertsWhenNotOwner() public {
        address notOwner = makeAddr("notOwner");
        address validatorAddr = makeAddr("validator");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.setModule("transferValidator", validatorAddr);
    }

    function testFuzz_SetTransferValidatorModule_UpdatesAddress(address validatorAddr) public {
        vm.prank(token.owner());
        token.setModule("transferValidator", validatorAddr);

        assertEq(token.transferValidator(), validatorAddr);
    }

    function testFuzz_SetTransferValidatorModule_EmitsEvent(address firstValidator, address secondValidator) public {
        // First set
        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.SetTransferValidator(address(0), firstValidator);

        vm.prank(token.owner());
        token.setModule("transferValidator", firstValidator);

        // Second set
        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.SetTransferValidator(firstValidator, secondValidator);

        vm.prank(token.owner());
        token.setModule("transferValidator", secondValidator);
    }

    // Transfer Validation Integration Tests

    function test_Transfer_ChecksValidator_WhenValidatorSet() public {
        // Setup
        address minterAddr = makeAddr("minter");
        address from = makeAddr("from");
        address to = makeAddr("to");
        bytes32 castHash = keccak256("castForTransfer");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 999;

        // Mint a token first
        token.setModule("minter", minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, makeAddr("creator"));

        // Deploy a real validator with transfers disabled
        TransferValidator validator = new TransferValidator(address(this));
        token.setModule("transferValidator", address(validator));
        // transfersEnabled is false by default, so all transfers are denied

        // Attempt to transfer should revert
        vm.prank(from);
        vm.expectRevert(ICollectibleCast.TransferNotAllowed.selector);
        token.safeTransferFrom(from, to, tokenId, 1, "");
    }

    function test_Transfer_AllowedWhenValidatorAllows() public {
        // Setup
        address minterAddr = makeAddr("minter");
        address from = makeAddr("from");
        address to = makeAddr("to");
        bytes32 castHash = keccak256("castForTransfer2");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 1000;

        // Mint a token first
        token.setModule("minter", minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, makeAddr("creator"));

        // Deploy a real validator with transfers enabled
        TransferValidator validator = new TransferValidator(address(this));
        token.setModule("transferValidator", address(validator));
        vm.prank(validator.owner());
        validator.enableTransfers(); // Enable transfers

        // Transfer should succeed
        vm.prank(from);
        token.safeTransferFrom(from, to, tokenId, 1, "");

        // Verify transfer
        assertEq(token.balanceOf(from, tokenId), 0);
        assertEq(token.balanceOf(to, tokenId), 1);
    }

    function test_Transfer_AllowedWhenNoValidatorSet() public {
        // Setup
        address minterAddr = makeAddr("minter");
        address from = makeAddr("from");
        address to = makeAddr("to");
        bytes32 castHash = keccak256("castForTransfer3");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 1001;

        // Mint a token first
        token.setModule("minter", minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, makeAddr("creator"));

        // No validator set - transfer should succeed
        vm.prank(from);
        token.safeTransferFrom(from, to, tokenId, 1, "");

        // Verify transfer
        assertEq(token.balanceOf(from, tokenId), 0);
        assertEq(token.balanceOf(to, tokenId), 1);
    }

    function test_Mint_NotAffectedByValidator() public {
        // Setup
        address minterAddr = makeAddr("minter");
        address recipient = makeAddr("recipient");
        bytes32 castHash = keccak256("castForMintWithValidator");
        uint256 fid = 1002;

        // Set minter
        token.setModule("minter", minterAddr);

        // Deploy a real validator with transfers disabled
        TransferValidator validator = new TransferValidator(address(this));
        token.setModule("transferValidator", address(validator));
        // transfersEnabled is false by default, so all transfers are denied

        // Minting should still succeed even with restrictive validator
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, makeAddr("creator"));

        // Verify mint succeeded
        assertEq(token.balanceOf(recipient, uint256(castHash)), 1);
    }

    function testFuzz_Transfer_ChecksValidator(
        address from,
        address to,
        bytes32 castHash,
        uint256 fid,
        bool allowTransfer
    ) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);
        vm.assume(fid != 0); // FID must be non-zero
        // Ensure they can receive ERC1155 tokens
        vm.assume(from.code.length == 0);
        vm.assume(to.code.length == 0);

        // Setup
        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);

        // Mint token
        token.setModule("minter", minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, makeAddr("creator"));

        // Set validator
        TransferValidator validator = new TransferValidator(address(this));
        token.setModule("transferValidator", address(validator));
        if (allowTransfer) {
            vm.prank(validator.owner());
            validator.enableTransfers();
        }

        // Attempt transfer
        vm.prank(from);
        if (allowTransfer) {
            token.safeTransferFrom(from, to, tokenId, 1, "");
            assertEq(token.balanceOf(to, tokenId), 1);
        } else {
            vm.expectRevert(ICollectibleCast.TransferNotAllowed.selector);
            token.safeTransferFrom(from, to, tokenId, 1, "");
        }
    }

    // Royalties Module Tests

    function test_SetRoyaltiesModule_OnlyOwner() public {
        address notOwner = makeAddr("notOwner");
        address royaltiesModule = makeAddr("royaltiesModule");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.setModule("royalties", royaltiesModule);
    }

    function test_SetRoyaltiesModule_UpdatesModule() public {
        address royaltiesModule = makeAddr("royaltiesModule");

        vm.prank(token.owner());
        token.setModule("royalties", royaltiesModule);

        assertEq(token.royalties(), royaltiesModule);
    }

    function test_SetRoyaltiesModule_EmitsEvent() public {
        address previousModule = token.royalties();
        address newModule = makeAddr("newRoyaltiesModule");

        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.SetRoyalties(previousModule, newModule);

        vm.prank(token.owner());
        token.setModule("royalties", newModule);
    }

    function test_SetModule_RevertsWithInvalidModule() public {
        vm.expectRevert(ICollectibleCast.InvalidModule.selector);
        token.setModule("invalidModule", makeAddr("someAddress"));
    }

    function test_SupportsERC2981Interface() public view {
        // ERC-2981 interface ID
        bytes4 erc2981InterfaceId = 0x2a55205a;
        assertTrue(token.supportsInterface(erc2981InterfaceId));
    }

    function test_RoyaltyInfo_ReturnsZeroWhenNoRoyaltiesModule() public view {
        // Test royalty without setting module
        bytes32 castHash = keccak256("royaltyTest");
        uint256 tokenId = uint256(castHash);
        uint256 salePrice = 1000 ether;

        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return zero
        assertEq(receiver, address(0));
        assertEq(royaltyAmount, 0);
    }

    function test_RoyaltyInfo_ReturnsZeroWhenNoCreator() public {
        // Test royalty with module but no creator stored (unminted token)
        vm.prank(token.owner());
        token.setModule("royalties", makeAddr("royaltiesModule"));

        bytes32 castHash = keccak256("unmintedToken");
        uint256 tokenId = uint256(castHash);
        uint256 salePrice = 1000 ether;

        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return zero since no creator
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
        token.setModule("minter", minterAddr);
        vm.prank(minterAddr);
        token.mint(makeAddr("recipient"), castHash, fid, creator);

        // Deploy and set royalties module
        Royalties royaltiesModule = new Royalties();
        vm.prank(token.owner());
        token.setModule("royalties", address(royaltiesModule));

        // Test royalty calculation
        uint256 salePrice = 1000 ether;
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return 5% to creator
        assertEq(receiver, creator);
        assertEq(royaltyAmount, salePrice * 500 / 10000); // 5%
    }

    function testFuzz_RoyaltyInfo_ReturnsCreatorRoyalty(uint256 salePrice, bytes32 castHash, address creator) public {
        salePrice = _bound(salePrice, 0, 1000000 ether);
        vm.assume(creator != address(0));

        // Set up a token with a creator
        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 123;

        // Mint token with creator
        token.setModule("minter", minterAddr);
        vm.prank(minterAddr);
        token.mint(makeAddr("recipient"), castHash, fid, creator);

        // Deploy and set royalties module
        Royalties royaltiesModule = new Royalties();
        vm.prank(token.owner());
        token.setModule("royalties", address(royaltiesModule));

        // Test royalty calculation
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);

        // Should return 5% to creator
        assertEq(receiver, creator);
        assertEq(royaltyAmount, salePrice * 500 / 10000); // 5%
        assertTrue(royaltyAmount <= salePrice);
    }

    function test_Uri_DelegatesToMetadataModule() public {
        // Set up metadata module
        string memory baseUri = "https://api.example.com/";
        Metadata metadataModule = new Metadata(baseUri, address(this));
        vm.prank(token.owner());
        token.setModule("metadata", address(metadataModule));

        // Test that uri delegates to metadata module
        uint256 tokenId = 123;
        string memory expectedUri = string.concat(baseUri, "123");
        assertEq(token.uri(tokenId), expectedUri);
    }

    function test_Uri_ReturnsEmptyWhenNoMetadataModule() public view {
        // When no metadata module is set, should return empty string
        uint256 tokenId = 123;
        assertEq(token.uri(tokenId), "");
    }

    function test_ContractURI_DelegatesToMetadataModule() public {
        // Set up metadata module
        string memory baseUri = "https://api.example.com/";
        Metadata metadataModule = new Metadata(baseUri, address(this));
        vm.prank(token.owner());
        token.setModule("metadata", address(metadataModule));

        // Test that contractURI delegates to metadata module
        string memory expectedUri = string.concat(baseUri, "contract");
        assertEq(token.contractURI(), expectedUri);
    }

    function test_ContractURI_ReturnsEmptyWhenNoMetadataModule() public view {
        // When no metadata module is set, should return empty string
        assertEq(token.contractURI(), "");
    }

    function test_TokenData_ReturnsStoredData() public {
        // Setup
        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        bytes32 castHash = keccak256("tokenDataTest");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 12345;

        // Mint a token
        token.setModule("minter", minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, fid, creator);

        // Test tokenData function returns correct data
        ICollectibleCast.TokenData memory data = token.tokenData(tokenId);
        assertEq(data.fid, fid);
        assertEq(data.creator, creator);
    }

    function test_TokenData_ReturnsEmptyForUnmintedToken() public view {
        // Test tokenData for unminted token returns empty struct
        uint256 tokenId = uint256(keccak256("unminted"));
        ICollectibleCast.TokenData memory data = token.tokenData(tokenId);
        assertEq(data.fid, 0);
        assertEq(data.creator, address(0));
    }

    function test_TokenFid_ReturnsZeroForUnmintedToken() public view {
        // Test tokenFid for unminted token returns 0
        uint256 tokenId = uint256(keccak256("unmintedFid"));
        assertEq(token.tokenFid(tokenId), 0);
    }

    function test_Exists_ReturnsTrueForMintedToken() public {
        // Setup
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("existsTest");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 12345;

        // Before minting, exists should return false
        assertFalse(token.exists(tokenId));

        // Mint a token
        token.setModule("minter", minterAddr);
        vm.prank(minterAddr);
        token.mint(alice, castHash, fid, makeAddr("creator"));

        // After minting, exists should return true
        assertTrue(token.exists(tokenId));
    }

    function test_Exists_ReturnsFalseForUnmintedToken() public view {
        // For any unminted token, exists should return false
        uint256 tokenId = uint256(keccak256("unmintedExists"));
        assertFalse(token.exists(tokenId));
    }

    // Edge case tests
    function test_Mint_MaxTokenId() public {
        // Test minting with maximum possible token ID
        address minterAddr = makeAddr("minter");
        address recipient = makeAddr("recipient");
        bytes32 maxCastHash = bytes32(type(uint256).max);
        uint256 fid = 123;

        token.setModule("minter", minterAddr);

        vm.prank(minterAddr);
        token.mint(recipient, maxCastHash, fid, makeAddr("creator"));

        uint256 tokenId = uint256(maxCastHash);
        assertEq(token.balanceOf(recipient, tokenId), 1);
        assertEq(token.tokenFid(tokenId), fid);
        assertTrue(token.exists(tokenId));
    }

    function test_Mint_ZeroTokenId() public {
        // Test minting with zero token ID (bytes32(0))
        address minterAddr = makeAddr("minter");
        address recipient = makeAddr("recipient");
        bytes32 zeroCastHash = bytes32(0);
        uint256 fid = 123;

        token.setModule("minter", minterAddr);

        vm.prank(minterAddr);
        token.mint(recipient, zeroCastHash, fid, makeAddr("creator"));

        uint256 tokenId = uint256(zeroCastHash); // Should be 0
        assertEq(token.balanceOf(recipient, tokenId), 1);
        assertEq(token.tokenFid(tokenId), fid);
        assertTrue(token.exists(tokenId));
    }

    function test_SetModule_WithZeroAddress() public {
        // Test setting module to zero address (should be allowed - disables module)
        vm.prank(token.owner());
        token.setModule("metadata", address(0));

        assertEq(token.metadata(), address(0));
        // URI should return empty string when metadata module is zero
        assertEq(token.uri(123), "");
        assertEq(token.contractURI(), "");
    }

    function test_Transfer_ToZeroAddress_Reverts() public {
        // Test transfer to zero address (should revert)
        address minterAddr = makeAddr("minter");
        address from = makeAddr("from");
        bytes32 castHash = keccak256("transferToZero");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 123;

        // Mint token
        token.setModule("minter", minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, makeAddr("creator"));

        // Try to transfer to zero address - should revert
        vm.prank(from);
        vm.expectRevert(); // ERC1155 should revert on transfer to zero address
        token.safeTransferFrom(from, address(0), tokenId, 1, "");
    }

    function test_Transfer_ZeroAmount() public {
        // Test transferring 0 amount (should succeed but do nothing)
        address minterAddr = makeAddr("minter");
        address from = makeAddr("from");
        address to = makeAddr("to");
        bytes32 castHash = keccak256("zeroAmountTransfer");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 123;

        // Mint token
        token.setModule("minter", minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, makeAddr("creator"));

        // Transfer 0 amount should succeed but not change balances
        vm.prank(from);
        token.safeTransferFrom(from, to, tokenId, 0, "");

        // Balances should be unchanged
        assertEq(token.balanceOf(from, tokenId), 1);
        assertEq(token.balanceOf(to, tokenId), 0);
    }

    function test_Transfer_MoreThanBalance_Reverts() public {
        // Test transferring more than owned balance
        address minterAddr = makeAddr("minter");
        address from = makeAddr("from");
        address to = makeAddr("to");
        bytes32 castHash = keccak256("transferMoreThanBalance");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 123;

        // Mint token (balance = 1)
        token.setModule("minter", minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, makeAddr("creator"));

        // Try to transfer more than balance - should revert
        vm.prank(from);
        vm.expectRevert(); // ERC1155 should revert
        token.safeTransferFrom(from, to, tokenId, 2, "");
    }
}
