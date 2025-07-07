// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CollectibleCast} from "../../src/CollectibleCast.sol";
import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockERC1155Receiver, MockNonERC1155Receiver} from "./mocks/MockERC1155Receiver.sol";
import {MockTransferValidator} from "./mocks/MockTransferValidator.sol";

contract CollectibleCastTest is Test {
    CollectibleCast public token;
    MockERC1155Receiver public validReceiver;
    MockNonERC1155Receiver public invalidReceiver;

    function setUp() public {
        token = new CollectibleCast();
        validReceiver = new MockERC1155Receiver();
        invalidReceiver = new MockNonERC1155Receiver();
    }

    function testFuzz_SetMinter_OnlyOwner(address newMinter, address notOwner) public {
        // Ensure notOwner is different from the actual owner
        vm.assume(notOwner != token.owner());
        vm.assume(notOwner != address(0));

        // Test that owner can set minter
        vm.prank(token.owner());
        token.setMinter(newMinter);
        assertEq(token.minter(), newMinter);

        // Test that non-owner cannot set minter
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.setMinter(makeAddr("anotherMinter"));
    }

    function testFuzz_SetMinter_EmitsEvent(address firstMinter, address secondMinter) public {
        // First set
        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.MinterSet(address(0), firstMinter);

        vm.prank(token.owner());
        token.setMinter(firstMinter);

        // Second set
        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.MinterSet(firstMinter, secondMinter);

        vm.prank(token.owner());
        token.setMinter(secondMinter);
    }

    function testFuzz_Constructor_SetsOwner(address owner) public {
        // Skip zero address and this contract
        vm.assume(owner != address(0));
        vm.assume(owner != address(this));

        vm.prank(owner);
        CollectibleCast newToken = new CollectibleCast();

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

        vm.prank(notMinter);
        vm.expectRevert(ICollectibleCast.Unauthorized.selector);
        token.mint(recipient, castHash, fid, makeAddr("creator"));
    }

    function testFuzz_Mint_SucceedsFirstTime(address recipient, bytes32 castHash, uint256 fid) public {
        vm.assume(recipient != address(0));
        // Ensure recipient can receive ERC1155
        vm.assume(recipient.code.length == 0 || recipient == address(validReceiver));

        address minterAddr = makeAddr("minter");
        address creator = makeAddr("creator");
        uint256 tokenId = uint256(castHash);

        // Set minter
        token.setMinter(minterAddr);

        // Mint as the minter with creator
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, creator);

        // Check that the recipient received the token
        assertEq(token.balanceOf(recipient, tokenId), 1);
        assertEq(token.castHashToFid(castHash), fid);
        assertEq(token.tokenCreator(tokenId), creator);
    }

    function testFuzz_Mint_EmitsEvent(address recipient, bytes32 castHash, uint256 fid) public {
        vm.assume(recipient != address(0));
        vm.assume(recipient.code.length == 0 || recipient == address(validReceiver));

        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);

        token.setMinter(minterAddr);

        // Expect the CastMinted event
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCast.CastMinted(recipient, castHash, tokenId, fid);

        // Mint as the minter
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, makeAddr("creator"));
    }

    function test_Mint_ToValidContract() public {
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("cast2");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 2;

        token.setMinter(minterAddr);

        // Mint to a contract that implements ERC1155Receiver
        vm.prank(minterAddr);
        token.mint(address(validReceiver), castHash, fid, makeAddr("creator"));

        assertEq(token.balanceOf(address(validReceiver), tokenId), 1);
        assertEq(token.castHashToFid(castHash), fid);
    }

    function test_Mint_ToInvalidContract_Reverts() public {
        address minterAddr = makeAddr("minter");
        bytes32 castHash = keccak256("cast3");
        uint256 fid = 3;

        token.setMinter(minterAddr);

        // Attempt to mint to a contract that doesn't implement ERC1155Receiver
        vm.prank(minterAddr);
        vm.expectRevert(); // ERC1155 will revert
        token.mint(address(invalidReceiver), castHash, fid, makeAddr("creator"));
    }

    function testFuzz_Mint_ToEOA(address recipient, bytes32 castHash, uint256 fid) public {
        // Test minting to EOAs only
        vm.assume(recipient != address(0));
        vm.assume(recipient.code.length == 0); // Only EOAs
        vm.assume(recipient != address(this)); // Not the test contract

        // Set up minter
        address minterAddr = makeAddr("minter");
        token.setMinter(minterAddr);

        uint256 tokenId = uint256(castHash);

        // Mint as the minter
        vm.prank(minterAddr);
        token.mint(recipient, castHash, fid, makeAddr("creator"));

        // Check that the recipient received the token
        assertEq(token.balanceOf(recipient, tokenId), 1);
        // Check that the FID was stored
        assertEq(token.castHashToFid(castHash), fid);
    }

    function testFuzz_Mint_MultipleUniqueCasts(bytes32[5] memory castHashes, uint256 baseFid) public {
        // Test minting multiple unique casts
        vm.assume(baseFid < type(uint256).max - 5); // Prevent overflow

        address minterAddr = makeAddr("minter");
        address recipient = makeAddr("recipient");
        token.setMinter(minterAddr);

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
            assertEq(token.castHashToFid(castHashes[i]), fid);
        }
    }

    function test_Mint_RevertsOnDoubleMint() public {
        address minterAddr = makeAddr("minter");
        address recipient = makeAddr("recipient");
        bytes32 castHash = keccak256("duplicateCast");
        uint256 fid = 456;

        token.setMinter(minterAddr);

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
        // Skip addresses that might be contracts without ERC1155Receiver
        vm.assume(recipient1.code.length == 0 || recipient1 == address(validReceiver));
        vm.assume(recipient2.code.length == 0 || recipient2 == address(validReceiver));

        address minterAddr = makeAddr("minter");
        token.setMinter(minterAddr);

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
        token.setMetadataModule(metadataAddr);
    }

    function testFuzz_SetMetadataModule_UpdatesAddress(address metadataAddr) public {
        vm.prank(token.owner());
        token.setMetadataModule(metadataAddr);

        assertEq(token.metadataModule(), metadataAddr);
    }

    function testFuzz_SetMetadataModule_EmitsEvent(address firstMetadata, address secondMetadata) public {
        // First set
        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.MetadataModuleSet(address(0), firstMetadata);

        vm.prank(token.owner());
        token.setMetadataModule(firstMetadata);

        // Second set
        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.MetadataModuleSet(firstMetadata, secondMetadata);

        vm.prank(token.owner());
        token.setMetadataModule(secondMetadata);
    }

    // TransferValidator Tests

    function test_SetTransferValidatorModule_RevertsWhenNotOwner() public {
        address notOwner = makeAddr("notOwner");
        address validatorAddr = makeAddr("validator");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.setTransferValidatorModule(validatorAddr);
    }

    function testFuzz_SetTransferValidatorModule_UpdatesAddress(address validatorAddr) public {
        vm.prank(token.owner());
        token.setTransferValidatorModule(validatorAddr);

        assertEq(token.transferValidatorModule(), validatorAddr);
    }

    function testFuzz_SetTransferValidatorModule_EmitsEvent(address firstValidator, address secondValidator) public {
        // First set
        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.TransferValidatorModuleSet(address(0), firstValidator);

        vm.prank(token.owner());
        token.setTransferValidatorModule(firstValidator);

        // Second set
        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.TransferValidatorModuleSet(firstValidator, secondValidator);

        vm.prank(token.owner());
        token.setTransferValidatorModule(secondValidator);
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
        token.setMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, makeAddr("creator"));

        // Deploy a mock validator that denies all transfers
        MockTransferValidator validator = new MockTransferValidator(false);
        token.setTransferValidatorModule(address(validator));

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
        token.setMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, makeAddr("creator"));

        // Deploy a mock validator that allows all transfers
        MockTransferValidator validator = new MockTransferValidator(true);
        token.setTransferValidatorModule(address(validator));

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
        token.setMinter(minterAddr);
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
        token.setMinter(minterAddr);

        // Deploy a mock validator that denies all transfers
        MockTransferValidator validator = new MockTransferValidator(false);
        token.setTransferValidatorModule(address(validator));

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
        // Ensure they can receive ERC1155 tokens
        vm.assume(from.code.length == 0);
        vm.assume(to.code.length == 0);

        // Setup
        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);

        // Mint token
        token.setMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(from, castHash, fid, makeAddr("creator"));

        // Set validator
        MockTransferValidator validator = new MockTransferValidator(allowTransfer);
        token.setTransferValidatorModule(address(validator));

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
        token.setRoyaltiesModule(royaltiesModule);
    }

    function test_SetRoyaltiesModule_UpdatesModule() public {
        address royaltiesModule = makeAddr("royaltiesModule");

        vm.prank(token.owner());
        token.setRoyaltiesModule(royaltiesModule);

        assertEq(token.royaltiesModule(), royaltiesModule);
    }

    function test_SetRoyaltiesModule_EmitsEvent() public {
        address previousModule = token.royaltiesModule();
        address newModule = makeAddr("newRoyaltiesModule");

        vm.expectEmit(true, true, false, true);
        emit ICollectibleCast.RoyaltiesModuleSet(previousModule, newModule);

        vm.prank(token.owner());
        token.setRoyaltiesModule(newModule);
    }

    function test_SupportsERC2981Interface() public view {
        // ERC-2981 interface ID
        bytes4 erc2981InterfaceId = 0x2a55205a;
        assertTrue(token.supportsInterface(erc2981InterfaceId));
    }

    function test_RoyaltyInfo_ReturnsZeroWhenNoRoyaltiesModule() public {
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
        token.setRoyaltiesModule(makeAddr("royaltiesModule"));
        
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
        token.setMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(makeAddr("recipient"), castHash, fid, creator);
        
        // Set any royalties module (simplified version doesn't use it)
        vm.prank(token.owner());
        token.setRoyaltiesModule(makeAddr("royaltiesModule"));
        
        // Test royalty calculation
        uint256 salePrice = 1000 ether;
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);
        
        // Should return 5% to creator
        assertEq(receiver, creator);
        assertEq(royaltyAmount, salePrice * 500 / 10000); // 5%
    }

    function testFuzz_RoyaltyInfo_ReturnsCreatorRoyalty(
        uint256 salePrice,
        bytes32 castHash,
        address creator
    ) public {
        salePrice = _bound(salePrice, 0, 1000000 ether);
        vm.assume(creator != address(0));
        
        // Set up a token with a creator
        address minterAddr = makeAddr("minter");
        uint256 tokenId = uint256(castHash);
        uint256 fid = 123;
        
        // Mint token with creator
        token.setMinter(minterAddr);
        vm.prank(minterAddr);
        token.mint(makeAddr("recipient"), castHash, fid, creator);
        
        // Set any royalties module (simplified version doesn't use it)
        vm.prank(token.owner());
        token.setRoyaltiesModule(makeAddr("royaltiesModule"));
        
        // Test royalty calculation
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(tokenId, salePrice);
        
        // Should return 5% to creator
        assertEq(receiver, creator);
        assertEq(royaltyAmount, salePrice * 500 / 10000); // 5%
        assertTrue(royaltyAmount <= salePrice);
    }
}
