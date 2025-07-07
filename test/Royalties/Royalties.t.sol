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
        address creator = address(0x1234);
        uint256 tokenId = 12345;
        uint256 salePrice = 1000 ether;

        (address receiver, uint256 royaltyAmount) = royalties.royaltyInfo(tokenId, salePrice, creator);

        assertEq(receiver, creator);
        assertEq(royaltyAmount, 50 ether); // 5% of 1000
    }

    function testFuzz_RoyaltyInfo_CalculatesCorrectly(uint256 tokenId, uint256 salePrice, address creator)
        public
        view
    {
        vm.assume(creator != address(0));
        vm.assume(salePrice < type(uint256).max / 500); // Prevent overflow

        (address receiver, uint256 royaltyAmount) = royalties.royaltyInfo(tokenId, salePrice, creator);

        assertEq(receiver, creator);
        assertEq(royaltyAmount, (salePrice * royalties.ROYALTY_BPS()) / royalties.BPS_DENOMINATOR());
    }

    function test_RoyaltyBPS_Is500() public view {
        assertEq(royalties.ROYALTY_BPS(), 500);
    }

    function test_BPS_DENOMINATOR_Is10000() public view {
        assertEq(royalties.BPS_DENOMINATOR(), 10000);
    }

    // Edge case tests
    function test_RoyaltyInfo_MaxSalePrice() public view {
        // Test with maximum possible sale price to check for overflow
        address creator = address(0x1234);
        uint256 tokenId = 12345;
        uint256 maxPrice = type(uint256).max / royalties.ROYALTY_BPS(); // Prevent overflow

        (address receiver, uint256 royaltyAmount) = royalties.royaltyInfo(tokenId, maxPrice, creator);

        assertEq(receiver, creator);
        // Should not overflow and should calculate correctly
        assertEq(royaltyAmount, (maxPrice * royalties.ROYALTY_BPS()) / royalties.BPS_DENOMINATOR());
        assertTrue(royaltyAmount <= maxPrice); // Royalty should never exceed sale price
    }

    function test_RoyaltyInfo_ZeroSalePrice() public view {
        // Test with zero sale price
        address creator = address(0x1234);
        uint256 tokenId = 12345;
        uint256 salePrice = 0;

        (address receiver, uint256 royaltyAmount) = royalties.royaltyInfo(tokenId, salePrice, creator);

        assertEq(receiver, creator);
        assertEq(royaltyAmount, 0);
    }

    function test_RoyaltyInfo_ZeroCreator() public view {
        // Test with zero address as creator
        address creator = address(0);
        uint256 tokenId = 12345;
        uint256 salePrice = 1000 ether;

        (address receiver, uint256 royaltyAmount) = royalties.royaltyInfo(tokenId, salePrice, creator);

        assertEq(receiver, address(0));
        assertEq(royaltyAmount, (salePrice * royalties.ROYALTY_BPS()) / royalties.BPS_DENOMINATOR());
    }

    function test_RoyaltyInfo_MinimumSalePrice() public view {
        // Test with minimum sale price that produces non-zero royalty
        address creator = address(0x1234);
        uint256 tokenId = 12345;
        uint256 salePrice = royalties.BPS_DENOMINATOR() / royalties.ROYALTY_BPS(); // Minimum for 1 wei royalty

        (address receiver, uint256 royaltyAmount) = royalties.royaltyInfo(tokenId, salePrice, creator);

        assertEq(receiver, creator);
        assertEq(royaltyAmount, 1); // Should be exactly 1 wei
    }

    function test_RoyaltyInfo_PrecisionLoss() public view {
        // Test for precision loss in royalty calculations
        address creator = address(0x1234);
        uint256 tokenId = 12345;
        uint256 salePrice = 1; // Very small sale price

        (address receiver, uint256 royaltyAmount) = royalties.royaltyInfo(tokenId, salePrice, creator);

        assertEq(receiver, creator);
        // With 1 wei sale price and 5% royalty, should round down to 0
        assertEq(royaltyAmount, 0);
    }

    function testFuzz_RoyaltyInfo_NoOverflow(uint256 salePrice) public view {
        // Test that royalty calculation never overflows
        address creator = address(0x1234);
        uint256 tokenId = 12345;

        // Bound salePrice to prevent overflow in the multiplication
        salePrice = _bound(salePrice, 0, type(uint256).max / royalties.ROYALTY_BPS());

        (address receiver, uint256 royaltyAmount) = royalties.royaltyInfo(tokenId, salePrice, creator);

        assertEq(receiver, creator);
        // Verify royalty is calculated correctly without overflow
        assertEq(royaltyAmount, (salePrice * royalties.ROYALTY_BPS()) / royalties.BPS_DENOMINATOR());
        // Royalty should never exceed sale price
        assertTrue(royaltyAmount <= salePrice);
    }
}
