# CollectibleCasts Deployment Scripts

This directory contains deployment scripts for the CollectibleCasts contract suite, following the Farcaster deployment patterns.

## Overview

The deployment uses the ImmutableCreate2Factory for deterministic deployments across chains. This ensures that contracts have the same addresses on all networks where the factory is deployed.

**Note**: This deployment is configured specifically for Base mainnet. The USDC address is hardcoded to Base's USDC token (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913).

## Scripts

- **ImmutableCreate2Deployer.sol** - Base contract for CREATE2 deployments (from Farcaster)
- **DeployCollectibleCasts.s.sol** - Main deployment script with lifecycle methods

## Deployment Process

### 1. Setup Environment

Copy `.env.example` to `.env` and fill in the required values:

```bash
cp .env.example .env
```

Required environment variables:
- `OWNER_ADDRESS` - Contract owner address
- `TREASURY_ADDRESS` - Treasury for protocol fees
- `BACKEND_SIGNER_ADDRESS` - Backend signer for auction authorizations

### 2. Deploy Contracts

For testnet deployment:
```bash
forge script script/DeployCollectibleCasts.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

For mainnet deployment with verification:
```bash
forge script script/DeployCollectibleCasts.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast --verify
```

### 3. Alternative Wallet Options

Instead of `--private-key`, you can use:
- `--ledger` - Hardware wallet support
- `--trezor` - Trezor support  
- `--mnemonic` - Mnemonic phrases
- `--interactive` - Interactive key entry

## Deployment Order

The contracts are deployed in this specific order to handle dependencies:

1. **CollectibleCast** - Main ERC-1155 token contract
2. **Metadata** - Token metadata module
3. **Minter** - Minting access control (depends on CollectibleCast)
4. **TransferValidator** - Transfer restrictions module
5. **Royalties** - ERC-2981 royalty implementation
6. **Auction** - Auction system (depends on Minter and USDC)

## Post-Deployment Configuration

The deployment script automatically:
- Sets all modules on CollectibleCast
- Allows Auction contract to mint tokens
- Adds backend signer as auction authorizer
- Transfers ownership to the specified owner address

## Base Mainnet Configuration

The deployment is configured for Base mainnet with USDC hardcoded to: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

## Deterministic Addresses

By using CREATE2, contracts will have the same addresses across all networks where the ImmutableCreate2Factory (0x0000000000FFe8B47B3e2130213B802212439497) is deployed.

To use custom salts for specific addresses, set the CREATE2_SALT environment variables in your `.env` file.

## Testing Deployment

Run the deployment test suite:
```bash
forge test --match-contract DeployCollectibleCastsTest
```

Note: Fork tests require a valid RPC URL in the `FORK_RPC_URL` environment variable.