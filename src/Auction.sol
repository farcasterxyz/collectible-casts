// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAuction} from "./interfaces/IAuction.sol";
import {ICollectibleCasts} from "./interfaces/ICollectibleCasts.sol";
import {IERC20Permit} from "./interfaces/IERC20Permit.sol";
import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title Auction
 * @author Farcaster
 * @notice Ascending escrowed USDC auction for Farcaster collectible casts
 * @custom:security-contact security@merklemanufactory.com
 */
contract Auction is IAuction, Ownable2Step, Pausable, EIP712 {
    /// @dev EIP-712 type hash for auction start authorization. Signed by offchain authorizer.
    bytes32 internal constant START_AUTHORIZATION_TYPEHASH = keccak256(
        "StartAuthorization(bytes32 castHash,address creator,uint96 creatorFid,address bidder,uint96 bidderFid,uint256 amount,uint64 minBid,uint16 minBidIncrementBps,uint32 duration,uint32 extension,uint32 extensionThreshold,uint16 protocolFeeBps,bytes32 nonce,uint256 deadline)"
    );

    /// @dev EIP-712 type hash for bid authorization. Signed by offchain authorizer.
    bytes32 internal constant BID_AUTHORIZATION_TYPEHASH = keccak256(
        "BidAuthorization(bytes32 castHash,address bidder,uint96 bidderFid,uint256 amount,bytes32 nonce,uint256 deadline)"
    );

    /// @dev EIP-712 type hash for auction cancellation authorization. Signed by offchain authorizer.
    bytes32 internal constant CANCEL_AUTHORIZATION_TYPEHASH =
        keccak256("CancelAuthorization(bytes32 castHash,bytes32 nonce,uint256 deadline)");

    /// @dev Basis points denominator (10,000 = 100%)
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice Collectible NFT contract
    ICollectibleCasts public immutable collectible;
    /// @notice USDC token
    IERC20 public immutable usdc;

    /// @notice Protocol fee recipient address
    address public treasury;
    /// @notice Global auction configuration parameters
    AuctionConfig public config;

    /// @notice Mapping of address to authorization status for signing
    mapping(address signer => bool authorized) public authorizers;
    /// @notice Mapping of nonce to usage status to prevent replay attacks
    mapping(bytes32 nonce => bool used) public usedNonces;
    /// @notice Mapping of cast hash to auction data
    mapping(bytes32 castHash => AuctionData data) public auctions;

    /**
     * @notice Creates auction contract
     * @param _collectibleCast NFT contract address
     * @param _usdc USDC token address
     * @param _treasury Fee recipient
     * @param _owner Contract owner
     */
    constructor(address _collectibleCast, address _usdc, address _treasury, address _owner)
        Ownable(_owner)
        EIP712("CollectibleCastsAuction", "1")
    {
        if (_collectibleCast == address(0)) revert InvalidAddress();
        if (_usdc == address(0)) revert InvalidAddress();
        if (_treasury == address(0)) revert InvalidAddress();

        collectible = ICollectibleCasts(_collectibleCast);
        usdc = IERC20(_usdc);
        treasury = _treasury;

        config = AuctionConfig({
            minBidAmount: uint32(1e6),
            minAuctionDuration: uint32(1 hours),
            maxAuctionDuration: uint32(30 days),
            maxExtension: uint32(24 hours)
        });
    }

    // ========== PUBLIC/EXTERNAL FUNCTIONS ==========

    /// @inheritdoc IAuction
    function start(
        CastData calldata cast,
        BidData calldata bidData,
        AuctionParams calldata params,
        AuthData calldata auth
    ) external whenNotPaused {
        _start(cast, bidData, params, auth);
        usdc.transferFrom(msg.sender, address(this), bidData.amount);
    }

    /// @inheritdoc IAuction
    function start(
        CastData calldata cast,
        BidData calldata bidData,
        AuctionParams calldata params,
        AuthData calldata auth,
        PermitData calldata permit
    ) external whenNotPaused {
        _start(cast, bidData, params, auth);
        _permitAndTransfer(bidData.amount, permit);
    }

    /// @inheritdoc IAuction
    function bid(bytes32 castHash, BidData calldata bidData, AuthData calldata auth) external whenNotPaused {
        (address previousBidder, uint256 previousBid) = _bid(castHash, bidData, auth);

        usdc.transferFrom(msg.sender, address(this), bidData.amount);
        usdc.transfer(previousBidder, previousBid);
        emit BidRefunded(castHash, previousBidder, previousBid);
    }

    /// @inheritdoc IAuction
    function bid(bytes32 castHash, BidData calldata bidData, AuthData calldata auth, PermitData calldata permit)
        external
        whenNotPaused
    {
        (address previousBidder, uint256 previousBid) = _bid(castHash, bidData, auth);

        _permitAndTransfer(bidData.amount, permit);
        usdc.transfer(previousBidder, previousBid);
        emit BidRefunded(castHash, previousBidder, previousBid);
    }

    /// @inheritdoc IAuction
    function settle(bytes32 castHash) external whenNotPaused {
        _settle(castHash);
    }

    /// @inheritdoc IAuction
    function batchSettle(bytes32[] calldata castHashes) external whenNotPaused {
        uint256 length = castHashes.length;
        for (uint256 i = 0; i < length; ++i) {
            _settle(castHashes[i]);
        }
    }

    /// @inheritdoc IAuction
    function batchCancel(bytes32[] calldata castHashes, AuthData[] calldata authDatas) external whenNotPaused {
        uint256 length = castHashes.length;
        if (length != authDatas.length) revert InvalidAuctionParams();

        for (uint256 i = 0; i < length; ++i) {
            _cancel(castHashes[i], authDatas[i]);
        }
    }

    /// @inheritdoc IAuction
    function cancel(bytes32 castHash, AuthData calldata auth) external whenNotPaused {
        _cancel(castHash, auth);
    }

    /// @inheritdoc IAuction
    function recover(bytes32 castHash, address refundTo) external onlyOwner {
        // Validate recovery address
        if (refundTo == address(0)) revert InvalidAddress();

        // Check auction state: must be Active or Ended
        AuctionState state = auctionState(castHash);
        if (state != AuctionState.Active && state != AuctionState.Ended) revert AuctionNotCancellable();

        // Load auction data and get refund amount
        AuctionData storage auctionData = auctions[castHash];
        uint256 refundAmount = auctionData.highestBid;

        // Mark as recovered
        auctionData.state = AuctionState.Recovered;

        // Transfer funds
        usdc.transfer(refundTo, refundAmount);

        emit AuctionRecovered(castHash, refundTo, refundAmount);
    }

    // ========== PERMISSIONED FUNCTIONS ==========

    /// @inheritdoc IAuction
    function allowAuthorizer(address authorizer) external onlyOwner {
        if (authorizer == address(0)) revert InvalidAddress();
        authorizers[authorizer] = true;
        emit AuthorizerAllowed(authorizer);
    }

    /// @inheritdoc IAuction
    function denyAuthorizer(address authorizer) external onlyOwner {
        authorizers[authorizer] = false;
        emit AuthorizerDenied(authorizer);
    }

    /// @inheritdoc IAuction
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert InvalidAddress();
        emit TreasurySet(treasury, _treasury);
        treasury = _treasury;
    }

    /// @inheritdoc IAuction
    function setAuctionConfig(AuctionConfig calldata _config) external onlyOwner {
        if (_config.minBidAmount == 0) revert InvalidAuctionParams();
        if (_config.minAuctionDuration == 0) revert InvalidAuctionParams();
        if (_config.maxAuctionDuration <= _config.minAuctionDuration) revert InvalidAuctionParams();
        if (_config.maxExtension == 0) revert InvalidAuctionParams();

        config = _config;
        emit AuctionConfigSet(_config);
    }

    /// @inheritdoc IAuction
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IAuction
    function unpause() external onlyOwner {
        _unpause();
    }

    // ========== VIEW FUNCTIONS ==========

    /// @inheritdoc IAuction
    function auctionState(bytes32 castHash) public view returns (AuctionState) {
        AuctionData storage auctionData = auctions[castHash];
        AuctionState state = auctionData.state;

        if (block.timestamp > auctionData.endTime && state == AuctionState.Active) {
            return AuctionState.Ended;
        }

        return state;
    }

    /// @inheritdoc IAuction
    function getAuction(bytes32 castHash) external view returns (AuctionData memory) {
        AuctionData memory auction = auctions[castHash];
        auction.state = auctionState(castHash);
        return auction;
    }

    /// @inheritdoc IAuction
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
    ) public view returns (bytes32) {
        bytes32 structHash;
        {
            structHash = keccak256(
                abi.encode(
                    START_AUTHORIZATION_TYPEHASH,
                    castHash,
                    creator,
                    creatorFid,
                    bidder,
                    bidderFid,
                    amount,
                    params.minBid,
                    params.minBidIncrementBps,
                    params.duration,
                    params.extension,
                    params.extensionThreshold,
                    params.protocolFeeBps,
                    nonce,
                    deadline
                )
            );
        }
        return _hashTypedDataV4(structHash);
    }

    /// @inheritdoc IAuction
    function hashBidAuthorization(
        bytes32 castHash,
        address bidder,
        uint96 bidderFid,
        uint256 amount,
        bytes32 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(BID_AUTHORIZATION_TYPEHASH, castHash, bidder, bidderFid, amount, nonce, deadline));
        return _hashTypedDataV4(structHash);
    }

    /// @inheritdoc IAuction
    function hashCancelAuthorization(bytes32 castHash, bytes32 nonce, uint256 deadline) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, castHash, nonce, deadline));
        return _hashTypedDataV4(structHash);
    }

    /// @inheritdoc IAuction
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ========== INTERNAL FUNCTIONS ==========

    /**
     * @notice Internal function to start an auction
     * @param cast Cast data including hash, creator address and FID
     * @param bidData Initial bid data including bidder FID and amount
     * @param params Auction parameters
     * @param auth Authorization signature and nonce
     */
    function _start(
        CastData calldata cast,
        BidData calldata bidData,
        AuctionParams calldata params,
        AuthData calldata auth
    ) internal {
        // Auction must not exist
        if (auctionState(cast.castHash) != AuctionState.None) revert AuctionAlreadyExists();

        // Cast token must not be minted
        if (collectible.isMinted(cast.castHash)) revert AuctionAlreadyExists();

        // Validate cast parameters
        if (cast.castHash == bytes32(0)) revert InvalidCastHash();
        if (cast.creator == address(0)) revert InvalidAddress();
        if (cast.creatorFid == 0) revert InvalidCreatorFid();

        // Validate bid amount
        if (bidData.amount < params.minBid) revert InvalidBidAmount();

        // Validate auction parameters
        _validateAuctionParams(params);

        // Verify start authorization
        if (block.timestamp > auth.deadline) revert DeadlineExpired();
        if (usedNonces[auth.nonce]) revert NonceAlreadyUsed();

        // Verify signature
        bytes32 digest = hashStartAuthorization(
            cast.castHash,
            cast.creator,
            cast.creatorFid,
            msg.sender, // bidder must be msg.sender
            bidData.bidderFid,
            bidData.amount,
            params,
            auth.nonce,
            auth.deadline
        );
        address signer = ECDSA.recover(digest, auth.signature);
        if (!authorizers[signer]) {
            revert Unauthorized();
        }

        // Mark nonce as used
        usedNonces[auth.nonce] = true;

        // Create auction
        uint40 endTime = uint40(block.timestamp + params.duration);
        auctions[cast.castHash] = AuctionData({
            creator: cast.creator,
            creatorFid: cast.creatorFid,
            highestBidder: msg.sender,
            highestBidderFid: bidData.bidderFid,
            highestBid: bidData.amount,
            lastBidAt: uint40(block.timestamp),
            endTime: endTime,
            bids: 1,
            state: AuctionState.Active,
            params: params
        });

        emit AuctionStarted(cast.castHash, cast.creator, cast.creatorFid, endTime, signer);
        emit BidPlaced(cast.castHash, msg.sender, bidData.bidderFid, bidData.amount, signer);
    }

    /**
     * @notice Internal function to place a bid
     * @param castHash Unique identifier of the cast
     * @param bidData Bid data including bidder FID and amount
     * @param auth Authorization signature and nonce
     * @return previousBidder Address of the previous highest bidder
     * @return previousBid Amount of the previous highest bid
     */
    function _bid(bytes32 castHash, BidData calldata bidData, AuthData calldata auth)
        internal
        returns (address previousBidder, uint256 previousBid)
    {
        // Auction must be active
        AuctionState state = auctionState(castHash);
        if (state != AuctionState.Active) revert AuctionNotActive();

        AuctionData storage auctionData = auctions[castHash];

        // Verify bid authorization
        if (block.timestamp > auth.deadline) revert DeadlineExpired();
        if (usedNonces[auth.nonce]) revert NonceAlreadyUsed();

        // Check signature
        bytes32 digest =
            hashBidAuthorization(castHash, msg.sender, bidData.bidderFid, bidData.amount, auth.nonce, auth.deadline);
        address signer = ECDSA.recover(digest, auth.signature);
        if (!authorizers[signer]) {
            revert Unauthorized();
        }

        // Mark nonce as used
        usedNonces[auth.nonce] = true;

        // Calculate minimum acceptable bid
        uint256 incrementAmount = (auctionData.highestBid * auctionData.params.minBidIncrementBps) / BPS_DENOMINATOR;
        uint256 minBid = auctionData.highestBid + _max(config.minBidAmount, incrementAmount);

        if (bidData.amount < minBid) revert InvalidBidAmount();

        // Store previous bidder info for refund
        previousBidder = auctionData.highestBidder;
        previousBid = auctionData.highestBid;

        // Update auction with new bid
        auctionData.highestBidder = msg.sender;
        auctionData.highestBidderFid = bidData.bidderFid;
        auctionData.highestBid = bidData.amount;
        auctionData.lastBidAt = uint40(block.timestamp);
        auctionData.bids++;

        // Check if we need to extend the auction
        uint256 timeLeft = auctionData.endTime - block.timestamp;
        if (timeLeft <= auctionData.params.extensionThreshold) {
            auctionData.endTime = uint40(auctionData.endTime + auctionData.params.extension);
            emit AuctionExtended(castHash, auctionData.endTime);
        }

        emit BidPlaced(castHash, msg.sender, bidData.bidderFid, bidData.amount, signer);
    }

    /**
     * @notice Internal function to settle an ended auction
     * @param castHash Unique identifier of the cast
     */
    function _settle(bytes32 castHash) internal {
        // Auction must be in Ended state
        AuctionState state = auctionState(castHash);
        if (state != AuctionState.Ended) revert AuctionNotEnded();

        // Mark as settled
        AuctionData storage auctionData = auctions[castHash];
        auctionData.state = AuctionState.Settled;

        // Calculate payment distribution
        uint256 totalAmount = auctionData.highestBid;
        uint256 treasuryAmount = (totalAmount * auctionData.params.protocolFeeBps) / BPS_DENOMINATOR;
        uint256 creatorAmount = totalAmount - treasuryAmount;

        // Transfer payments
        usdc.transfer(treasury, treasuryAmount);
        usdc.transfer(auctionData.creator, creatorAmount);

        // Mint NFT to the winner
        collectible.mint(auctionData.highestBidder, castHash, uint256(auctionData.creatorFid));

        emit AuctionSettled(castHash, auctionData.highestBidder, auctionData.highestBidderFid, auctionData.highestBid);
    }

    /**
     * @notice Internal function to cancel an auction
     * @param castHash Unique identifier of the cast
     * @param auth Authorization signature and nonce
     */
    function _cancel(bytes32 castHash, AuthData calldata auth) internal {
        // Auction must be active or ended (not settled or cancelled)
        AuctionState state = auctionState(castHash);
        if (state != AuctionState.Active && state != AuctionState.Ended) revert AuctionNotCancellable();

        // Verify authorization
        if (block.timestamp > auth.deadline) revert DeadlineExpired();
        if (usedNonces[auth.nonce]) revert NonceAlreadyUsed();

        // Validate signature
        bytes32 digest = hashCancelAuthorization(castHash, auth.nonce, auth.deadline);
        address signer = ECDSA.recover(digest, auth.signature);
        if (!authorizers[signer]) revert Unauthorized();

        // Mark nonce as used
        usedNonces[auth.nonce] = true;

        // Load refund info
        AuctionData storage auctionData = auctions[castHash];
        address refundAddress = auctionData.highestBidder;
        uint96 refundBidderFid = auctionData.highestBidderFid;
        uint256 refundAmount = auctionData.highestBid;

        // Mark as cancelled
        auctionData.state = AuctionState.Cancelled;

        // Refund the highest bidder
        usdc.transfer(refundAddress, refundAmount);
        emit BidRefunded(castHash, refundAddress, refundAmount);

        emit AuctionCancelled(castHash, refundAddress, refundBidderFid, signer);
    }

    /**
     * @notice Internal function to execute USDC permit and transfer
     * @param amount Amount of USDC to transfer
     * @param permit EIP-2612 permit data
     */
    function _permitAndTransfer(uint256 amount, PermitData calldata permit) internal {
        IERC20Permit(address(usdc)).permit(
            msg.sender, address(this), amount, permit.deadline, permit.v, permit.r, permit.s
        );
        usdc.transferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Internal function to validate auction parameters
     * @param params Auction parameters to validate
     */
    function _validateAuctionParams(AuctionParams calldata params) internal view {
        if (params.protocolFeeBps > BPS_DENOMINATOR) revert InvalidAuctionParams();

        if (params.duration < config.minAuctionDuration || params.duration > config.maxAuctionDuration) {
            revert InvalidAuctionParams();
        }

        if (params.extension == 0 || params.extension > config.maxExtension) {
            revert InvalidAuctionParams();
        }

        if (params.extensionThreshold == 0 || params.extensionThreshold > params.duration) {
            revert InvalidAuctionParams();
        }

        if (params.extension > params.duration) {
            revert InvalidAuctionParams();
        }

        if (params.minBidIncrementBps == 0 || params.minBidIncrementBps > BPS_DENOMINATOR) {
            revert InvalidAuctionParams();
        }

        if (params.minBid < config.minBidAmount) {
            revert InvalidAuctionParams();
        }
    }

    /**
     * @notice Internal function to return the maximum of two values
     * @param a First value
     * @param b Second value
     * @return Maximum value
     */
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }
}
