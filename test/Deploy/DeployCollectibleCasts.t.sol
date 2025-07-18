// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {DeployCollectibleCasts} from "../../script/DeployCollectibleCasts.s.sol";

// Import all contracts for testing
import {CollectibleCasts} from "../../src/CollectibleCasts.sol";
import {ICollectibleCasts} from "../../src/interfaces/ICollectibleCasts.sol";
import {Auction} from "../../src/Auction.sol";
import {IAuction} from "../../src/interfaces/IAuction.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployCollectibleCastsTest
 * @notice Fork test for CollectibleCasts deployment
 */
contract DeployCollectibleCastsTest is DeployCollectibleCasts, Test {
    // Test accounts
    address public deployer = makeAddr("deployer");
    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public backendSigner;
    uint256 public backendSignerKey;
    address public user = makeAddr("user");

    address public constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    DeployCollectibleCasts.Contracts public deployed;

    function setUp() public {
        string memory rpcUrl = vm.envString("FORK_RPC_URL");
        uint256 forkBlock = vm.envOr("FORK_BLOCK", uint256(0));

        if (forkBlock > 0) {
            vm.createSelectFork(rpcUrl, forkBlock);
        } else {
            vm.createSelectFork(rpcUrl);
        }

        (backendSigner, backendSignerKey) = makeAddrAndKey("backend");

        vm.setEnv("DEPLOYER_ADDRESS", vm.toString(deployer));
        vm.setEnv("OWNER_ADDRESS", vm.toString(owner));
        vm.setEnv("TREASURY_ADDRESS", vm.toString(treasury));
        vm.setEnv("USDC_ADDRESS", vm.toString(USDC_BASE));
        vm.setEnv("BACKEND_SIGNER_ADDRESS", vm.toString(backendSigner));
        vm.setEnv("BASE_URI", "https://api.example.com/metadata/");
        vm.setEnv("BROADCAST", "false");

        vm.setEnv("COLLECTIBLE_CAST_CREATE2_SALT", vm.toString(bytes32(0)));
        vm.setEnv("TRANSFER_VALIDATOR_CREATE2_SALT", vm.toString(bytes32(0)));
        vm.setEnv("ROYALTIES_CREATE2_SALT", vm.toString(bytes32(0)));
        vm.setEnv("AUCTION_CREATE2_SALT", vm.toString(bytes32(0)));

        vm.startPrank(deployer);
        deployed = run();
        vm.stopPrank();
    }

    function test_DeploymentAddresses() public view {
        assertTrue(address(deployed.collectibleCast) != address(0), "CollectibleCasts should be deployed");
        assertTrue(address(deployed.auction) != address(0), "Auction should be deployed");
    }

    function test_CollectibleCastsConfiguration() public view {
        assertTrue(deployed.collectibleCast.minters(address(deployed.auction)), "Auction not allowed to mint");
        assertEq(deployed.collectibleCast.owner(), deployer, "CollectibleCasts owner incorrect");
        assertEq(deployed.collectibleCast.pendingOwner(), owner, "CollectibleCasts owner incorrect");
    }

    function test_AuctionConfiguration() public view {
        assertEq(
            address(deployed.auction.collectible()), address(deployed.collectibleCast), "Auction collectible incorrect"
        );
        assertEq(address(deployed.auction.usdc()), USDC_BASE, "Auction USDC incorrect");
        assertEq(deployed.auction.treasury(), treasury, "Auction treasury incorrect");
        assertTrue(deployed.auction.authorizers(backendSigner), "Backend signer should be authorized");
        assertEq(deployed.auction.owner(), deployer, "Auction owner incorrect");
        assertEq(deployed.auction.pendingOwner(), owner, "Auction owner incorrect");
    }

    function test_EndToEndAuctionFlow() public {
        // This test simulates a complete auction flow

        // Setup cast data
        bytes32 castHash = keccak256("test-cast");
        address creator = makeAddr("creator");
        uint96 creatorFid = 12345;

        // Setup bidder
        address bidder = makeAddr("bidder");
        uint96 bidderFid = 54321;
        uint256 bidAmount = 1e6; // 1 USDC

        // Fund bidder with USDC
        deal(USDC_BASE, bidder, bidAmount * 2);

        // Create auction parameters
        IAuction.CastData memory castData =
            IAuction.CastData({castHash: castHash, creator: creator, creatorFid: creatorFid});

        IAuction.BidData memory bidData = IAuction.BidData({bidderFid: bidderFid, amount: bidAmount});

        IAuction.AuctionParams memory params = IAuction.AuctionParams({
            minBid: uint64(1e6),
            minBidIncrementBps: uint16(1000), // 10%
            duration: uint32(24 hours),
            extension: uint32(15 minutes),
            extensionThreshold: uint32(15 minutes),
            protocolFeeBps: uint16(1000) // 10%
        });

        // Create signature
        bytes32 nonce = keccak256("test-nonce");
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(backendSigner);
        bytes32 messageHash = deployed.auction.hashStartAuthorization(
            castHash, creator, creatorFid, bidder, bidderFid, bidAmount, params, nonce, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendSignerKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        IAuction.AuthData memory auth = IAuction.AuthData({nonce: nonce, deadline: deadline, signature: signature});

        vm.startPrank(bidder);
        IERC20(USDC_BASE).approve(address(deployed.auction), bidAmount);

        deployed.auction.start(castData, bidData, params, auth);
        vm.stopPrank();

        // Verify auction started
        (,,,, uint256 highestBid,,,,,) = deployed.auction.auctions(castHash);
        assertEq(highestBid, bidAmount, "Auction should have correct highest bid");

        // Fast forward to end
        vm.warp(block.timestamp + 25 hours);

        // Settle auction
        vm.prank(user); // Anyone can settle
        deployed.auction.settle(castHash);

        // Verify token was minted
        uint256 balance = deployed.collectibleCast.balanceOf(bidder);
        assertEq(balance, 1, "Bidder should have received token");
        assertEq(deployed.collectibleCast.ownerOf(uint256(castHash)), bidder, "Bidder should own the token");

        // Verify payments
        uint256 creatorBalance = IERC20(USDC_BASE).balanceOf(creator);
        uint256 treasuryBalance = IERC20(USDC_BASE).balanceOf(treasury);

        uint256 expectedCreatorAmount = (bidAmount * 9000) / 10000; // 90%
        uint256 expectedTreasuryAmount = (bidAmount * 1000) / 10000; // 10%

        assertEq(creatorBalance, expectedCreatorAmount, "Creator should receive 90%");
        assertEq(treasuryBalance, expectedTreasuryAmount, "Treasury should receive 10%");
    }
}
