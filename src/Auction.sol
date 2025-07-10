// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IAuction} from "./interfaces/IAuction.sol";
import {ICollectibleCasts} from "./interfaces/ICollectibleCasts.sol";
import {IERC20Permit} from "./interfaces/IERC20Permit.sol";
import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Auction is IAuction, Ownable2Step, EIP712 {
    bytes32 private constant START_AUTHORIZATION_TYPEHASH = keccak256(
        "StartAuthorization(bytes32 castHash,address creator,uint256 creatorFid,address bidder,uint256 bidderFid,uint256 amount,uint256 minBid,uint256 minBidIncrement,uint256 duration,uint256 extension,uint256 extensionThreshold,uint256 protocolFee,bytes32 nonce,uint256 deadline)"
    );

    bytes32 private constant BID_AUTHORIZATION_TYPEHASH = keccak256(
        "BidAuthorization(bytes32 castHash,address bidder,uint256 bidderFid,uint256 amount,bytes32 nonce,uint256 deadline)"
    );

    uint256 private constant BPS_DENOMINATOR = 10000;
    uint256 private constant MIN_BID_AMOUNT = 1e6;
    uint256 private constant MIN_AUCTION_DURATION = 1 hours;
    uint256 private constant MAX_AUCTION_DURATION = 30 days;
    uint256 private constant MAX_EXTENSION = 24 hours;

    address public immutable collectibleCast;
    address public immutable usdc;

    address public treasury;

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

        collectibleCast = _collectibleCast;
        usdc = _usdc;
        treasury = _treasury;
    }

    // ========== PUBLIC/EXTERNAL FUNCTIONS ==========

    function start(CastData memory cast, BidData memory bid, AuctionParams memory params, AuthData memory auth)
        external
    {
        _start(cast, bid, params, auth);
        IERC20(usdc).transferFrom(msg.sender, address(this), bid.amount);
    }

    function start(
        CastData memory cast,
        BidData memory bid,
        AuctionParams memory params,
        AuthData memory auth,
        PermitData memory permit
    ) external {
        _start(cast, bid, params, auth);
        _permitAndTransfer(bid.amount, permit);
    }

    function bid(bytes32 castHash, BidData memory bid, AuthData memory auth) external {
        (address previousBidder, uint256 previousBid) = _bid(castHash, bid, auth);

        IERC20(usdc).transferFrom(msg.sender, address(this), bid.amount);
        if (previousBidder != address(0)) {
            IERC20(usdc).transfer(previousBidder, previousBid);
        }
    }

    function bid(bytes32 castHash, BidData memory bid, AuthData memory auth, PermitData memory permit) external {
        (address previousBidder, uint256 previousBid) = _bid(castHash, bid, auth);

        _permitAndTransfer(bid.amount, permit);
        if (previousBidder != address(0)) {
            IERC20(usdc).transfer(previousBidder, previousBid);
        }
    }

    function settle(bytes32 castHash) external {
        AuctionState state = getAuctionState(castHash);
        if (state == AuctionState.None) revert AuctionDoesNotExist();
        if (state == AuctionState.Active) revert AuctionNotEnded();
        if (state == AuctionState.Settled) revert AuctionAlreadySettled();

        // Mark as settled
        AuctionData storage auctionData = auctions[castHash];
        auctionData.settled = true;

        // Calculate payment distribution based on protocol fee
        uint256 totalAmount = auctionData.highestBid;
        uint256 treasuryAmount = (totalAmount * auctionData.params.protocolFee) / BPS_DENOMINATOR;
        uint256 creatorAmount = totalAmount - treasuryAmount;

        // Transfer payments
        IERC20(usdc).transfer(treasury, treasuryAmount);
        IERC20(usdc).transfer(auctionData.creator, creatorAmount);

        // Mint NFT to the winner
        ICollectibleCasts(collectibleCast).mint(
            auctionData.highestBidder, castHash, auctionData.creatorFid, auctionData.creator, ""
        );

        emit AuctionSettled(castHash, auctionData.highestBidder, auctionData.highestBidderFid, auctionData.highestBid);
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
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasurySet(oldTreasury, _treasury);
    }

    // ========== VIEW FUNCTIONS ==========

    function getAuctionState(bytes32 castHash) public view returns (AuctionState) {
        AuctionData storage auctionData = auctions[castHash];

        if (auctionData.endTime == 0) {
            return AuctionState.None;
        }

        if (auctionData.settled) {
            return AuctionState.Settled;
        }

        if (block.timestamp < auctionData.endTime) {
            return AuctionState.Active;
        }

        return AuctionState.Ended;
    }

    function hashBidAuthorization(
        bytes32 castHash,
        address bidder,
        uint256 bidderFid,
        uint256 amount,
        bytes32 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(BID_AUTHORIZATION_TYPEHASH, castHash, bidder, bidderFid, amount, nonce, deadline));
        return _hashTypedDataV4(structHash);
    }

    function hashStartAuthorization(
        bytes32 castHash,
        address creator,
        uint256 creatorFid,
        address bidder,
        uint256 bidderFid,
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
                    params.minBidIncrement,
                    params.duration,
                    params.extension,
                    params.extensionThreshold,
                    params.protocolFee,
                    nonce,
                    deadline
                )
            );
        }
        return _hashTypedDataV4(structHash);
    }

    function verifyBidAuthorization(
        bytes32 castHash,
        address bidder,
        uint256 bidderFid,
        uint256 amount,
        bytes32 nonce,
        uint256 deadline,
        bytes memory signature
    ) public view returns (bool) {
        if (block.timestamp > deadline) return false;

        bytes32 digest = hashBidAuthorization(castHash, bidder, bidderFid, amount, nonce, deadline);
        (address signer, ECDSA.RecoverError error,) = ECDSA.tryRecover(digest, signature);

        return error == ECDSA.RecoverError.NoError && authorizers[signer];
    }

    // Helper view to expose the domain separator for external consumers
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ========== INTERNAL FUNCTIONS ==========

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function _start(CastData memory cast, BidData memory bid, AuctionParams memory params, AuthData memory auth)
        internal
    {
        if (getAuctionState(cast.castHash) != AuctionState.None) revert AuctionAlreadyExists();

        // Validate cast hash
        if (cast.castHash == bytes32(0)) revert InvalidCastHash();

        // Validate creator
        if (cast.creator == address(0)) revert InvalidAddress();
        if (cast.creatorFid == 0) revert InvalidCreatorFid();

        // Validate auction parameters
        _validateAuctionParams(params);

        // Prevent self-bidding on own auction
        if (msg.sender == cast.creator) revert SelfBidding();

        // Verify authorization
        bytes32 digest = hashStartAuthorization(
            cast.castHash,
            cast.creator,
            cast.creatorFid,
            msg.sender, // bidder must be msg.sender
            bid.bidderFid,
            bid.amount,
            params,
            auth.nonce,
            auth.deadline
        );

        // Check deadline
        if (block.timestamp > auth.deadline) revert DeadlineExpired();

        // Verify signature
        (address signer, ECDSA.RecoverError error,) = ECDSA.tryRecover(digest, auth.signature);
        if (error != ECDSA.RecoverError.NoError || !authorizers[signer]) {
            revert UnauthorizedBidder();
        }

        // Check nonce
        if (usedNonces[auth.nonce]) revert NonceAlreadyUsed();
        usedNonces[auth.nonce] = true;

        // Validate bid amount
        if (bid.amount < params.minBid) revert InvalidBidAmount();

        // Create auction
        AuctionData storage auctionData = auctions[cast.castHash];
        auctionData.creator = cast.creator;
        auctionData.creatorFid = cast.creatorFid;
        auctionData.highestBidder = msg.sender;
        auctionData.highestBidderFid = bid.bidderFid;
        auctionData.highestBid = bid.amount;
        auctionData.lastBidAt = block.timestamp;
        auctionData.endTime = block.timestamp + params.duration;
        auctionData.params = params;

        emit AuctionStarted(cast.castHash, cast.creator, cast.creatorFid);
        emit BidPlaced(cast.castHash, msg.sender, bid.bidderFid, bid.amount);
    }

    function _bid(bytes32 castHash, BidData memory bid, AuthData memory auth)
        internal
        returns (address previousBidder, uint256 previousBid)
    {
        AuctionState state = getAuctionState(castHash);
        if (state == AuctionState.None) revert AuctionDoesNotExist();
        if (state != AuctionState.Active) revert AuctionNotActive();

        // Get auction data to check creator
        AuctionData storage auctionData = auctions[castHash];

        // Prevent self-bidding
        if (msg.sender == auctionData.creator) revert SelfBidding();

        // Verify bid authorization
        if (
            !verifyBidAuthorization(
                castHash, msg.sender, bid.bidderFid, bid.amount, auth.nonce, auth.deadline, auth.signature
            )
        ) {
            revert UnauthorizedBidder();
        }

        // Check nonce
        if (usedNonces[auth.nonce]) revert NonceAlreadyUsed();
        usedNonces[auth.nonce] = true;

        // Calculate minimum acceptable bid
        uint256 incrementAmount = (auctionData.highestBid * auctionData.params.minBidIncrement) / BPS_DENOMINATOR;
        uint256 minBid = auctionData.highestBid + max(MIN_BID_AMOUNT, incrementAmount);

        if (bid.amount < minBid) revert InvalidBidAmount();

        // Store previous bidder info for refund
        previousBidder = auctionData.highestBidder;
        previousBid = auctionData.highestBid;

        // Update auction with new bid
        auctionData.highestBidder = msg.sender;
        auctionData.highestBidderFid = bid.bidderFid;
        auctionData.highestBid = bid.amount;
        auctionData.lastBidAt = block.timestamp;

        // Check if we need to extend the auction
        uint256 timeLeft = auctionData.endTime - block.timestamp;
        if (timeLeft <= auctionData.params.extensionThreshold) {
            auctionData.endTime += auctionData.params.extension;
            emit AuctionExtended(castHash, auctionData.endTime);
        }

        emit BidPlaced(castHash, msg.sender, bid.bidderFid, bid.amount);
    }

    function _permitAndTransfer(uint256 amount, PermitData memory permit) internal {
        // Use permit
        IERC20Permit(usdc).permit(msg.sender, address(this), amount, permit.deadline, permit.v, permit.r, permit.s);

        // Transfer USDC
        IERC20(usdc).transferFrom(msg.sender, address(this), amount);
    }

    function _validateAuctionParams(AuctionParams memory params) internal pure {
        // Validate protocol fee
        if (params.protocolFee > BPS_DENOMINATOR) revert InvalidProtocolFee();

        // Validate durations
        if (params.duration < MIN_AUCTION_DURATION || params.duration > MAX_AUCTION_DURATION) {
            revert InvalidAuctionParams();
        }

        // Validate extension
        if (params.extension == 0 || params.extension > MAX_EXTENSION) {
            revert InvalidAuctionParams();
        }

        // Validate extension threshold
        if (params.extensionThreshold == 0 || params.extensionThreshold > params.duration) {
            revert InvalidAuctionParams();
        }

        // Validate extension is not greater than duration
        if (params.extension > params.duration) {
            revert InvalidAuctionParams();
        }

        // Validate minimum bid increment
        if (params.minBidIncrement == 0 || params.minBidIncrement > BPS_DENOMINATOR) {
            revert InvalidAuctionParams();
        }

        // Validate minimum bid
        if (params.minBid < MIN_BID_AMOUNT) {
            revert InvalidAuctionParams();
        }
    }
}
