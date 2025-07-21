// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CollectibleCasts} from "../../src/CollectibleCasts.sol";
import {ICollectibleCasts} from "../../src/interfaces/ICollectibleCasts.sol";
import {MockMetadata} from "../mocks/MockMetadata.sol";

contract CollectibleCastsMetadataEventsTest is Test {
    CollectibleCasts public token;
    MockMetadata public metadataModule;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public tokenId = 1;
    uint256 public fromTokenId = 1;
    uint256 public toTokenId = 10;

    function setUp() public {
        vm.prank(owner);
        token = new CollectibleCasts(owner, "https://example.com/");

        // Set up metadata module with reference to the NFT contract
        metadataModule = new MockMetadata(address(token));
    }

    // emitMetadataUpdate tests

    function test_EmitMetadataUpdate_ByOwner() public {
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.MetadataUpdate(tokenId);

        vm.prank(owner);
        token.emitMetadataUpdate(tokenId);
    }

    function test_EmitMetadataUpdate_ByMetadataModule() public {
        // First set the metadata module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.MetadataUpdate(tokenId);

        vm.prank(address(metadataModule));
        token.emitMetadataUpdate(tokenId);
    }

    function test_EmitMetadataUpdate_RevertsWhenUnauthorized() public {
        vm.expectRevert(ICollectibleCasts.Unauthorized.selector);
        vm.prank(alice);
        token.emitMetadataUpdate(tokenId);
    }

    function test_EmitMetadataUpdate_RevertsWhenNotOwnerOrModule() public {
        // Set metadata module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        // Try as unauthorized address
        vm.expectRevert(ICollectibleCasts.Unauthorized.selector);
        vm.prank(bob);
        token.emitMetadataUpdate(tokenId);
    }

    function testFuzz_EmitMetadataUpdate_ByOwner(uint256 _tokenId) public {
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.MetadataUpdate(_tokenId);

        vm.prank(owner);
        token.emitMetadataUpdate(_tokenId);
    }

    // emitBatchMetadataUpdate tests

    function test_EmitBatchMetadataUpdate_ByOwner() public {
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.BatchMetadataUpdate(fromTokenId, toTokenId);

        vm.prank(owner);
        token.emitBatchMetadataUpdate(fromTokenId, toTokenId);
    }

    function test_EmitBatchMetadataUpdate_ByMetadataModule() public {
        // First set the metadata module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.BatchMetadataUpdate(fromTokenId, toTokenId);

        vm.prank(address(metadataModule));
        token.emitBatchMetadataUpdate(fromTokenId, toTokenId);
    }

    function test_EmitBatchMetadataUpdate_RevertsWhenUnauthorized() public {
        vm.expectRevert(ICollectibleCasts.Unauthorized.selector);
        vm.prank(alice);
        token.emitBatchMetadataUpdate(fromTokenId, toTokenId);
    }

    function test_EmitBatchMetadataUpdate_AllTokens() public {
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.BatchMetadataUpdate(0, type(uint256).max);

        vm.prank(owner);
        token.emitBatchMetadataUpdate(0, type(uint256).max);
    }

    function testFuzz_EmitBatchMetadataUpdate_ByOwner(uint256 _fromTokenId, uint256 _toTokenId) public {
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.BatchMetadataUpdate(_fromTokenId, _toTokenId);

        vm.prank(owner);
        token.emitBatchMetadataUpdate(_fromTokenId, _toTokenId);
    }

    // emitContractURIUpdated tests

    function test_EmitContractURIUpdated_ByOwner() public {
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.ContractURIUpdated();

        vm.prank(owner);
        token.emitContractURIUpdated();
    }

    function test_EmitContractURIUpdated_ByMetadataModule() public {
        // First set the metadata module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.ContractURIUpdated();

        vm.prank(address(metadataModule));
        token.emitContractURIUpdated();
    }

    function test_EmitContractURIUpdated_RevertsWhenUnauthorized() public {
        vm.expectRevert(ICollectibleCasts.Unauthorized.selector);
        vm.prank(alice);
        token.emitContractURIUpdated();
    }

    // Test with no metadata module set

    function test_EmitMetadataUpdate_ByOwner_NoModuleSet() public {
        // Ensure no module is set
        assertEq(address(token.metadata()), address(0));

        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.MetadataUpdate(tokenId);

        vm.prank(owner);
        token.emitMetadataUpdate(tokenId);
    }

    function test_EmitBatchMetadataUpdate_ByOwner_NoModuleSet() public {
        // Ensure no module is set
        assertEq(address(token.metadata()), address(0));

        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.BatchMetadataUpdate(fromTokenId, toTokenId);

        vm.prank(owner);
        token.emitBatchMetadataUpdate(fromTokenId, toTokenId);
    }

    function test_EmitContractURIUpdated_ByOwner_NoModuleSet() public {
        // Ensure no module is set
        assertEq(address(token.metadata()), address(0));

        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.ContractURIUpdated();

        vm.prank(owner);
        token.emitContractURIUpdated();
    }

    // Test after ownership transfer

    function test_EmitMetadataUpdate_AfterOwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");

        // Transfer ownership (two-step)
        vm.prank(owner);
        token.transferOwnership(newOwner);
        vm.prank(newOwner);
        token.acceptOwnership();

        // Old owner should not be able to emit
        vm.expectRevert(ICollectibleCasts.Unauthorized.selector);
        vm.prank(owner);
        token.emitMetadataUpdate(tokenId);

        // New owner should be able to emit
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.MetadataUpdate(tokenId);

        vm.prank(newOwner);
        token.emitMetadataUpdate(tokenId);
    }

    // Test module change

    function test_EmitMetadataUpdate_AfterModuleChange() public {
        MockMetadata newModule = new MockMetadata(address(token));

        // Set initial module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        // Change module
        vm.prank(owner);
        token.setMetadataModule(address(newModule));

        // Old module should not be able to emit
        vm.expectRevert(ICollectibleCasts.Unauthorized.selector);
        vm.prank(address(metadataModule));
        token.emitMetadataUpdate(tokenId);

        // New module should be able to emit
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.MetadataUpdate(tokenId);

        vm.prank(address(newModule));
        token.emitMetadataUpdate(tokenId);
    }

    // Test when paused

    function test_EmitMetadataUpdate_WorksWhenPaused() public {
        // Pause the contract
        vm.prank(owner);
        token.pause();

        // Should still work for owner
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.MetadataUpdate(tokenId);

        vm.prank(owner);
        token.emitMetadataUpdate(tokenId);
    }

    function test_EmitBatchMetadataUpdate_WorksWhenPaused() public {
        // Pause the contract
        vm.prank(owner);
        token.pause();

        // Should still work for owner
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.BatchMetadataUpdate(fromTokenId, toTokenId);

        vm.prank(owner);
        token.emitBatchMetadataUpdate(fromTokenId, toTokenId);
    }

    function test_EmitContractURIUpdated_WorksWhenPaused() public {
        // Pause the contract
        vm.prank(owner);
        token.pause();

        // Should still work for owner
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.ContractURIUpdated();

        vm.prank(owner);
        token.emitContractURIUpdated();
    }

    // Test module removed

    function test_EmitMetadataUpdate_AfterModuleRemoved() public {
        // Set module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        // Remove module
        vm.prank(owner);
        token.setMetadataModule(address(0));

        // Module should not be able to emit
        vm.expectRevert(ICollectibleCasts.Unauthorized.selector);
        vm.prank(address(metadataModule));
        token.emitMetadataUpdate(tokenId);

        // Owner should still be able to emit
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.MetadataUpdate(tokenId);

        vm.prank(owner);
        token.emitMetadataUpdate(tokenId);
    }

    // Tests with actual callback functions from MockMetadata

    function test_UpdateTokenMetadata_CallbackFromModule() public {
        // Set the metadata module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        // Expect the event
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.MetadataUpdate(42);

        // Call the function on metadata module that triggers callback
        metadataModule.updateTokenMetadata(42);
    }

    function test_UpdateBatchMetadata_CallbackFromModule() public {
        // Set the metadata module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        // Expect the event
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.BatchMetadataUpdate(100, 200);

        // Call the function on metadata module that triggers callback
        metadataModule.updateBatchMetadata(100, 200);
    }

    function test_UpdateContractMetadata_CallbackFromModule() public {
        // Set the metadata module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        // Expect the event
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.ContractURIUpdated();

        // Call the function on metadata module that triggers callback
        metadataModule.updateContractMetadata();
    }

    function test_UpdateAllMetadata_CallbackFromModule() public {
        // Set the metadata module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        // Expect all three events in order
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.MetadataUpdate(1);
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.BatchMetadataUpdate(10, 20);
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.ContractURIUpdated();

        // Call the function that triggers all callbacks
        metadataModule.updateAllMetadata(1, 10, 20);
    }

    function test_UpdateTokenMetadata_CallbackFailsWhenModuleNotSet() public {
        // Don't set the metadata module

        // Should revert because metadataModule is not authorized
        vm.expectRevert(ICollectibleCasts.Unauthorized.selector);
        metadataModule.updateTokenMetadata(42);
    }

    function test_UpdateTokenMetadata_CallbackFailsAfterModuleRemoved() public {
        // Set the metadata module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        // Remove the module
        vm.prank(owner);
        token.setMetadataModule(address(0));

        // Should revert because metadataModule is no longer authorized
        vm.expectRevert(ICollectibleCasts.Unauthorized.selector);
        metadataModule.updateTokenMetadata(42);
    }

    function test_UpdateTokenMetadata_CallbackWorksFromDifferentCallers() public {
        // Deploy a new MockMetadata that anyone can call
        MockMetadata publicMetadata = new MockMetadata(address(token));

        // Set it as the metadata module
        vm.prank(owner);
        token.setMetadataModule(address(publicMetadata));

        // Alice calls the metadata module, which then calls back to CollectibleCasts
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.MetadataUpdate(123);

        vm.prank(alice);
        publicMetadata.updateTokenMetadata(123);
    }

    function testFuzz_UpdateTokenMetadata_CallbackFromModule(uint256 _tokenId) public {
        // Set the metadata module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        // Expect the event
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.MetadataUpdate(_tokenId);

        // Call the function on metadata module that triggers callback
        metadataModule.updateTokenMetadata(_tokenId);
    }

    function testFuzz_UpdateBatchMetadata_CallbackFromModule(uint256 _fromTokenId, uint256 _toTokenId) public {
        // Set the metadata module
        vm.prank(owner);
        token.setMetadataModule(address(metadataModule));

        // Expect the event
        vm.expectEmit(true, true, true, true);
        emit ICollectibleCasts.BatchMetadataUpdate(_fromTokenId, _toTokenId);

        // Call the function on metadata module that triggers callback
        metadataModule.updateBatchMetadata(_fromTokenId, _toTokenId);
    }
}
