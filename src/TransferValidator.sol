// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ITransferValidator} from "./interfaces/ITransferValidator.sol";

contract TransferValidator is ITransferValidator, Ownable2Step {
    // State to control if transfers are paused
    bool public paused;

    // Events
    event Paused();
    event Unpaused();

    constructor() Ownable(msg.sender) {}

    function validateTransfer(
        address,
        address,
        address,
        uint256[] calldata,
        uint256[] calldata
    ) external view override returns (bool) {
        return !paused;
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }
}