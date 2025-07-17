// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IERC20Permit
 * @notice EIP-2612: Gasless token approvals via signatures
 */
interface IERC20Permit {
    /**
     * @notice Approves tokens via signature
     * @param owner Token holder signing permit
     * @param spender Approved address
     * @param value Approval amount
     * @param deadline Permit expiration
     * @param v Signature v
     * @param r Signature r
     * @param s Signature s
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    /**
     * @notice Gets nonce for replay protection
     * @param owner Address to check
     * @return Current nonce
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @notice Gets EIP-712 domain separator
     * @return Domain separator
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
