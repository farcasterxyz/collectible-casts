# Collectible Casts

ERC-1155 collectible casts + auction.

## Documentation

- [SPEC.md](./SPEC.md) - Complete system specification
- [PLAN.md](./PLAN.md) - Implementation plan
- [TASKS.md](./TASKS.md) - Detailed task breakdown

## Setup

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone repository
git clone <repository-url>
cd collectible-casts

# Install dependencies
forge install

# Build contracts
forge build
```

## Development

```bash
# Run tests
forge test

# Run tests with gas report
forge test --gas-report

# Format code
forge fmt

# Check coverage
forge coverage
python3 script/check-coverage.py
```

## Deployment

```bash
# Deploy to Base mainnet
forge script script/DeployCollectibleCasts.s.sol --rpc-url <BASE_RPC_URL> --broadcast
```

## Project Structure

```
src/
├── CollectibleCast.sol     # Main ERC-1155 token contract
├── Minter.sol             # Minting access control
├── Metadata.sol           # Token URI generation
├── TransferValidator.sol  # Optional transfer restrictions
├── Royalties.sol          # ERC-2981 royalty implementation
└── Auction.sol            # Dutch auction for token sales

test/                      # Comprehensive test suite (100% coverage)
script/                    # Deployment scripts
```

## License

UNLICENSED
