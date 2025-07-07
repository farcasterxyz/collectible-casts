// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ITransferValidator} from "./interfaces/ITransferValidator.sol";

contract TransferValidator is ITransferValidator, Ownable2Step {
    // One-way switch to enable transfers (disabled at launch)
    bool public transfersEnabled;

    // Operator allowlist for marketplace curation
    mapping(address => bool) public allowedOperators;

    constructor() Ownable(msg.sender) {}

    function validateTransfer(address operator, address from, address, uint256[] calldata, uint256[] calldata)
        external
        view
        override
        returns (bool)
    {
        // If transfers are not enabled, no transfers allowed at all
        if (!transfersEnabled) {
            return false;
        }

        // Transfers are enabled, check if operator is allowed
        // Owner can always transfer their own tokens
        if (operator == from) {
            return true;
        }

        // For third-party transfers, operator must be allowed
        return allowedOperators[operator];
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
