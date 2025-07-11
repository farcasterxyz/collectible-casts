// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IAuction {
    error InvalidAddress();
    error InvalidBidAmount();
    error AuctionDoesNotExist();
    error AuctionAlreadyExists();
    error AuctionAlreadySettled();
    error AuctionNotActive();
    error AuctionNotEnded();
    error DeadlineExpired();
    error NonceAlreadyUsed();
    error UnauthorizedBidder();
    error InvalidProtocolFee();
    error InvalidAuctionParams();
    error InvalidCreatorFid();
    error SelfBidding();
    error InvalidCastHash();
    error InsufficientAllowance();

    struct AuctionConfig {
        uint32 minBidAmount;
        uint32 minAuctionDuration;
        uint32 maxAuctionDuration;
        uint32 maxExtension;
    }

    struct AuctionParams {
        uint64 minBid;
        uint16 minBidIncrementBps;
        uint16 protocolFeeBps;
        uint32 duration;
        uint32 extension;
        uint32 extensionThreshold;
    }

    struct AuthData {
        bytes32 nonce;
        uint256 deadline;
        bytes signature;
    }

    struct PermitData {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct BidData {
        uint96 bidderFid;
        uint256 amount;
    }

    struct CastData {
        bytes32 castHash;
        address creator;
        uint96 creatorFid;
    }

    struct AuctionData {
        address creator;
        uint96 creatorFid;
        address highestBidder;
        uint96 highestBidderFid;
        uint256 highestBid;
        uint40 lastBidAt;
        uint40 endTime;
        bool settled;
        AuctionParams params;
    }

    enum AuctionState {
        None, // Auction doesn't exist
        Active, // Auction is accepting bids
        Ended, // Auction ended but not settled
        Settled // Auction settled and NFT minted

    }

    event AuthorizerAllowed(address indexed authorizer);
    event AuthorizerDenied(address indexed authorizer);
    event TreasurySet(address indexed oldTreasury, address indexed newTreasury);
    event AuctionConfigSet(AuctionConfig config);
    event AuctionStarted(bytes32 indexed castHash, address indexed creator, uint96 creatorFid);
    event BidPlaced(bytes32 indexed castHash, address indexed bidder, uint96 bidderFid, uint256 amount);
    event AuctionExtended(bytes32 indexed castHash, uint256 newEndTime);
    event AuctionSettled(bytes32 indexed castHash, address indexed winner, uint96 winnerFid, uint256 amount);

    function start(CastData memory cast, BidData memory bid, AuctionParams memory params, AuthData memory auth)
        external;

    function start(
        CastData memory cast,
        BidData memory bid,
        AuctionParams memory params,
        AuthData memory auth,
        PermitData memory permit
    ) external;

    function bid(bytes32 castHash, BidData memory bid, AuthData memory auth) external;

    function bid(bytes32 castHash, BidData memory bid, AuthData memory auth, PermitData memory permit) external;

    function settle(bytes32 castHash) external;

    function batchSettle(bytes32[] calldata castHashes) external;

    function auctionState(bytes32 castHash) external view returns (AuctionState);
}
