// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IAuction {
    // Custom errors
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

    // Structs
    struct AuctionParams {
        uint256 minBid;
        uint256 minBidIncrement;
        uint256 duration;
        uint256 extension;
        uint256 extensionThreshold;
        uint256 protocolFee;
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
        uint256 bidderFid;
        uint256 amount;
    }

    struct CastData {
        bytes32 castHash;
        address creator;
        uint256 creatorFid;
    }

    struct AuctionData {
        // Cast metadata (set at auction start)
        address creator;
        uint256 creatorFid;
        // Auction state
        address highestBidder;
        uint256 highestBidderFid;
        uint256 highestBid;
        uint256 endTime;
        bool settled;
        // Custom parameters for this auction
        AuctionParams params;
    }

    // Enums
    enum AuctionState {
        None, // Auction doesn't exist
        Active, // Auction is accepting bids
        Ended, // Auction ended but not settled
        Settled // Auction settled and NFT minted

    }

    // Events
    event AuthorizerAllowed(address indexed authorizer);
    event AuthorizerDenied(address indexed authorizer);
    event TreasurySet(address indexed oldTreasury, address indexed newTreasury);
    event AuctionStarted(bytes32 indexed castHash, address indexed creator, uint256 creatorFid);
    event BidPlaced(bytes32 indexed castHash, address indexed bidder, uint256 bidderFid, uint256 amount);
    event AuctionExtended(bytes32 indexed castHash, uint256 newEndTime);
    event AuctionSettled(bytes32 indexed castHash, address indexed winner, uint256 winnerFid, uint256 amount);

    // Main auction functions
    function start(
        CastData memory castData,
        BidData memory bidData,
        AuctionParams memory params,
        AuthData memory auth
    ) external;

    function start(
        CastData memory castData,
        BidData memory bidData,
        AuctionParams memory params,
        AuthData memory auth,
        PermitData memory permit
    ) external;

    function bid(
        bytes32 castHash,
        BidData memory bidData,
        AuthData memory auth
    ) external;

    function bid(
        bytes32 castHash,
        BidData memory bidData,
        AuthData memory auth,
        PermitData memory permit
    ) external;

    function settle(bytes32 castHash) external;

    // View functions
    function getAuctionState(bytes32 castHash) external view returns (AuctionState);
}
