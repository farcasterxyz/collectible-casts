// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ITransferValidator} from "../../../src/interfaces/ITransferValidator.sol";

contract MockTransferValidator is ITransferValidator {
    bool public allowTransfers;

    constructor(bool _allowTransfers) {
        allowTransfers = _allowTransfers;
    }

    function validateTransfer(address, address, address, uint256[] calldata, uint256[] calldata)
        external
        view
        returns (bool)
    {
        return allowTransfers;
    }
}
