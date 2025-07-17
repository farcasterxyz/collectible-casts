// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "./interfaces/IAuction.sol";
import {ICollectibleCasts} from "./interfaces/ICollectibleCasts.sol";
import {IERC20Permit} from "./interfaces/IERC20Permit.sol";
import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Auction is IAuction, Ownable2Step, Pausable, EIP712 {
    bytes32 internal constant START_AUTHORIZATION_TYPEHASH = keccak256(
        "StartAuthorization(bytes32 castHash,address creator,uint96 creatorFid,address bidder,uint96 bidderFid,uint256 amount,uint64 minBid,uint16 minBidIncrementBps,uint32 duration,uint32 extension,uint32 extensionThreshold,uint16 protocolFeeBps,bytes32 nonce,uint256 deadline)"
    );

    bytes32 internal constant BID_AUTHORIZATION_TYPEHASH = keccak256(
        "BidAuthorization(bytes32 castHash,address bidder,uint96 bidderFid,uint256 amount,bytes32 nonce,uint256 deadline)"
    );

    bytes32 internal constant CANCEL_AUTHORIZATION_TYPEHASH =
        keccak256("CancelAuthorization(bytes32 castHash,bytes32 nonce,uint256 deadline)");

    uint256 internal constant BPS_DENOMINATOR = 10_000;

    ICollectibleCasts public immutable collectible;
    IERC20 public immutable usdc;

    address public treasury;
    AuctionConfig public config;

    mapping(address => bool) public authorizers;
    mapping(bytes32 => bool) public usedNonces;
    mapping(bytes32 => AuctionData) public auctions;

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

    function start(CastData memory cast, BidData memory bidData, AuctionParams memory params, AuthData memory auth)
        external
        whenNotPaused
    {
        _start(cast, bidData, params, auth);
        usdc.transferFrom(msg.sender, address(this), bidData.amount);
    }

    function start(
        CastData memory cast,
        BidData memory bidData,
        AuctionParams memory params,
        AuthData memory auth,
        PermitData memory permit
    ) external whenNotPaused {
        _start(cast, bidData, params, auth);
        _permitAndTransfer(bidData.amount, permit);
    }

    function bid(bytes32 castHash, BidData memory bidData, AuthData memory auth) external whenNotPaused {
        (address previousBidder, uint256 previousBid) = _bid(castHash, bidData, auth);

        IERC20(usdc).transferFrom(msg.sender, address(this), bidData.amount);
        if (previousBidder != address(0)) {
            usdc.transfer(previousBidder, previousBid);
        }
    }

    function bid(bytes32 castHash, BidData memory bidData, AuthData memory auth, PermitData memory permit)
        external
        whenNotPaused
    {
        (address previousBidder, uint256 previousBid) = _bid(castHash, bidData, auth);

        _permitAndTransfer(bidData.amount, permit);
        if (previousBidder != address(0)) {
            usdc.transfer(previousBidder, previousBid);
        }
    }

    function settle(bytes32 castHash) external whenNotPaused {
        _settle(castHash);
    }

    function batchSettle(bytes32[] calldata castHashes) external whenNotPaused {
        uint256 length = castHashes.length;
        for (uint256 i = 0; i < length; ++i) {
            _settle(castHashes[i]);
        }
    }

    function cancel(bytes32 castHash, AuthData memory auth) external whenNotPaused {
        // Check auction state
        AuctionState state = auctionState(castHash);
        if (state == AuctionState.None) revert AuctionNotFound();
        if (state != AuctionState.Active) revert AuctionNotActive();

        // Verify authorization
        if (block.timestamp > auth.deadline) revert DeadlineExpired();
        if (usedNonces[auth.nonce]) revert NonceAlreadyUsed();

        // Validate signature
        bytes32 digest = hashCancelAuthorization(castHash, auth.nonce, auth.deadline);
        address signer = ECDSA.recover(digest, auth.signature);
        if (!authorizers[signer]) revert Unauthorized();

        // Mark nonce as used
        usedNonces[auth.nonce] = true;

        // Get auction data before cancelling
        AuctionData storage auctionData = auctions[castHash];
        address refundAddress = auctionData.highestBidder;
        uint256 refundAmount = auctionData.highestBid;

        // Mark as cancelled
        auctionData.state = AuctionState.Cancelled;

        // Refund the highest bidder
        if (refundAmount > 0 && refundAddress != address(0)) {
            usdc.transfer(refundAddress, refundAmount);
        }

        emit AuctionCancelled(castHash, refundAddress, signer);
    }

    // ========== PERMISSIONED FUNCTIONS ==========

    function allowAuthorizer(address authorizer) external onlyOwner {
        if (authorizer == address(0)) revert InvalidAddress();
        authorizers[authorizer] = true;
        emit AuthorizerAllowed(authorizer);
    }

    function denyAuthorizer(address authorizer) external onlyOwner {
        authorizers[authorizer] = false;
        emit AuthorizerDenied(authorizer);
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert InvalidAddress();
        emit TreasurySet(treasury, _treasury);
        treasury = _treasury;
    }

    function setAuctionConfig(AuctionConfig memory _config) external onlyOwner {
        if (_config.minBidAmount == 0) revert InvalidAuctionParams();
        if (_config.minAuctionDuration == 0) revert InvalidAuctionParams();
        if (_config.maxAuctionDuration <= _config.minAuctionDuration) revert InvalidAuctionParams();
        if (_config.maxExtension == 0) revert InvalidAuctionParams();

        config = _config;
        emit AuctionConfigSet(_config);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ========== VIEW FUNCTIONS ==========

    function auctionState(bytes32 castHash) public view returns (AuctionState) {
        AuctionData storage auctionData = auctions[castHash];

        if (auctionData.endTime == 0) {
            return AuctionState.None;
        }

        // If auction is settled or cancelled, return that state
        if (auctionData.state == AuctionState.Settled || auctionData.state == AuctionState.Cancelled) {
            return auctionData.state;
        }

        // Otherwise, check if auction is active or ended based on time
        if (block.timestamp < auctionData.endTime) {
            return AuctionState.Active;
        }

        return AuctionState.Ended;
    }

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

    function hashCancelAuthorization(bytes32 castHash, bytes32 nonce, uint256 deadline) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, castHash, nonce, deadline));
        return _hashTypedDataV4(structHash);
    }

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

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ========== INTERNAL FUNCTIONS ==========

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function _start(CastData memory cast, BidData memory bidData, AuctionParams memory params, AuthData memory auth)
        internal
    {
        if (auctionState(cast.castHash) != AuctionState.None) revert AuctionAlreadyExists();

        // Validate cast hash
        if (cast.castHash == bytes32(0)) revert InvalidCastHash();

        // Validate creator
        if (cast.creator == address(0)) revert InvalidAddress();
        if (cast.creatorFid == 0) revert InvalidCreatorFid();

        // Validate auction parameters
        _validateAuctionParams(params);

        // Verify authorization
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

        // Check deadline
        if (block.timestamp > auth.deadline) revert DeadlineExpired();

        // Verify signature
        address signer = ECDSA.recover(digest, auth.signature);
        if (!authorizers[signer]) {
            revert Unauthorized();
        }

        // Check nonce
        if (usedNonces[auth.nonce]) revert NonceAlreadyUsed();
        usedNonces[auth.nonce] = true;

        // Validate bid amount
        if (bidData.amount < params.minBid) revert InvalidBidAmount();

        // Create auction
        AuctionData storage auctionData = auctions[cast.castHash];
        auctionData.creator = cast.creator;
        auctionData.creatorFid = cast.creatorFid;
        auctionData.highestBidder = msg.sender;
        auctionData.highestBidderFid = bidData.bidderFid;
        auctionData.highestBid = bidData.amount;
        auctionData.lastBidAt = uint40(block.timestamp);
        auctionData.endTime = uint40(block.timestamp + params.duration);
        auctionData.bids = 1;
        auctionData.state = AuctionState.Active;
        auctionData.params = params;

        emit AuctionStarted(cast.castHash, cast.creator, cast.creatorFid, auctionData.endTime, signer);
        emit BidPlaced(cast.castHash, msg.sender, bidData.bidderFid, bidData.amount);
    }

    function _bid(bytes32 castHash, BidData memory bidData, AuthData memory auth)
        internal
        returns (address previousBidder, uint256 previousBid)
    {
        AuctionState state = auctionState(castHash);
        if (state == AuctionState.None) revert AuctionNotFound();
        if (state != AuctionState.Active) revert AuctionNotActive();

        AuctionData storage auctionData = auctions[castHash];

        // Verify bid authorization
        if (block.timestamp > auth.deadline) revert DeadlineExpired();
        if (usedNonces[auth.nonce]) revert NonceAlreadyUsed();

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

        emit BidPlaced(castHash, msg.sender, bidData.bidderFid, bidData.amount);
    }

    function _settle(bytes32 castHash) internal {
        AuctionState state = auctionState(castHash);
        if (state == AuctionState.None) revert AuctionNotFound();
        if (state == AuctionState.Active) revert AuctionNotEnded();
        if (state == AuctionState.Settled) revert AuctionAlreadySettled();
        if (state == AuctionState.Cancelled) revert AuctionIsCancelled();

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
        collectible.mint(auctionData.highestBidder, castHash, uint96(auctionData.creatorFid), auctionData.creator);

        emit AuctionSettled(castHash, auctionData.highestBidder, auctionData.highestBidderFid, auctionData.highestBid);
    }

    function _permitAndTransfer(uint256 amount, PermitData memory permit) internal {
        IERC20Permit(address(usdc)).permit(
            msg.sender, address(this), amount, permit.deadline, permit.v, permit.r, permit.s
        );
        usdc.transferFrom(msg.sender, address(this), amount);
    }

    function _validateAuctionParams(AuctionParams memory params) internal view {
        if (params.protocolFeeBps > BPS_DENOMINATOR) revert InvalidProtocolFee();

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
}
