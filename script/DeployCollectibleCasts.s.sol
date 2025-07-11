// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {ImmutableCreate2Deployer} from "./ImmutableCreate2Deployer.sol";

// Import all our contracts
import {CollectibleCasts} from "../src/CollectibleCasts.sol";
import {Auction} from "../src/Auction.sol";

/**
 * @title DeployCollectibleCasts
 * @notice Deployment script for the CollectibleCasts contract suite
 *         Following the Farcaster deployment pattern
 */
contract DeployCollectibleCasts is ImmutableCreate2Deployer {
    struct Salts {
        bytes32 collectibleCast;
        bytes32 auction;
    }

    struct DeploymentParams {
        address deployer;
        address owner;
        address treasury;
        address usdc;
        address backendSigner;
        string baseURI;
        Salts salts;
    }

    struct Addresses {
        address collectibleCast;
        address auction;
    }

    struct Contracts {
        CollectibleCasts collectibleCast;
        Auction auction;
    }

    /**
     * @notice Main entry point for deployment
     */
    function run() public returns (Contracts memory contracts) {
        bool broadcast = vm.envOr("BROADCAST", true);
        DeploymentParams memory params = loadDeploymentParams();

        console.log("");
        console.log("========================================");
        console.log("Deploying CollectibleCasts contracts...");
        console.log("========================================");
        console.log("Deployer:", params.deployer);
        console.log("Owner:", params.owner);
        console.log("Treasury:", params.treasury);
        console.log("USDC:", params.usdc);
        console.log("Backend Signer:", params.backendSigner);
        console.log("Base URI:", params.baseURI);
        console.log("========================================");
        console.log("");

        contracts = runDeploy(broadcast, params);

        if (deploymentChanged()) {
            runSetup(broadcast, params, contracts);
        }
        console.log("");
        console.log("========================================");
        console.log("Deployment complete!");
        console.log("========================================");

        return contracts;
    }

    /**
     * @notice Deploy all contracts
     */
    function runDeploy(bool broadcast, DeploymentParams memory params) internal returns (Contracts memory) {
        Addresses memory addrs;

        // Deploy CollectibleCasts
        addrs.collectibleCast = register(
            "CollectibleCasts",
            params.salts.collectibleCast,
            type(CollectibleCasts).creationCode,
            abi.encode(params.deployer, params.baseURI)
        );

        // Deploy Auction (needs CollectibleCasts address, USDC, treasury, and owner)
        addrs.auction = register(
            "Auction",
            params.salts.auction,
            type(Auction).creationCode,
            abi.encode(addrs.collectibleCast, params.usdc, params.treasury, params.deployer)
        );

        // Deploy all registered contracts
        deploy(broadcast);

        // Return typed contract instances
        return Contracts({collectibleCast: CollectibleCasts(addrs.collectibleCast), auction: Auction(addrs.auction)});
    }

    /**
     * @notice Configure contracts post-deployment
     */
    function runSetup(bool broadcast, DeploymentParams memory params, Contracts memory contracts) internal {
        console.log("");
        console.log("========================================");
        console.log("Configuring contracts...");
        console.log("========================================");

        console.log("Allowing Auction on CollectibleCasts...");
        if (broadcast) vm.broadcast();
        contracts.collectibleCast.allowMinter(address(contracts.auction));

        console.log("Adding backend signer as authorizer...");
        if (broadcast) vm.broadcast();
        contracts.auction.allowAuthorizer(params.backendSigner);

        console.log("Transferring ownership...");
        if (broadcast) vm.broadcast();
        contracts.collectibleCast.transferOwnership(params.owner);

        if (broadcast) vm.broadcast();
        contracts.auction.transferOwnership(params.owner);

        console.log("Configuration complete!");
    }

    /**
     * @notice Load deployment parameters from environment
     */
    function loadDeploymentParams() internal view returns (DeploymentParams memory params) {
        params.deployer = vm.envOr("DEPLOYER_ADDRESS", msg.sender);
        params.owner = vm.envOr("OWNER_ADDRESS", params.deployer);
        params.treasury = vm.envAddress("TREASURY_ADDRESS");
        // Base mainnet USDC
        params.usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        params.backendSigner = vm.envAddress("BACKEND_SIGNER_ADDRESS");
        params.baseURI = vm.envOr("BASE_URI", string("https://api.farcaster.xyz/v1/collectible-cast-metadata/"));

        // Load salts from environment or use defaults
        params.salts = Salts({
            collectibleCast: vm.envOr("COLLECTIBLE_CAST_CREATE2_SALT", bytes32(0)),
            auction: vm.envOr("AUCTION_CREATE2_SALT", bytes32(0))
        });

        return params;
    }
}
