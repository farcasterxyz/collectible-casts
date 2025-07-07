// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

abstract contract TestSuiteSetup is Test {
    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        // Base setup can be extended by inheriting contracts
    }

    /**
     * @dev Assumes the address is not the zero address and has no code
     */
    function _assumeClean(address addr) internal view {
        vm.assume(addr != address(0));
        vm.assume(addr.code.length == 0);
    }

    /**
     * @dev Bounds a private key to valid range
     */
    function _boundPk(uint256 pk) internal pure returns (uint256) {
        return _bound(pk, 1, type(uint256).max);
    }

    /**
     * @dev Create a user with a private key
     */
    function _createUser(string memory name) internal returns (address, uint256) {
        uint256 pk = uint256(keccak256(abi.encodePacked(name)));
        pk = _boundPk(pk);
        address user = vm.addr(pk);
        vm.label(user, name);
        return (user, pk);
    }

    /**
     * @dev Deal ETH to an address and prank
     */
    function _hoaxWithETH(address user, uint256 amount) internal {
        vm.deal(user, amount);
        vm.prank(user);
    }

    /**
     * @dev Skip time forward
     */
    function _skipTime(uint256 seconds_) internal {
        skip(seconds_);
    }

    /**
     * @dev Expect a custom error with no parameters
     */
    function _expectRevert(bytes4 selector) internal {
        vm.expectRevert(abi.encodeWithSelector(selector));
    }

    /**
     * @dev Expect a custom error with parameters
     */
    function _expectRevertWithArgs(bytes memory data) internal {
        vm.expectRevert(data);
    }
}