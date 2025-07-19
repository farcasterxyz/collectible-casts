// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "../../src/interfaces/IAuction.sol";

contract AuctionTestHelper {
    function createCastData(bytes32 castHash, address creator, uint96 creatorFid)
        internal
        pure
        returns (IAuction.CastData memory)
    {
        return IAuction.CastData({castHash: castHash, creator: creator, creatorFid: creatorFid});
    }

    function createBidData(uint96 bidderFid, uint256 amount) internal pure returns (IAuction.BidData memory) {
        return IAuction.BidData({bidderFid: bidderFid, amount: amount});
    }

    function createAuthData(bytes32 nonce, uint256 deadline, bytes memory signature)
        internal
        pure
        returns (IAuction.AuthData memory)
    {
        return IAuction.AuthData({nonce: nonce, deadline: deadline, signature: signature});
    }

    function createPermitData(uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        internal
        pure
        returns (IAuction.PermitData memory)
    {
        return IAuction.PermitData({deadline: deadline, v: v, r: r, s: s});
    }

    function createAuctionParams(
        uint256 minBid,
        uint256 minBidIncrement,
        uint256 duration,
        uint256 extension,
        uint256 extensionThreshold,
        uint256 protocolFee
    ) internal pure returns (IAuction.AuctionParams memory) {
        return IAuction.AuctionParams({
            minBid: uint64(minBid),
            minBidIncrementBps: uint16(minBidIncrement),
            duration: uint32(duration),
            extension: uint32(extension),
            extensionThreshold: uint32(extensionThreshold),
            protocolFeeBps: uint16(protocolFee)
        });
    }
}
