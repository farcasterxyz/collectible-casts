// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import {Royalties} from "../../src/Royalties.sol";

contract RoyaltiesTest is TestSuiteSetup {
    Royalties public royalties;

    function setUp() public override {
        super.setUp();
        royalties = new Royalties();
    }

    function test_RoyaltyInfo_Returns5PercentToCreator() public {
        address creator = makeAddr("creator");
        uint256 tokenId = 12345;
        uint256 salePrice = 1000 ether;

        (address receiver, uint256 royaltyAmount) = royalties.royaltyInfo(tokenId, salePrice, creator);

        assertEq(receiver, creator);
        assertEq(royaltyAmount, 50 ether); // 5% of 1000
    }

    function testFuzz_RoyaltyInfo_CalculatesCorrectly(uint256 tokenId, uint256 salePrice, address creator) public {
        vm.assume(creator != address(0));
        vm.assume(salePrice < type(uint256).max / 500); // Prevent overflow

        (address receiver, uint256 royaltyAmount) = royalties.royaltyInfo(tokenId, salePrice, creator);

        assertEq(receiver, creator);
        assertEq(royaltyAmount, (salePrice * 500) / 10000);
    }

    function test_RoyaltyBPS_Is500() public view {
        assertEq(royalties.ROYALTY_BPS(), 500);
    }
}
