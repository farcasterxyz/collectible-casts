// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ITransferValidator} from "./interfaces/ITransferValidator.sol";

contract TransferValidator is ITransferValidator, Ownable2Step {
    // One-way switch to enable transfers (disabled at launch)
    bool public transfersEnabled;

    // Operator allowlist for marketplace curation
    mapping(address => bool) public allowedOperators;

    // Custom errors
    error TransfersAlreadyEnabled();
    error TransfersDisabled();

    // Events
    event TransfersEnabled();
    event OperatorAllowed(address indexed operator);
    event OperatorRemoved(address indexed operator);

    constructor() Ownable(msg.sender) {}

    function validateTransfer(
        address operator,
        address,
        address,
        uint256[] calldata,
        uint256[] calldata
    ) external view override returns (bool) {
        // If transfers are not enabled, only allowed operators can transfer
        if (!transfersEnabled) {
            return allowedOperators[operator];
        }
        // If transfers are enabled, anyone can transfer
        return true;
    }

    // One-way switch to enable transfers
    function enableTransfers() external onlyOwner {
        if (transfersEnabled) revert TransfersAlreadyEnabled();
        transfersEnabled = true;
        emit TransfersEnabled();
    }

    // Allow an operator (e.g., marketplace contract)
    function allowOperator(address operator) external onlyOwner {
        allowedOperators[operator] = true;
        emit OperatorAllowed(operator);
    }

    // Remove an operator from the allowlist
    function removeOperator(address operator) external onlyOwner {
        allowedOperators[operator] = false;
        emit OperatorRemoved(operator);
    }
}