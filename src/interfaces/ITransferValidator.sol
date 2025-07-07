// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface ITransferValidator {
    // Custom errors
    error TransfersAlreadyEnabled();
    error TransfersDisabled();

    // Events
    event TransfersEnabled();
    event OperatorAllowed(address indexed operator);
    event OperatorRemoved(address indexed operator);

    function validateTransfer(
        address operator,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external view returns (bool);

    function enableTransfers() external;
    function allowOperator(address operator) external;
    function removeOperator(address operator) external;

    // View functions
    function transfersEnabled() external view returns (bool);
    function allowedOperators(address operator) external view returns (bool);
}
