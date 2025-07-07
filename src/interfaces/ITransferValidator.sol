// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface ITransferValidator {
    function validateTransfer(
        address operator,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external view returns (bool);
}
