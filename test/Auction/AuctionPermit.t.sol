// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "../../src/interfaces/IAuction.sol";
import {AuctionTestBase} from "./AuctionTestBase.sol";

contract AuctionPermitTest is AuctionTestBase {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function testFuzz_StartWithPermit_Success(uint96 bidderFid, uint256 amount, bytes32 nonce) public {
        (address bidder, uint256 bidderKey) = makeAddrAndKey("bidder");
        bidderFid = uint96(_bound(bidderFid, 1, type(uint96).max));
        amount = _bound(amount, 1e6, 10000e6); // 1 to 10,000 USDC
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = _getDefaultAuctionParams();

        // Create auction start authorization
        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Create permit signature
        uint256 permitDeadline = block.timestamp + 1 hours;
        bytes32 permitHash = _getPermitHash(bidder, address(auction), amount, 0, permitDeadline);
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(bidderKey, permitHash);

        IAuction.PermitData memory permit = createPermitData(permitDeadline, permitV, permitR, permitS);

        // Give bidder USDC but don't approve
        usdc.mint(bidder, amount);

        // Verify no approval exists
        assertEq(usdc.allowance(bidder, address(auction)), 0);

        // Start auction with permit
        vm.prank(bidder);
        auction.start(castData, bidData, params, auth, permit);

        // Verify auction started and USDC transferred
        assertEq(usdc.balanceOf(address(auction)), amount);
        assertEq(usdc.balanceOf(bidder), 0);
    }

    function testFuzz_BidWithPermit_Success(
        address firstBidder,
        uint96 firstBidderFid,
        uint256 firstAmount,
        uint96 secondBidderFid,
        uint256 bidIncrement,
        bytes32 nonce
    ) public {
        // Bound inputs
        vm.assume(firstBidder != address(0));
        vm.assume(firstBidder != address(auction)); // Not the auction contract
        vm.assume(nonce != keccak256("start-nonce")); // Avoid nonce collision
        firstBidderFid = uint96(_bound(firstBidderFid, 1, type(uint96).max));
        firstAmount = _bound(firstAmount, 1e6, 1000e6); // 1 to 1000 USDC
        secondBidderFid = uint96(_bound(secondBidderFid, 1, type(uint96).max));

        // Calculate valid bid increment
        uint256 minIncrement = (firstAmount * 1000) / 10000; // 10%
        if (minIncrement < 1e6) minIncrement = 1e6;
        bidIncrement = _bound(bidIncrement, minIncrement, 100e6);
        uint256 secondAmount = firstAmount + bidIncrement;

        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Second bidder with permit
        (address secondBidder, uint256 secondBidderKey) = makeAddrAndKey("secondBidder");
        uint256 deadline = block.timestamp + 1 hours;

        // Create bid authorization
        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, secondAmount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Create permit signature
        uint256 permitDeadline = block.timestamp + 1 hours;
        bytes32 permitHash = _getPermitHash(secondBidder, address(auction), secondAmount, 0, permitDeadline);
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(secondBidderKey, permitHash);

        // Give second bidder USDC but don't approve
        usdc.mint(secondBidder, secondAmount);

        // Verify no approval exists
        assertEq(usdc.allowance(secondBidder, address(auction)), 0);

        // Record first bidder's balance before bid
        uint256 firstBidderBalanceBefore = usdc.balanceOf(firstBidder);

        IAuction.BidData memory bidData = createBidData(secondBidderFid, secondAmount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        IAuction.PermitData memory permit = createPermitData(permitDeadline, permitV, permitR, permitS);

        // Place bid with permit
        vm.prank(secondBidder);
        auction.bid(TEST_CAST_HASH, bidData, auth, permit);

        // Verify bid succeeded
        assertEq(usdc.balanceOf(address(auction)), secondAmount);
        assertEq(usdc.balanceOf(secondBidder), 0);
        assertEq(usdc.balanceOf(firstBidder), firstBidderBalanceBefore + firstAmount); // Refunded
    }

    function testFuzz_StartWithPermit_ExpiredPermit(
        uint96 bidderFid,
        uint256 amount,
        bytes32 nonce,
        uint256 expiredOffset
    ) public {
        (address bidder, uint256 bidderKey) = makeAddrAndKey("bidder");
        bidderFid = uint96(_bound(bidderFid, 1, type(uint96).max));
        amount = _bound(amount, 1e6, 10000e6);
        expiredOffset = _bound(expiredOffset, 1, block.timestamp > 365 days ? 365 days : block.timestamp); // Avoid underflow
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = _getDefaultAuctionParams();

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Create expired permit signature
        uint256 permitDeadline = block.timestamp - expiredOffset; // Already expired
        bytes32 permitHash = _getPermitHash(bidder, address(auction), amount, 0, permitDeadline);
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(bidderKey, permitHash);

        IAuction.PermitData memory permit = createPermitData(permitDeadline, permitV, permitR, permitS);

        usdc.mint(bidder, amount);

        // Should revert when permit fails (expired deadline)
        vm.prank(bidder);
        vm.expectRevert(); // Will revert with ERC20Permit: expired deadline
        auction.start(castData, bidData, params, auth, permit);
    }

    function testFuzz_StartWithPermit_InvalidSignature(uint96 bidderFid, uint256 amount, bytes32 nonce) public {
        (address bidder,) = makeAddrAndKey("bidder");
        bidderFid = uint96(_bound(bidderFid, 1, type(uint96).max));
        amount = _bound(amount, 1e6, 10000e6);
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = _getDefaultAuctionParams();

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Give bidder USDC
        usdc.mint(bidder, amount);

        // Use invalid permit signature
        uint256 permitDeadline = block.timestamp + 1 hours;
        uint8 permitV = 27;
        bytes32 permitR = bytes32(uint256(1));
        bytes32 permitS = bytes32(uint256(2));

        IAuction.PermitData memory permit = createPermitData(permitDeadline, permitV, permitR, permitS);

        // Should revert due to invalid permit
        vm.prank(bidder);
        vm.expectRevert(); // Will revert with ERC20Permit: invalid signature
        auction.start(castData, bidData, params, auth, permit);
    }

    function testFuzz_BidWithPermit_PermitAlreadyUsed(
        address firstBidder,
        uint96 firstBidderFid,
        uint256 firstAmount,
        uint96 secondBidderFid,
        uint256 bidIncrement
    ) public {
        // Bound inputs
        vm.assume(firstBidder != address(0));
        vm.assume(firstBidder != address(auction)); // Not the auction contract
        firstBidderFid = uint96(_bound(firstBidderFid, 1, type(uint96).max));
        firstAmount = _bound(firstAmount, 1e6, 1000e6);
        secondBidderFid = uint96(_bound(secondBidderFid, 1, type(uint96).max));

        // Calculate valid bid increment
        uint256 minIncrement = (firstAmount * 1000) / 10000; // 10%
        if (minIncrement < 1e6) minIncrement = 1e6;
        bidIncrement = _bound(bidIncrement, minIncrement, 100e6);
        uint256 amount = firstAmount + bidIncrement;

        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Second bidder setup
        (address secondBidder, uint256 secondBidderKey) = makeAddrAndKey("secondBidder");

        // Create permit signature
        uint256 permitDeadline = block.timestamp + 1 hours;
        bytes32 permitHash = _getPermitHash(secondBidder, address(auction), amount, 0, permitDeadline);
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(secondBidderKey, permitHash);

        // Use permit directly first
        usdc.mint(secondBidder, amount * 2); // Mint extra for second attempt
        vm.prank(secondBidder);
        usdc.permit(secondBidder, address(auction), amount, permitDeadline, permitV, permitR, permitS);

        // Now try to bid with same permit (should revert since permit already used)
        bytes32 nonce = keccak256("bid-nonce-1");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.BidData memory bidData = createBidData(secondBidderFid, amount);
        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);
        IAuction.PermitData memory permit = createPermitData(permitDeadline, permitV, permitR, permitS);

        // Should revert since permit was already used
        vm.prank(secondBidder);
        vm.expectRevert(); // Will revert with ERC20Permit: invalid signature (nonce already used)
        auction.bid(TEST_CAST_HASH, bidData, auth, permit);
    }

    function testFuzz_StartWithPermit_FailsWhenInsufficientAllowanceAfterPermitFail(
        uint96 bidderFid,
        uint256 amount,
        bytes32 nonce
    ) public {
        (address bidder,) = makeAddrAndKey("bidder-no-allowance");
        bidderFid = uint96(_bound(bidderFid, 1, type(uint96).max));
        amount = _bound(amount, 1e6, 10000e6);
        uint256 deadline = block.timestamp + 1 hours;

        IAuction.CastData memory castData = createCastData(TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID);
        IAuction.BidData memory bidData = createBidData(bidderFid, amount);
        IAuction.AuctionParams memory params = _getDefaultAuctionParams();

        bytes32 messageHash = auction.hashStartAuthorization(
            TEST_CAST_HASH, DEFAULT_CREATOR, DEFAULT_CREATOR_FID, bidder, bidderFid, amount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.AuthData memory auth = createAuthData(nonce, deadline, signature);

        // Create invalid permit data that will fail
        IAuction.PermitData memory invalidPermit = createPermitData(
            block.timestamp + 1 hours, // deadline
            27, // v (invalid)
            bytes32(uint256(1)), // r (invalid)
            bytes32(uint256(2)) // s (invalid)
        );

        // Give bidder USDC but don't approve and use invalid permit
        usdc.mint(bidder, amount);
        // No approval and invalid permit should cause permit to fail

        vm.prank(bidder);
        vm.expectRevert(); // Will revert with ERC20Permit: invalid signature
        auction.start(castData, bidData, params, auth, invalidPermit);
    }

    function testFuzz_BidWithPermit_FailsWhenInsufficientAllowanceAfterPermitFail(
        address firstBidder,
        uint96 firstBidderFid,
        uint256 firstAmount,
        uint96 secondBidderFid,
        uint256 bidIncrement,
        bytes32 nonce
    ) public {
        // Bound inputs
        vm.assume(firstBidder != address(0));
        vm.assume(nonce != keccak256("start-nonce")); // Avoid nonce collision
        firstBidderFid = uint96(_bound(firstBidderFid, 1, type(uint96).max));
        firstAmount = _bound(firstAmount, 1e6, 1000e6);
        secondBidderFid = uint96(_bound(secondBidderFid, 1, type(uint96).max));

        // Calculate valid bid increment
        uint256 minIncrement = (firstAmount * 1000) / 10000; // 10%
        if (minIncrement < 1e6) minIncrement = 1e6;
        bidIncrement = _bound(bidIncrement, minIncrement, 100e6);
        uint256 secondAmount = firstAmount + bidIncrement;

        _startAuction(firstBidder, firstBidderFid, firstAmount);

        // Second bidder with invalid permit and no approval
        (address secondBidder,) = makeAddrAndKey("secondBidder-no-allowance");
        uint256 deadline = block.timestamp + 1 hours;

        // Create bid authorization
        bytes32 messageHash =
            auction.hashBidAuthorization(TEST_CAST_HASH, secondBidder, secondBidderFid, secondAmount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IAuction.BidData memory bidData = createBidData(secondBidderFid, secondAmount);
        IAuction.AuthData memory authData = createAuthData(nonce, deadline, signature);

        // Create invalid permit signature
        IAuction.PermitData memory invalidPermit = createPermitData(
            block.timestamp + 1 hours, // deadline
            27, // v (invalid)
            bytes32(uint256(1)), // r (invalid)
            bytes32(uint256(2)) // s (invalid)
        );

        // Give second bidder USDC but don't approve
        usdc.mint(secondBidder, secondAmount);

        // Verify no approval exists
        assertEq(usdc.allowance(secondBidder, address(auction)), 0);

        // Should revert since permit fails
        vm.prank(secondBidder);
        vm.expectRevert(); // Will revert with ERC20Permit: invalid signature
        auction.bid(TEST_CAST_HASH, bidData, authData, invalidPermit);
    }

    // Helper functions
    function _getPermitHash(address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));

        return keccak256(abi.encodePacked("\x19\x01", usdc.DOMAIN_SEPARATOR(), structHash));
    }
}
