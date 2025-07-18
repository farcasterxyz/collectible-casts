// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IAuction
 * @notice Ascending escrowed USDC auction for Farcaster collectible casts
 */
interface IAuction {
    error InvalidAddress(); // Zero address provided where valid address required
    error InvalidBidAmount(); // Bid amount insufficient or invalid
    error AuctionAlreadyExists(); // Auction for this cast already exists
    error AuctionNotActive(); // Auction is not in active state
    error AuctionNotEnded(); // Auction is still active, cannot settle
    error DeadlineExpired(); // Signature deadline has passed
    error NonceAlreadyUsed(); // Nonce has been used for previous signed operation
    error Unauthorized(); // Signer is not authorized for this operation
    error InvalidAuctionParams(); // Auction parameters are invalid or out of bounds
    error InvalidCreatorFid(); // Creator Farcaster ID is zero or invalid
    error InvalidCastHash(); // Cast hash is zero or invalid
    error AuctionNotCancellable(); // Auction is in a state that cannot be cancelled

    /**
     * @notice Global auction configuration. Used to validate per-auction params.
     * @param minBidAmount Min bid in USDC (6 decimals)
     * @param minAuctionDuration Min duration (seconds)
     * @param maxAuctionDuration Max duration (seconds)
     * @param maxExtension Max time extension (seconds)
     */
    struct AuctionConfig {
        uint32 minBidAmount;
        uint32 minAuctionDuration;
        uint32 maxAuctionDuration;
        uint32 maxExtension;
    }

    /**
     * @notice Auction-specific parameters. Signed and passed by offchain authorizer.
     * @param minBid Starting bid in USDC (6 decimals)
     * @param minBidIncrementBps Min bid increment (bps)
     * @param protocolFeeBps Protocol fee (bps)
     * @param duration Auction length (seconds)
     * @param extension Extension time (seconds)
     * @param extensionThreshold Extension trigger (seconds)
     */
    struct AuctionParams {
        uint64 minBid;
        uint16 minBidIncrementBps;
        uint16 protocolFeeBps;
        uint32 duration;
        uint32 extension;
        uint32 extensionThreshold;
    }

    /**
     * @notice Offchain authorizer signature data
     * @param nonce Replay protection nonce. Random 32 byte value.
     * @param deadline Signature expiration timestamp
     * @param signature EIP-712 signature bytes
     */
    struct AuthData {
        bytes32 nonce;
        uint256 deadline;
        bytes signature;
    }

    /**
     * @notice ERC20 Permit data
     * @param deadline Permit expiration
     * @param v Signature recovery byte
     * @param r Signature r value
     * @param s Signature s value
     */
    struct PermitData {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /**
     * @notice Bid data
     * @param bidderFid Bidder's Farcaster ID
     * @param amount Bid in USDC (6 decimals)
     */
    struct BidData {
        uint96 bidderFid;
        uint256 amount;
    }

    /**
     * @notice Cast data
     * @param castHash Unique cast identifier
     * @param creator Cast creator's primary address at time of auction
     * @param creatorFid Cast creator's Farcaster ID
     */
    struct CastData {
        bytes32 castHash;
        address creator;
        uint96 creatorFid;
    }

    /**
     * @notice Auction state data
     * @param creator Cast creator's primary address
     * @param creatorFid Cast creator's FID
     * @param highestBidder Current leader
     * @param highestBidderFid Leader's FID
     * @param highestBid Leading bid (USDC)
     * @param lastBidAt Last bid timestamp
     * @param endTime End time (extensible)
     * @param bids Bid count
     * @param state Auction state
     * @param params Auction parameters
     */
    struct AuctionData {
        address creator;
        uint96 creatorFid;
        address highestBidder;
        uint96 highestBidderFid;
        uint256 highestBid;
        uint40 lastBidAt;
        uint40 endTime;
        uint32 bids;
        AuctionState state;
        AuctionParams params;
    }

    /**
     * @notice Auction states
     */
    enum AuctionState {
        None,
        Active,
        Ended,
        Settled,
        Cancelled,
        Recovered
    }

    event AuthorizerAllowed(address indexed authorizer); // Allowed a new offchain authorizer
    event AuthorizerDenied(address indexed authorizer); // Removed an offchain authorizer
    event TreasurySet(address indexed oldTreasury, address indexed newTreasury); // Treasury address updated
    event AuctionConfigSet(AuctionConfig config); // Global auction configuration updated
    event AuctionStarted(
        bytes32 indexed castHash, address indexed creator, uint96 creatorFid, uint40 endTime, address authorizer
    ); // New auction started with initial bid and signed parameters
    event BidPlaced(bytes32 indexed castHash, address indexed bidder, uint96 bidderFid, uint256 amount); // Bid placed on auction
    event AuctionExtended(bytes32 indexed castHash, uint256 newEndTime); // Auction end time extended due to late bid
    event AuctionSettled(bytes32 indexed castHash, address indexed winner, uint96 winnerFid, uint256 amount); // Auction settled, NFT minted to winner
    event AuctionCancelled(
        bytes32 indexed castHash, address indexed refundedBidder, uint96 refundedBidderFid, address indexed authorizer
    ); // Auction cancelled, highest bidder refunded
    event AuctionRecovered(bytes32 indexed castHash, address indexed refundTo, uint256 amount); // Emergency recovery, funds sent to recovery address
    event BidRefunded(address indexed to, uint256 amount); // USDC refunded to previous bidder

    /**
     * @notice Starts an auction with prior USDC allowance
     * @param cast Cast to auction
     * @param bidData Initial bid
     * @param params Auction settings
     * @param auth Signature authorization
     */
    function start(CastData memory cast, BidData memory bidData, AuctionParams memory params, AuthData memory auth)
        external;

    /**
     * @notice Starts an auction with USDC permit signature
     * @param cast Cast to auction
     * @param bidData Initial bid
     * @param params Auction settings
     * @param auth Signature authorization
     * @param permit USDC permit signature data
     */
    function start(
        CastData memory cast,
        BidData memory bidData,
        AuctionParams memory params,
        AuthData memory auth,
        PermitData memory permit
    ) external;

    /**
     * @notice Places a bid with prior USDC allowance
     * @param castHash Cast identifier
     * @param bidData Bid details
     * @param auth Signature authorization
     * @dev Auto-refunds previous bidder
     */
    function bid(bytes32 castHash, BidData memory bidData, AuthData memory auth) external;

    /**
     * @notice Places a bid with USDC permit signature
     * @param castHash Cast identifier
     * @param bidData Bid details
     * @param auth Signature authorization
     * @param permit USDC permit signature data
     */
    function bid(bytes32 castHash, BidData memory bidData, AuthData memory auth, PermitData memory permit) external;

    /**
     * @notice Settles ended auction
     * @param castHash Cast identifier
     * @dev Mints NFT and distributes payments
     */
    function settle(bytes32 castHash) external;

    /**
     * @notice Batch settles multiple auctions
     * @param castHashes Casts to settle
     */
    function batchSettle(bytes32[] calldata castHashes) external;

    /**
     * @notice Cancels an active auction
     * @param castHash Cast identifier
     * @param auth Signature authorization
     * @dev Refunds highest bidder
     */
    function cancel(bytes32 castHash, AuthData memory auth) external;

    /**
     * @notice Emergency recovery for stuck auctions
     * @param castHash Cast identifier
     * @param refundTo Address to send refund
     * @dev Owner only. Treats as emergency cancellation.
     */
    function recover(bytes32 castHash, address refundTo) external;

    /**
     * @notice Read auction state
     * @param castHash Cast identifier
     * @return Current state
     */
    function auctionState(bytes32 castHash) external view returns (AuctionState);

    /**
     * @notice Computes bid authorization hash
     * @return EIP-712 hash for signature verification
     */
    function hashBidAuthorization(
        bytes32 castHash,
        address bidder,
        uint96 bidderFid,
        uint256 amount,
        bytes32 nonce,
        uint256 deadline
    ) external view returns (bytes32);

    /**
     * @notice Computes cancel authorization hash
     * @return EIP-712 hash for signature verification
     */
    function hashCancelAuthorization(bytes32 castHash, bytes32 nonce, uint256 deadline)
        external
        view
        returns (bytes32);

    /**
     * @notice Computes start authorization hash
     * @return EIP-712 hash for signature verification
     */
    function hashStartAuthorization(
        bytes32 castHash,
        address creator,
        uint96 creatorFid,
        address bidder,
        uint96 bidderFid,
        uint256 amount,
        AuctionParams memory params,
        bytes32 nonce,
        uint256 deadline
    ) external view returns (bytes32);

    /**
     * @notice EIP-712 domain separator
     * @return Domain separator for signatures
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
