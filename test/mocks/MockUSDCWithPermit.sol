// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {MockERC20} from "./MockERC20.sol";
import {IERC20Permit} from "../../src/interfaces/IERC20Permit.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

contract MockUSDCWithPermit is MockERC20, IERC20Permit, EIP712 {
    mapping(address => uint256) public nonces;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    constructor() MockERC20("USD Coin", "USDC") EIP712("USD Coin", "1") {}

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        if (block.timestamp > deadline) revert("Permit expired");

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address recoveredAddress = ECDSA.recover(hash, v, r, s);
        if (recoveredAddress != owner) revert("Invalid signature");

        _approve(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
