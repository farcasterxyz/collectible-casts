// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {ImmutableCreate2Deployer} from "./ImmutableCreate2Deployer.sol";

import {CollectibleCasts} from "../src/CollectibleCasts.sol";
import {Auction} from "../src/Auction.sol";

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

    function run() public returns (Contracts memory contracts) {
        bool broadcast = vm.envOr("BROADCAST", true);
        DeploymentParams memory params = loadDeploymentParams();

        console.log("");
        console.log("========================================");
        console.log("Deploying CollectibleCasts contracts...");
        console.log("========================================");
        console.log("Caller:", msg.sender);
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

    function runDeploy(bool broadcast, DeploymentParams memory params) internal returns (Contracts memory) {
        Addresses memory addrs;

        addrs.collectibleCast = register(
            "CollectibleCasts",
            params.salts.collectibleCast,
            type(CollectibleCasts).creationCode,
            abi.encode(params.deployer, params.baseURI)
        );
        addrs.auction = register(
            "Auction",
            params.salts.auction,
            type(Auction).creationCode,
            abi.encode(addrs.collectibleCast, params.usdc, params.treasury, params.deployer)
        );

        deploy(broadcast);

        return Contracts({collectibleCast: CollectibleCasts(addrs.collectibleCast), auction: Auction(addrs.auction)});
    }

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
        contracts.auction.transferOwnership(params.owner);

        console.log("Configuration complete!");
    }

    function loadDeploymentParams() internal view returns (DeploymentParams memory params) {
        params.deployer = vm.envOr("DEPLOYER_ADDRESS", msg.sender);
        params.owner = vm.envOr("OWNER_ADDRESS", params.deployer);
        params.treasury = vm.envAddress("TREASURY_ADDRESS");
        params.usdc = vm.envAddress("USDC_ADDRESS");
        params.backendSigner = vm.envAddress("BACKEND_SIGNER_ADDRESS");
        params.baseURI = vm.envOr("BASE_URI", string("https://api.farcaster.xyz/v2/cast-collectibles/metadata?id="));

        params.salts = Salts({
            collectibleCast: vm.envOr("COLLECTIBLE_CAST_CREATE2_SALT", bytes32(0)),
            auction: vm.envOr("AUCTION_CREATE2_SALT", bytes32(0))
        });

        return params;
    }
}
