# Collectible Casts

A lightweight on-chain system for Farcaster users to financially support creators through collectible NFTs with ascending auctions.

## Overview

Collectible Casts allows any Farcaster cast to be collected as an ERC-721 NFT. When multiple users want to collect the same cast, an ascending auction determines the final owner and price. The winning bidder receives a unique NFT representing ownership of that cast.

**Key Features:**
- 🎨 **ERC-721 NFTs** - Each cast becomes a unique, tradeable collectible
- 🏷️ **Ascending Auctions** - Fair price discovery through competitive bidding
- 💰 **Creator Monetization** - 90% of proceeds go directly to creators
- 🔐 **Backend Authorization** - Secure auction creation with EIP-712 signatures
- ⚡ **USDC Payments** - Simple, stable payments on Base network
- 🎯 **Anti-Snipe Protection** - 15-minute extensions prevent last-second bidding

## Architecture

The system consists of two main contracts:

```
┌─────────────────┐
│ CollectibleCast │  Core ERC-721 NFT contract
│                 │  - Stores cast metadata (FID, creator)
│                 │  - Implements ERC-2981 royalties (5%)
│                 │  - Manages minter permissions
└────────┬────────┘
         │ mints tokens
┌────────▼────────┐
│    Auction      │  Handles the auction mechanics
│                 │  - USDC escrow and bidding
│                 │  - EIP-712 signature validation
│                 │  - Automatic refunds
│                 │  - Settlement and minting
└─────────────────┘
```

## Documentation

- [SPEC.md](./SPEC.md) - Complete system specification
- [PLAN.md](./PLAN.md) - Implementation plan and design decisions
- [TASKS.md](./TASKS.md) - Development history and future roadmap
- [CLAUDE.md](./CLAUDE.md) - AI assistant guidelines

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
# Run all tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run tests with high verbosity
forge test -vvv

# Run specific test
forge test --match-test testName

# Run tests with coverage
forge coverage
python3 script/check-coverage.py

# Format code
forge fmt

# Run CI-level fuzz tests (10,000 runs)
FOUNDRY_PROFILE=ci forge test
```

## Testing

The project maintains 100% test coverage across all production contracts:
- 128 comprehensive tests
- Extensive fuzz testing for edge cases
- EIP-712 signature validation tests
- Gas optimization tests

Test profiles:
- `default`: 2,048 fuzz runs (development)
- `ci`: 10,000 fuzz runs (continuous integration)
- `deep`: 50,000 fuzz runs (deep testing)

## Deployment

```bash
# Set up environment variables
export DEPLOYER_ADDRESS=<your-deployer-address>
export OWNER_ADDRESS=<contract-owner-address>
export TREASURY_ADDRESS=<protocol-treasury>
export BACKEND_SIGNER_ADDRESS=<backend-signer>
export BASE_URI=<metadata-base-uri>

# Deploy to Base mainnet
forge script script/DeployCollectibleCasts.s.sol \
  --rpc-url <BASE_RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast \
  --verify

# Deploy to testnet (Base Sepolia)
forge script script/DeployCollectibleCasts.s.sol \
  --rpc-url <BASE_SEPOLIA_RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast
```

## Contract Interfaces

### CollectibleCast

```solidity
// Minting (only allowed minters)
function mint(
    address to,
    bytes32 castHash,
    uint256 creatorFid,
    address creator,
    string memory tokenURI
) external;

// Access control
function allowMinter(address account) external onlyOwner;
function denyMinter(address account) external onlyOwner;

// Metadata
function setBaseURI(string memory baseURI) external onlyOwner;
function setTokenURIs(uint256[] memory tokenIds, string[] memory uris) external onlyOwner;

// Royalties (ERC-2981)
function royaltyInfo(uint256 tokenId, uint256 salePrice) 
    external view returns (address receiver, uint256 royaltyAmount);
```

### Auction

```solidity
// Start an auction (with backend signature)
function start(
    ICast.CastData calldata cast,
    ISignature.BidData calldata bid, 
    IAuction.AuctionParams calldata params,
    ISignature.StartAuthorization calldata auth
) external;

// Place a bid (with backend signature)
function bid(
    bytes32 castHash,
    ISignature.BidData calldata bid,
    ISignature.BidAuthorization calldata auth
) external;

// Settle completed auction (permissionless)
function settle(bytes32 castHash) external;

// USDC operations with permit
function startWithPermit(...) external;
function bidWithPermit(...) external;
```

## Key Features

### Backend Authorization
- Multiple backend signers supported via allowlist
- EIP-712 signatures prevent replay attacks
- Random nonces ensure signature uniqueness
- Configurable auction parameters per cast

### Auction Mechanics
- **Opening bid**: Minimum 1 USDC
- **Bid increment**: 10% or 1 USDC (whichever is greater)
- **Duration**: Configurable (typically 24 hours)
- **Anti-snipe**: 15-minute extension if bid placed near end
- **Auto-refund**: Previous bidder automatically refunded

### Revenue Split
- **Creator**: 90% of winning bid
- **Protocol Treasury**: 10% for growth and incentives

## Security

- ✅ 100% test coverage on all production contracts
- ✅ No external dependencies beyond OpenZeppelin
- ✅ Immutable contracts (no upgradability)
- ✅ EIP-712 signatures prevent cross-chain replay
- ✅ Checks-effects-interactions pattern
- ✅ Custom errors for gas efficiency

## Gas Costs (Approximate)

- **Starting an auction**: ~150k gas
- **Placing a bid**: ~100k gas (includes refund)
- **Settling auction**: ~120k gas (includes minting)

## Future Enhancements

The contract includes a module system for future extensibility:
- Alternative payment tokens (currently USDC only)
- Transfer restrictions (currently unrestricted)
- Enhanced metadata providers
- Batch operations for efficiency

## License

UNLICENSED (All rights reserved)

## Acknowledgments

Built with:
- [Foundry](https://github.com/foundry-rs/foundry) - Development framework
- [OpenZeppelin](https://openzeppelin.com/contracts/) - Security-audited components
- Test-Driven Development principles
- Love for the Farcaster community 💜