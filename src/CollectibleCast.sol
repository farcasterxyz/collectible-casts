// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract CollectibleCast is Ownable2Step {
    constructor() Ownable(msg.sender) {}
}