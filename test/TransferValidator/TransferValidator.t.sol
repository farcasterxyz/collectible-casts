// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TransferValidator} from "../../src/TransferValidator.sol";
import {ITransferValidator} from "../../src/interfaces/ITransferValidator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TransferValidatorTest is Test {
    TransferValidator public validator;

    // Events to match
    event Paused();
    event Unpaused();

    function setUp() public {
        validator = new TransferValidator();
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(validator.owner(), address(this));
    }

    function test_ValidateTransfer_AllowsAllTransfers() public {
        address operator = makeAddr("operator");
        address from = makeAddr("from");
        address to = makeAddr("to");
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        bool isAllowed = validator.validateTransfer(operator, from, to, ids, amounts);
        assertTrue(isAllowed);
    }

    function testFuzz_ValidateTransfer_AllowsAllTransfers(
        address operator,
        address from,
        address to,
        uint256 tokenId,
        uint256 amount
    ) public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bool isAllowed = validator.validateTransfer(operator, from, to, ids, amounts);
        assertTrue(isAllowed);
    }

    function testFuzz_ValidateTransfer_AllowsMultipleTokens(
        address operator,
        address from,
        address to,
        uint8 arrayLength
    ) public {
        // Bound array length to reasonable size
        arrayLength = uint8(_bound(arrayLength, 1, 10));
        
        uint256[] memory ids = new uint256[](arrayLength);
        uint256[] memory amounts = new uint256[](arrayLength);
        
        // Fill arrays with some data
        for (uint256 i = 0; i < arrayLength; i++) {
            ids[i] = i + 1;
            amounts[i] = i + 100;
        }

        bool isAllowed = validator.validateTransfer(operator, from, to, ids, amounts);
        assertTrue(isAllowed);
    }

    function test_ValidateTransfer_AllowsZeroAddresses() public {
        // Even with zero addresses, should allow (basic implementation)
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        bool isAllowed = validator.validateTransfer(address(0), address(0), address(0), ids, amounts);
        assertTrue(isAllowed);
    }

    function test_Pause_BlocksTransfers() public {
        // Setup
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        // Initially should allow
        assertTrue(validator.validateTransfer(makeAddr("op"), makeAddr("from"), makeAddr("to"), ids, amounts));

        // Pause
        validator.pause();

        // Now should block
        assertFalse(validator.validateTransfer(makeAddr("op"), makeAddr("from"), makeAddr("to"), ids, amounts));
    }

    function test_Unpause_AllowsTransfers() public {
        // Setup
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        // Pause first
        validator.pause();
        assertFalse(validator.validateTransfer(makeAddr("op"), makeAddr("from"), makeAddr("to"), ids, amounts));

        // Unpause
        validator.unpause();

        // Should allow again
        assertTrue(validator.validateTransfer(makeAddr("op"), makeAddr("from"), makeAddr("to"), ids, amounts));
    }

    function test_Pause_OnlyOwner() public {
        address notOwner = makeAddr("notOwner");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        validator.pause();
    }

    function test_Unpause_OnlyOwner() public {
        address notOwner = makeAddr("notOwner");
        
        // Pause first as owner
        validator.pause();

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        validator.unpause();
    }

    function test_Pause_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit Paused();

        validator.pause();
    }

    function test_Unpause_EmitsEvent() public {
        // Pause first
        validator.pause();

        vm.expectEmit(false, false, false, true);
        emit Unpaused();

        validator.unpause();
    }

    function test_Paused_InitiallyFalse() public view {
        assertFalse(validator.paused());
    }

    function testFuzz_ValidateTransfer_RespectsState(
        address operator,
        address from,
        address to,
        bool isPaused
    ) public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        if (isPaused) {
            validator.pause();
        }

        bool isAllowed = validator.validateTransfer(operator, from, to, ids, amounts);
        assertEq(isAllowed, !isPaused);
    }
}