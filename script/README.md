# CollectibleCasts Deployment Scripts

This directory contains deployment scripts for the CollectibleCasts contract suite.

## Scripts

- **ImmutableCreate2Deployer.sol** - Base contract for CREATE2 deployments
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

1. **CollectibleCasts** - Main ERC-721 token contract
2. **Auction** - Auction system (depends on CollectibleCasts and USDC)

## Post-Deployment Configuration

The deployment script automatically:

- Allows Auction contract to mint tokens on CollectibleCasts
- Adds backend signer as auction authorizer
- Transfers ownership of both contracts to the specified owner address

## Testing Deployment

Run the deployment test suite:

```bash
forge test --match-contract DeployCollectibleCastsTest
```

Note: Fork tests require a valid RPC URL in the `FORK_RPC_URL` environment variable.
