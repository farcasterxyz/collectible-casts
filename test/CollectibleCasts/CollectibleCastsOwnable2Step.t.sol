// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CollectibleCasts} from "../../src/CollectibleCasts.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract CollectibleCastsOwnable2StepTest is TestSuiteSetup {
    CollectibleCasts public token;
    
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public override {
        super.setUp();
        token = new CollectibleCasts(address(this), "https://example.com/");
    }

    // Test two-step ownership transfer
    function testFuzz_TransferOwnership_TwoStep(address newOwner) public {
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != address(this));
        
        // Step 1: Initiate transfer
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferStarted(address(this), newOwner);
        
        token.transferOwnership(newOwner);
        
        // Verify state after initiation
        assertEq(token.owner(), address(this), "Owner should not change yet");
        assertEq(token.pendingOwner(), newOwner, "Pending owner should be set");
        
        // Step 2: Accept ownership
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(this), newOwner);
        
        vm.prank(newOwner);
        token.acceptOwnership();
        
        // Verify final state
        assertEq(token.owner(), newOwner, "Owner should be updated");
        assertEq(token.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    // Test that only pending owner can accept
    function testFuzz_AcceptOwnership_RevertsIfNotPendingOwner(address notPendingOwner) public {
        vm.assume(notPendingOwner != address(0));
        vm.assume(notPendingOwner != token.pendingOwner());
        
        // First set a pending owner
        address newOwner = makeAddr("newOwner");
        token.transferOwnership(newOwner);
        
        // Try to accept from wrong address
        vm.prank(notPendingOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notPendingOwner));
        token.acceptOwnership();
    }

    // Test renouncing ownership
    function test_RenounceOwnership() public {
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(this), address(0));
        
        token.renounceOwnership();
        
        assertEq(token.owner(), address(0), "Owner should be zero address");
        assertEq(token.pendingOwner(), address(0), "Pending owner should be zero");
    }

    // Test that renouncing clears pending owner
    function test_RenounceOwnership_ClearsPendingOwner() public {
        address newOwner = makeAddr("newOwner");
        token.transferOwnership(newOwner);
        
        assertEq(token.pendingOwner(), newOwner, "Pending owner should be set");
        
        token.renounceOwnership();
        
        assertEq(token.owner(), address(0), "Owner should be zero address");
        assertEq(token.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    // Test transferring to zero address
    function test_TransferOwnership_AllowsZeroAddress() public {
        // Ownable2Step allows initiating transfer to zero address
        // This is effectively the same as renouncing, but requires accept
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferStarted(address(this), address(0));
        
        token.transferOwnership(address(0));
        
        assertEq(token.pendingOwner(), address(0), "Pending owner should be zero");
        assertEq(token.owner(), address(this), "Current owner should not change");
    }

    // Test overwriting pending owner
    function testFuzz_TransferOwnership_OverwritesPendingOwner(address firstNewOwner, address secondNewOwner) public {
        vm.assume(firstNewOwner != address(0));
        vm.assume(secondNewOwner != address(0));
        vm.assume(firstNewOwner != secondNewOwner);
        
        // First transfer
        token.transferOwnership(firstNewOwner);
        assertEq(token.pendingOwner(), firstNewOwner);
        
        // Second transfer overwrites
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferStarted(address(this), secondNewOwner);
        
        token.transferOwnership(secondNewOwner);
        assertEq(token.pendingOwner(), secondNewOwner);
        
        // First owner can no longer accept
        vm.prank(firstNewOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, firstNewOwner));
        token.acceptOwnership();
    }

    // Test that only owner can transfer ownership
    function testFuzz_TransferOwnership_OnlyOwner(address nonOwner, address newOwner) public {
        vm.assume(nonOwner != address(0));
        vm.assume(nonOwner != address(this));
        vm.assume(newOwner != address(0));
        
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        token.transferOwnership(newOwner);
    }

    // Test that only owner can renounce
    function testFuzz_RenounceOwnership_OnlyOwner(address nonOwner) public {
        vm.assume(nonOwner != address(0));
        vm.assume(nonOwner != address(this));
        
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        token.renounceOwnership();
    }

    // Test ownership functions after ownership is renounced
    function test_OwnershipFunctions_AfterRenounce() public {
        token.renounceOwnership();
        
        // All owner functions should revert
        address minter = makeAddr("minter");
        
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        token.allowMinter(minter);
        
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        token.denyMinter(minter);
        
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        token.setBaseURI("test");
        
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        token.pause();
    }

    // Test ownership transfer maintains contract functionality
    function testFuzz_OwnershipTransfer_MaintainsFunctionality(address newOwner) public {
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != address(this));
        
        // Allow a minter before transfer
        address minter = makeAddr("minter");
        token.allowMinter(minter);
        
        // Transfer ownership
        token.transferOwnership(newOwner);
        vm.prank(newOwner);
        token.acceptOwnership();
        
        // Old owner can't perform owner functions
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        token.allowMinter(makeAddr("newMinter"));
        
        // New owner can perform owner functions
        vm.prank(newOwner);
        token.allowMinter(makeAddr("newMinter"));
        
        // Previously allowed minter can still mint
        vm.prank(minter);
        token.mint(alice, keccak256("test"), 123, alice);
    }
}