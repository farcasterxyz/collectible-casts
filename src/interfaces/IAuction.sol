// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICollectibleCasts} from "./ICollectibleCasts.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title IAuction
 * @author Farcaster
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
     * @param minBidAmount Minimum bid amount in USDC (6 decimals)
     * @param minAuctionDuration Minimum auction duration in seconds
     * @param maxAuctionDuration Maximum auction duration in seconds
     * @param maxExtension Maximum time extension in seconds when bid is placed near end
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

    /**
     * @notice Emitted when a new authorizer is allowed
     * @param authorizer Address granted authorization
     */
    event AuthorizerAllowed(address indexed authorizer);

    /**
     * @notice Emitted when an authorizer is denied
     * @param authorizer Address revoked authorization
     */
    event AuthorizerDenied(address indexed authorizer);

    /**
     * @notice Emitted when treasury address is updated
     * @param oldTreasury Previous treasury address
     * @param newTreasury New treasury address
     */
    event TreasurySet(address indexed oldTreasury, address indexed newTreasury);

    /**
     * @notice Emitted when auction configuration is updated
     * @param config New auction configuration
     */
    event AuctionConfigSet(AuctionConfig config);
    /**
     * @notice Emitted when a new auction is started
     * @param castHash Unique identifier of the cast
     * @param creator Cast creator's address
     * @param creatorFid Cast creator's Farcaster ID
     * @param endTime Auction end timestamp
     * @param authorizer Address that signed the authorization
     */
    event AuctionStarted(
        bytes32 indexed castHash, address indexed creator, uint96 creatorFid, uint40 endTime, address authorizer
    );

    /**
     * @notice Emitted when a bid is placed
     * @param castHash Unique identifier of the cast
     * @param bidder Bidder's address
     * @param bidderFid Bidder's Farcaster ID
     * @param amount Bid amount in USDC
     * @param authorizer Address that signed the authorization
     */
    event BidPlaced(
        bytes32 indexed castHash, address indexed bidder, uint96 bidderFid, uint256 amount, address indexed authorizer
    );

    /**
     * @notice Emitted when auction end time is extended
     * @param castHash Unique identifier of the cast
     * @param newEndTime New auction end timestamp
     */
    event AuctionExtended(bytes32 indexed castHash, uint256 newEndTime);

    /**
     * @notice Emitted when an auction is settled
     * @param castHash Unique identifier of the cast
     * @param winner Winner's address
     * @param winnerFid Winner's Farcaster ID
     * @param amount Winning bid amount
     */
    event AuctionSettled(bytes32 indexed castHash, address indexed winner, uint96 winnerFid, uint256 amount);

    /**
     * @notice Emitted when an auction is cancelled
     * @param castHash Unique identifier of the cast
     * @param refundedBidder Address receiving refund
     * @param refundedBidderFid Farcaster ID of refunded bidder
     * @param authorizer Address that signed the authorization
     */
    event AuctionCancelled(
        bytes32 indexed castHash, address indexed refundedBidder, uint96 refundedBidderFid, address indexed authorizer
    );

    /**
     * @notice Emitted when an auction is recovered by owner
     * @param castHash Unique identifier of the cast
     * @param refundTo Address receiving the recovered funds
     * @param amount Amount recovered
     */
    event AuctionRecovered(bytes32 indexed castHash, address indexed refundTo, uint256 amount);

    /**
     * @notice Emitted when USDC is refunded to a previous bidder
     * @param castHash Unique identifier of the cast
     * @param to Address receiving refund
     * @param amount Amount refunded
     */
    event BidRefunded(bytes32 indexed castHash, address indexed to, uint256 amount);

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
        AuctionParams calldata params,
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
     * @notice Batch cancels multiple auctions
     * @param castHashes Array of cast identifiers
     * @param authDatas Array of signature authorizations (must match castHashes length)
     * @dev Reverts entire batch if any cancellation fails
     */
    function batchCancel(bytes32[] calldata castHashes, AuthData[] calldata authDatas) external;

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
     * @notice Get auction data with calculated state
     * @param castHash Cast identifier
     * @return Auction data with current calculated state
     * @dev Returns empty struct for non-existent auctions
     */
    function getAuction(bytes32 castHash) external view returns (AuctionData memory);

    /**
     * @notice Computes bid authorization hash
     * @param castHash Unique identifier of the cast
     * @param bidder Bidder's address
     * @param bidderFid Bidder's Farcaster ID
     * @param amount Bid amount in USDC
     * @param nonce Unique nonce for replay protection
     * @param deadline Signature expiration timestamp
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
     * @param castHash Unique identifier of the cast
     * @param nonce Unique nonce for replay protection
     * @param deadline Signature expiration timestamp
     * @return EIP-712 hash for signature verification
     */
    function hashCancelAuthorization(bytes32 castHash, bytes32 nonce, uint256 deadline)
        external
        view
        returns (bytes32);

    /**
     * @notice Computes start authorization hash
     * @param castHash Unique identifier of the cast
     * @param creator Cast creator's address
     * @param creatorFid Cast creator's Farcaster ID
     * @param bidder Initial bidder's address
     * @param bidderFid Initial bidder's Farcaster ID
     * @param amount Initial bid amount in USDC
     * @param params Auction parameters
     * @param nonce Unique nonce for replay protection
     * @param deadline Signature expiration timestamp
     * @return EIP-712 hash for signature verification
     */
    function hashStartAuthorization(
        bytes32 castHash,
        address creator,
        uint96 creatorFid,
        address bidder,
        uint96 bidderFid,
        uint256 amount,
        AuctionParams calldata params,
        bytes32 nonce,
        uint256 deadline
    ) external view returns (bytes32);

    /**
     * @notice EIP-712 domain separator
     * @return Domain separator for signatures
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    // ========== ADMIN FUNCTIONS ==========

    /**
     * @notice Grants authorization to sign auction operations
     * @param authorizer Address to grant authorization
     * @dev Owner only
     */
    function allowAuthorizer(address authorizer) external;

    /**
     * @notice Revokes authorization to sign auction operations
     * @param authorizer Address to revoke authorization
     * @dev Owner only
     */
    function denyAuthorizer(address authorizer) external;

    /**
     * @notice Updates protocol fee recipient
     * @param _treasury New treasury address
     * @dev Owner only
     */
    function setTreasury(address _treasury) external;

    /**
     * @notice Updates global auction configuration
     * @param _config New configuration parameters
     * @dev Owner only. Validates all parameters.
     */
    function setAuctionConfig(AuctionConfig memory _config) external;

    /**
     * @notice Pauses all auction operations
     * @dev Owner only. Emits Paused event.
     */
    function pause() external;

    /**
     * @notice Resumes all auction operations
     * @dev Owner only. Emits Unpaused event.
     */
    function unpause() external;

    // ========== PUBLIC STATE VARIABLES ==========

    /**
     * @notice Collectible NFT contract
     * @return Address of the CollectibleCasts contract
     */
    function collectible() external view returns (ICollectibleCasts);

    /**
     * @notice USDC token contract
     * @return Address of the USDC token
     */
    function usdc() external view returns (IERC20);

    /**
     * @notice Protocol fee recipient
     * @return Current treasury address
     */
    function treasury() external view returns (address);

    /**
     * @notice Global auction configuration
     * @return minBidAmount Minimum bid amount in USDC (6 decimals)
     * @return minAuctionDuration Minimum auction duration in seconds
     * @return maxAuctionDuration Maximum auction duration in seconds
     * @return maxExtension Maximum time extension in seconds
     */
    function config()
        external
        view
        returns (uint32 minBidAmount, uint32 minAuctionDuration, uint32 maxAuctionDuration, uint32 maxExtension);

    /**
     * @notice Checks if address is authorized to sign
     * @param signer Address to check
     * @return Whether address is authorized
     */
    function authorizers(address signer) external view returns (bool);

    /**
     * @notice Checks if nonce has been used
     * @param nonce Nonce to check
     * @return Whether nonce has been used
     */
    function usedNonces(bytes32 nonce) external view returns (bool);

    /**
     * @notice Gets raw auction data from storage
     * @param castHash Cast identifier
     * @return creator Cast creator's primary address
     * @return creatorFid Cast creator's FID
     * @return highestBidder Current leader
     * @return highestBidderFid Leader's FID
     * @return highestBid Leading bid (USDC)
     * @return lastBidAt Last bid timestamp
     * @return endTime End time (extensible)
     * @return bids Bid count
     * @return state Auction state (may not reflect current time)
     * @return params Auction parameters
     * @dev Use getAuction() for calculated state
     */
    function auctions(bytes32 castHash)
        external
        view
        returns (
            address creator,
            uint96 creatorFid,
            address highestBidder,
            uint96 highestBidderFid,
            uint256 highestBid,
            uint40 lastBidAt,
            uint40 endTime,
            uint32 bids,
            AuctionState state,
            AuctionParams memory params
        );
}
