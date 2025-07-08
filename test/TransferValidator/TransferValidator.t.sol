// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {TransferValidator} from "../../src/TransferValidator.sol";
import {ITransferValidator} from "../../src/interfaces/ITransferValidator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TransferValidatorTest is TestSuiteSetup {
    TransferValidator public validator;

    // Events to match
    event TransfersEnabled();
    event OperatorAllowed(address indexed operator);
    event OperatorRemoved(address indexed operator);

    function setUp() public override {
        super.setUp();
        validator = new TransferValidator(address(this));
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(validator.owner(), address(this));
    }

    function test_TransfersEnabled_InitiallyFalse() public view {
        assertFalse(validator.transfersEnabled());
    }

    function test_ValidateTransfer_BlocksAllWhenTransfersDisabled() public {
        address owner = makeAddr("owner");
        address operator = makeAddr("operator");
        address to = makeAddr("to");
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        // Should block ALL transfers when disabled, even owner transfers
        assertFalse(validator.validateTransfer(owner, owner, to, ids, amounts));

        // Should block even if operator is allowed
        validator.allowOperator(operator);
        assertFalse(validator.validateTransfer(operator, owner, to, ids, amounts));
    }

    function test_ValidateTransfer_AllowsOwnerWhenTransfersEnabled() public {
        address owner = makeAddr("owner");
        address to = makeAddr("to");
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        // Enable transfers
        validator.enableTransfers();

        // Owner should be able to transfer their own tokens
        bool isAllowed = validator.validateTransfer(owner, owner, to, ids, amounts);
        assertTrue(isAllowed);
    }

    function test_ValidateTransfer_RequiresOperatorAllowlistWhenTransfersEnabled() public {
        address operator = makeAddr("operator");
        address from = makeAddr("from");
        address to = makeAddr("to");
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        // Enable transfers
        validator.enableTransfers();

        // Operator not allowed - should fail
        bool isAllowed = validator.validateTransfer(operator, from, to, ids, amounts);
        assertFalse(isAllowed);

        // Allow operator
        validator.allowOperator(operator);

        // Now should succeed
        isAllowed = validator.validateTransfer(operator, from, to, ids, amounts);
        assertTrue(isAllowed);
    }

    function test_EnableTransfers_OnlyOwner() public {
        address notOwner = makeAddr("notOwner");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        validator.enableTransfers();
    }

    function test_EnableTransfers_OneWaySwitch() public {
        // Enable transfers
        validator.enableTransfers();
        assertTrue(validator.transfersEnabled());

        // Try to enable again - should revert
        vm.expectRevert(ITransferValidator.TransfersAlreadyEnabled.selector);
        validator.enableTransfers();
    }

    function test_EnableTransfers_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit TransfersEnabled();

        validator.enableTransfers();
    }

    function test_AllowOperator_OnlyOwner() public {
        address notOwner = makeAddr("notOwner");
        address operator = makeAddr("operator");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        validator.allowOperator(operator);
    }

    function test_AllowOperator_SetsAllowedStatus() public {
        address operator = makeAddr("operator");

        // Initially not allowed
        assertFalse(validator.allowedOperators(operator));

        // Allow operator
        validator.allowOperator(operator);

        // Now allowed
        assertTrue(validator.allowedOperators(operator));
    }

    function test_AllowOperator_EmitsEvent() public {
        address operator = makeAddr("operator");

        vm.expectEmit(true, false, false, true);
        emit OperatorAllowed(operator);

        validator.allowOperator(operator);
    }

    function test_RemoveOperator_OnlyOwner() public {
        address notOwner = makeAddr("notOwner");
        address operator = makeAddr("operator");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        validator.removeOperator(operator);
    }

    function test_RemoveOperator_RemovesAllowedStatus() public {
        address operator = makeAddr("operator");

        // First allow
        validator.allowOperator(operator);
        assertTrue(validator.allowedOperators(operator));

        // Then remove
        validator.removeOperator(operator);

        // No longer allowed
        assertFalse(validator.allowedOperators(operator));
    }

    function test_RemoveOperator_EmitsEvent() public {
        address operator = makeAddr("operator");

        vm.expectEmit(true, false, false, true);
        emit OperatorRemoved(operator);

        validator.removeOperator(operator);
    }

    function testFuzz_ValidateTransfer_BlocksAllWhenDisabled(address operator, address from, address to) public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        // When transfers disabled, should always return false
        bool isAllowed = validator.validateTransfer(operator, from, to, ids, amounts);
        assertFalse(isAllowed);
    }

    function testFuzz_ValidateTransfer_RespectsOperatorAllowlistWhenEnabled(
        address operator,
        address from,
        address to,
        bool isOperatorAllowed
    ) public {
        vm.assume(operator != from); // Test third-party transfers

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        // Enable transfers
        validator.enableTransfers();

        if (isOperatorAllowed) {
            validator.allowOperator(operator);
        }

        // Should respect operator allowlist for third-party transfers
        bool isAllowed = validator.validateTransfer(operator, from, to, ids, amounts);
        assertEq(isAllowed, isOperatorAllowed);
    }

    function testFuzz_ValidateTransfer_AllowsOwnerTransfersWhenEnabled(address owner, address to) public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        // Enable transfers
        validator.enableTransfers();

        // Owner should always be able to transfer their own tokens
        bool isAllowed = validator.validateTransfer(owner, owner, to, ids, amounts);
        assertTrue(isAllowed);
    }

    function testFuzz_MultipleOperators(address[3] memory operators) public {
        // Ensure unique operators
        for (uint256 i = 0; i < operators.length; i++) {
            for (uint256 j = i + 1; j < operators.length; j++) {
                vm.assume(operators[i] != operators[j]);
            }
        }

        // Allow all operators
        for (uint256 i = 0; i < operators.length; i++) {
            validator.allowOperator(operators[i]);
            assertTrue(validator.allowedOperators(operators[i]));
        }

        // Remove first operator
        validator.removeOperator(operators[0]);
        assertFalse(validator.allowedOperators(operators[0]));

        // Others should still be allowed
        for (uint256 i = 1; i < operators.length; i++) {
            assertTrue(validator.allowedOperators(operators[i]));
        }
    }
}
