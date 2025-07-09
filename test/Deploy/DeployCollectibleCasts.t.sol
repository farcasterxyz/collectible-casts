// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {DeployCollectibleCasts} from "../../script/DeployCollectibleCasts.s.sol";

// Import all contracts for testing
import {CollectibleCast} from "../../src/CollectibleCast.sol";
import {ICollectibleCast} from "../../src/interfaces/ICollectibleCast.sol";
import {Metadata} from "../../src/Metadata.sol";
import {Minter} from "../../src/Minter.sol";
import {TransferValidator} from "../../src/TransferValidator.sol";
import {Royalties} from "../../src/Royalties.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployCollectibleCastsTest
 * @notice Fork test for CollectibleCasts deployment
 */
contract DeployCollectibleCastsTest is DeployCollectibleCasts, Test {
    // Test accounts
    address public deployer = address(0x1);
    address public owner = address(0x2);
    address public treasury = address(0x3);
    address public backendSigner;
    uint256 public backendSignerKey;
    address public user = address(0x5);

    // Base mainnet USDC
    address public constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    DeployCollectibleCasts.Contracts public deployed;

    function setUp() public {
        // Fork Base mainnet
        string memory rpcUrl = vm.envString("FORK_RPC_URL");
        uint256 forkBlock = vm.envOr("FORK_BLOCK", uint256(0));

        if (forkBlock > 0) {
            vm.createSelectFork(rpcUrl, forkBlock);
        } else {
            vm.createSelectFork(rpcUrl);
        }

        // Create backend signer with known private key
        (backendSigner, backendSignerKey) = makeAddrAndKey("backend");

        // Setup environment variables
        vm.setEnv("DEPLOYER_ADDRESS", vm.toString(deployer));
        vm.setEnv("OWNER_ADDRESS", vm.toString(owner));
        vm.setEnv("TREASURY_ADDRESS", vm.toString(treasury));
        vm.setEnv("USDC_ADDRESS", vm.toString(USDC_BASE));
        vm.setEnv("BACKEND_SIGNER_ADDRESS", vm.toString(backendSigner));
        vm.setEnv("BASE_URI", "https://api.example.com/metadata/");
        vm.setEnv("BROADCAST", "false");

        // Set test salts - using bytes32(0) bypasses deployer check in ImmutableCreate2Factory
        vm.setEnv("COLLECTIBLE_CAST_CREATE2_SALT", vm.toString(bytes32(0)));
        vm.setEnv("METADATA_CREATE2_SALT", vm.toString(bytes32(0)));
        vm.setEnv("MINTER_CREATE2_SALT", vm.toString(bytes32(0)));
        vm.setEnv("TRANSFER_VALIDATOR_CREATE2_SALT", vm.toString(bytes32(0)));
        vm.setEnv("ROYALTIES_CREATE2_SALT", vm.toString(bytes32(0)));
        vm.setEnv("AUCTION_CREATE2_SALT", vm.toString(bytes32(0)));

        // Fund deployer
        vm.deal(deployer, 10 ether);

        // Use startPrank to ensure all calls come from deployer
        vm.startPrank(deployer);
        deployed = run();
        vm.stopPrank();
    }

    function test_DeploymentAddresses() public view {
        // Verify all addresses are non-zero
        assertTrue(address(deployed.collectibleCast) != address(0), "CollectibleCast should be deployed");
        assertTrue(address(deployed.metadata) != address(0), "Metadata should be deployed");
        assertTrue(address(deployed.minter) != address(0), "Minter should be deployed");
        assertTrue(address(deployed.transferValidator) != address(0), "TransferValidator should be deployed");
        assertTrue(address(deployed.royalties) != address(0), "Royalties should be deployed");
        assertTrue(address(deployed.auction) != address(0), "Auction should be deployed");
    }

    function test_CollectibleCastConfiguration() public view {
        // Check modules are set correctly
        assertEq(deployed.collectibleCast.metadata(), address(deployed.metadata), "Metadata module incorrect");
        assertEq(deployed.collectibleCast.minter(), address(deployed.minter), "Minter module incorrect");
        assertEq(deployed.collectibleCast.transferValidator(), address(deployed.transferValidator), "TransferValidator module incorrect");
        assertEq(deployed.collectibleCast.royalties(), address(deployed.royalties), "Royalties module incorrect");

        // Check ownership
        assertEq(deployed.collectibleCast.owner(), deployer, "CollectibleCast owner incorrect");
        assertEq(deployed.collectibleCast.pendingOwner(), owner, "CollectibleCast owner incorrect");
    }

    function test_MinterConfiguration() public view {
        // Check token address
        assertEq(address(deployed.minter.token()), address(deployed.collectibleCast), "Minter token incorrect");

        // Check auction is allowed
        assertTrue(deployed.minter.allowed(address(deployed.auction)), "Auction should be allowed to mint");

        // Check ownership
        assertEq(deployed.minter.owner(), deployer, "Minter owner incorrect");
        assertEq(deployed.minter.pendingOwner(), owner, "Minter owner incorrect");
    }

    function test_AuctionConfiguration() public view {
        // Check immutable configuration
        assertEq(deployed.auction.minter(), address(deployed.minter), "Auction minter incorrect");
        assertEq(deployed.auction.usdc(), USDC_BASE, "Auction USDC incorrect");
        assertEq(deployed.auction.treasury(), treasury, "Auction treasury incorrect");

        // Check backend signer is authorized
        assertTrue(deployed.auction.authorizers(backendSigner), "Backend signer should be authorized");

        // Check ownership
        assertEq(deployed.auction.owner(), deployer, "Auction owner incorrect");
        assertEq(deployed.auction.pendingOwner(), owner, "Auction owner incorrect");
    }

    function test_MetadataConfiguration() public view {
        // Check base URI
        assertEq(deployed.metadata.baseURI(), "https://api.example.com/metadata/", "Base URI incorrect");

        // Check ownership
        assertEq(deployed.metadata.owner(), deployer, "Metadata owner incorrect");
        assertEq(deployed.metadata.pendingOwner(), owner, "Metadata owner incorrect");
    }

    function test_TransferValidatorConfiguration() public view {
        // Check transfers are disabled by default
        assertFalse(deployed.transferValidator.transfersEnabled(), "Transfers should be disabled by default");

        // Check ownership
        assertEq(deployed.transferValidator.owner(), deployer, "TransferValidator owner incorrect");
        assertEq(deployed.transferValidator.pendingOwner(), owner, "TransferValidator owner incorrect");
    }

    function test_EndToEndAuctionFlow() public {
        // This test simulates a complete auction flow

        // Setup cast data
        bytes32 castHash = keccak256("test-cast");
        address creator = address(0x100);
        uint256 creatorFid = 12345;

        // Setup bidder
        address bidder = address(0x200);
        uint256 bidderFid = 54321;
        uint256 bidAmount = 1e6; // 1 USDC

        // Fund bidder with USDC
        deal(USDC_BASE, bidder, bidAmount * 2);

        // Create auction parameters
        IAuction.CastData memory castData = IAuction.CastData({
            castHash: castHash,
            creator: creator,
            creatorFid: creatorFid
        });

        IAuction.BidData memory bidData = IAuction.BidData({
            bidderFid: bidderFid,
            amount: bidAmount
        });

        IAuction.AuctionParams memory params = IAuction.AuctionParams({
            minBid: 1e6,
            minBidIncrement: 1000, // 10%
            duration: 24 hours,
            extension: 15 minutes,
            extensionThreshold: 15 minutes,
            protocolFee: 1000 // 10%
        });

        // Create signature (in real scenario, this would come from backend)
        bytes32 nonce = keccak256("test-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        // For testing, we'll use the backend signer to create a valid signature
        vm.startPrank(backendSigner);
        bytes32 messageHash = deployed.auction.hashStartAuthorization(
            castHash,
            creator,
            creatorFid,
            bidder,
            bidderFid,
            bidAmount,
            params,
            nonce,
            deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendSignerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        IAuction.AuthData memory auth = IAuction.AuthData({
            nonce: nonce,
            deadline: deadline,
            signature: signature
        });

        // Approve USDC
        vm.startPrank(bidder);
        IERC20(USDC_BASE).approve(address(deployed.auction), bidAmount);

        // Start auction
        deployed.auction.start(castData, bidData, params, auth);
        vm.stopPrank();

        // Verify auction started
        (
            address auctionCreator,
            uint256 auctionCreatorFid,
            address highestBidder,
            uint256 highestBidderFid,
            uint256 highestBid,
            uint256 endTime,
            bool settled,
            IAuction.AuctionParams memory auctionParams
        ) = deployed.auction.auctions(castHash);
        assertEq(highestBid, bidAmount, "Auction should have correct highest bid");

        // Fast forward to end
        vm.warp(block.timestamp + 25 hours);

        // Settle auction
        vm.prank(user); // Anyone can settle
        deployed.auction.settle(castHash);

        // Verify token was minted
        uint256 balance = deployed.collectibleCast.balanceOf(bidder, uint256(castHash));
        assertEq(balance, 1, "Bidder should have received token");

        // Verify payments
        uint256 creatorBalance = IERC20(USDC_BASE).balanceOf(creator);
        uint256 treasuryBalance = IERC20(USDC_BASE).balanceOf(treasury);

        uint256 expectedCreatorAmount = (bidAmount * 9000) / 10000; // 90%
        uint256 expectedTreasuryAmount = (bidAmount * 1000) / 10000; // 10%

        assertEq(creatorBalance, expectedCreatorAmount, "Creator should receive 90%");
        assertEq(treasuryBalance, expectedTreasuryAmount, "Treasury should receive 10%");
    }

    function test_RoyaltyInfo() public {
        // Deploy and mint a token
        bytes32 castHash = keccak256("royalty-test");
        address creator = address(0x300);
        uint256 tokenId = uint256(castHash);

        // Mint token directly (as auction would)
        vm.prank(address(deployed.auction));
        deployed.minter.mint(creator, castHash, 12345, creator);

        // Check royalty info
        (address receiver, uint256 royaltyAmount) = deployed.collectibleCast.royaltyInfo(tokenId, 1000);

        assertEq(receiver, creator, "Royalty receiver should be creator");
        assertEq(royaltyAmount, 50, "Royalty should be 5%"); // 5% of 1000 = 50
    }
}
