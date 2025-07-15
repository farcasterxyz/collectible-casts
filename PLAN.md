# Collectible Casts Implementation Plan

## Overview

This document outlines the implementation approach for the Collectible Casts system. We've built a minimal, auditable contract suite following test-driven development principles.

## Current Architecture

```
┌─────────────────┐
│ CollectibleCast │ (Core ERC-721 NFT token)
└────────┬────────┘
         │
         └─── No external modules (simplified design)

┌─────────────┐
│   Auction   │ (Auction logic - mints tokens via CollectibleCast)
└─────────────┘
```

## Completed Implementation

### Phase 1: Core Token Contract (CollectibleCast) ✅

**What we built:**

- ERC-721 NFT contract (converted from ERC-1155)
- Uses cast hash (bytes32) as token ID
- Stores creator FID and address for each token
- Implements ERC-2981 royalty standard (5% to creator)
- Minter allowlist for access control
- Flexible metadata system with per-token URIs

**Key features implemented:**

- Token name: "CollectibleCast", symbol: "CAST"
- Batch metadata updates for backfilling
- Contract-level metadata support
- `exists()` function to check if token is minted
- 100% test coverage with 53 tests

### Phase 2: Auction Contract ✅

**What we built:**

- Clean three-function interface: `start()`, `bid()`, `settle()`
- EIP-712 signature validation for backend authorization
- USDC-only payments (hardcoded for simplicity)
- Automatic refunds when outbid
- Anti-snipe extensions (15 minutes)
- 90/10 creator/treasury split

**Key features implemented:**

- Multiple backend signers supported
- Random bytes32 nonces prevent replay attacks
- Bidder FID tracking for Farcaster integration
- USDC permit support for gasless approvals
- Self-bidding prevention
- 100% test coverage with 73 tests

### Phase 3: Deployment Infrastructure ✅

**What we built:**

- Production-ready deployment script
- Uses ImmutableCreate2 for deterministic addresses
- Follows Farcaster deployment patterns
- Configured for Base mainnet USDC

## Design Decisions & History

### Major Refactoring: ERC-1155 → ERC-721

We converted from ERC-1155 to ERC-721 because:

- Each cast is unique (non-fungible)
- Simpler mental model and implementation
- Better marketplace compatibility
- No need for batch transfers or amounts

### Removed Components

We simplified the architecture by removing:

- **Metadata module**: Integrated directly into CollectibleCast
- **Minter module**: Integrated directly into CollectibleCast
- **TransferValidator module**: Removed entirely (unrestricted transfers)
- **Royalties module**: Integrated directly into CollectibleCast

This consolidation resulted in:

- Fewer contracts to deploy and manage
- Reduced gas costs
- Simpler upgrade paths
- Easier to audit and understand

### Module System

While we kept the `setModule()` function for future extensibility, it currently always reverts with `InvalidModule()`. This preserves the upgrade path without adding complexity.

## Testing Strategy

We followed strict TDD principles:

1. **RED**: Write failing test first
2. **GREEN**: Implement minimal code to pass
3. **REFACTOR**: Improve while keeping tests green
4. **COMMIT**: Only commit with all tests passing

Results:

- 128 total tests
- 100% coverage on both production contracts
- Extensive fuzz testing (10,000+ runs per test in CI)
- Edge cases thoroughly covered

## Security Considerations

1. **Simplicity**: Minimal attack surface through simple design
2. **Immutability**: Contracts are non-upgradeable
3. **Access Control**: Owner functions clearly separated
4. **Signature Security**: Proper EIP-712 implementation
5. **No Reentrancy**: Checks-effects-interactions pattern
6. **USDC Integration**: Direct transfers (no blacklist handling)

## Configuration & Deployment

### Immutable Configuration

- **Auction Contract**:
  - CollectibleCast address
  - USDC address (Base mainnet)
  - Treasury address
- **CollectibleCast Contract**:
  - Owner address
  - Base metadata URI

### Configurable Parameters

- **Per Auction** (via backend signature):
  - Minimum bid amount
  - Bid increment percentage
  - Duration (typically 24 hours)
  - Extension settings
  - Protocol fee percentage

### Backend Signers

- Multiple signers supported via allowlist
- Can be added/removed by owner
- Sign auction parameters and bid authorizations

## Future Considerations

### Potential Enhancements

1. **Transfer restrictions**: Could re-add validator module if needed
2. **Metadata upgrades**: Module system allows future metadata providers
3. **Alternative payment tokens**: Could add ERC-20 support
4. **Batch operations**: Could add batch settling
5. **USDC blacklist handling**: Could add pull-pattern refunds

### Upgrade Path

The module system (`setModule()`) provides a clean upgrade path:

```solidity
// Currently always reverts
function setModule(bytes32, address) external onlyOwner {
    revert InvalidModule();
}
```

This can be extended to support new modules without changing core logic.

## Summary

We've successfully built a minimal, secure, and extensible Collectible Casts system:

- ✅ ERC-721 NFT with royalties
- ✅ Auction system with backend authorization
- ✅ 100% test coverage
- ✅ Production-ready deployment scripts
- ✅ Clean, auditable codebase
- ✅ Future extensibility via module system

The system is ready for deployment to Base mainnet.

# Implementation history and status

## Current Status: COMPLETE ✅

The Collectible Casts system is fully implemented and ready for deployment:

- ✅ CollectibleCast (ERC-721 NFT with integrated features)
- ✅ Auction (Complete implementation with EIP-712 signatures)
- ✅ 128 comprehensive tests with 100% coverage
- ✅ Production-ready deployment scripts

## Implementation Timeline

### Phase 1: Initial Design & Architecture (Completed)

We started with a modular architecture featuring separate contracts for each concern:

- CollectibleCast (ERC-1155)
- Metadata module
- Minter module
- TransferValidator module
- Royalties module
- Auction contract

### Phase 2: Core Implementation (Completed)

Following TDD principles (RED → GREEN → REFACTOR → COMMIT), we implemented:

#### CollectibleCast Token (Initially ERC-1155)

- Cast hash as token ID
- FID and creator storage
- Module management system
- Minter allowlist
- Max supply of 1 per cast
- 100% test coverage

#### Supporting Modules

- **Metadata**: URI management with base URI and per-token overrides
- **Minter**: Authorization layer for minting access
- **TransferValidator**: Optional transfer restrictions with operator allowlist
- **Royalties**: ERC-2981 implementation with 5% to creator

#### Auction Contract

Implemented in phases:

1. **Foundation**: Constructor, configuration, authorizer management
2. **EIP-712**: Domain separator, signature structures, verification
3. **Bidding Logic**: Start function, bid validation, auto-refunds
4. **Settlement**: Payment distribution, token minting, events

Key features:

- Three clean functions: `start()`, `bid()`, `settle()`
- Multiple backend authorizers
- Random bytes32 nonces
- Anti-snipe extensions
- USDC permit support
- 90/10 creator/treasury split

### Phase 3: Major Refactoring (Completed)

#### ERC-1155 → ERC-721 Conversion

Realized that ERC-721 was more appropriate because:

- Each cast is unique (truly non-fungible)
- Simpler implementation and mental model
- Better marketplace support
- No need for batch operations

The conversion involved:

- Updating base contract from ERC1155 to ERC721
- Changing balance tracking (amount → ownership)
- Updating transfer functions
- Converting `uri()` to `tokenURI()`
- Maintaining 100% test coverage throughout

#### Architecture Simplification

Removed the module system in favor of integrated functionality:

- **Before**: 6 separate contracts with complex interactions
- **After**: 2 contracts with clear responsibilities

Benefits:

- Reduced deployment complexity
- Lower gas costs
- Easier to audit
- Simpler upgrade path

### Phase 4: Testing & Hardening (Completed)

#### Test Coverage Achievements

- Converted 83 unit tests to fuzz tests
- Added edge case coverage
- Achieved 100% coverage on all metrics
- CI-level testing with 10,000 fuzz runs

#### Final Polish

- Removed unused imports and dependencies
- Standardized error handling
- Optimized gas usage
- Comprehensive documentation

## Deployment Readiness

### What's Ready

1. **Smart Contracts**:

   - CollectibleCast.sol (ERC-721 with royalties)
   - Auction.sol (full auction implementation)
   - Both with 100% test coverage

2. **Deployment Infrastructure**:

   - DeployCollectibleCasts.s.sol script
   - ImmutableCreate2 for deterministic addresses
   - Base mainnet configuration

3. **Testing**:
   - 128 comprehensive tests
   - Fuzz testing at CI level
   - Edge cases covered

### Deployment Checklist

- [ ] Final audit/review
- [ ] Deploy to Base testnet
- [ ] Integration testing with backend
- [ ] Deploy to Base mainnet
- [ ] Verify contracts on Basescan
- [ ] Update documentation with addresses

## Lessons Learned

### What Worked Well

1. **TDD Approach**: Caught issues early and ensured quality
2. **Fuzz Testing**: Discovered edge cases we wouldn't have thought of
3. **Simplification**: Removing modules made the system much cleaner
4. **ERC-721**: Better fit than ERC-1155 for this use case

### What We'd Do Differently

1. **Start with ERC-721**: Would have saved refactoring time
2. **Skip modules initially**: YAGNI principle - we didn't need them
3. **Earlier fuzz testing**: Would have caught arithmetic issues sooner

## Architecture Summary

### Final Design

```
┌─────────────────┐
│ CollectibleCast │
│   (ERC-721)     │
│                 │
│ Features:       │
│ - Royalties     │
│ - Metadata      │
│ - Minting       │
└────────┬────────┘
         │ mints
┌────────▼────────┐
│    Auction      │
│                 │
│ Features:       │
│ - EIP-712 auth  │
│ - USDC escrow   │
│ - Auto refunds  │
│ - Settlement    │
└─────────────────┘
```

### Key Invariants

1. **One collectible per cast**: Enforced by cast hash as token ID
2. **Creator compensation**: 90% of winning bid
3. **Protocol sustainability**: 10% to treasury
4. **No double minting**: AlreadyMinted check
5. **Fair auctions**: Anti-snipe extensions

## Next Steps

### Immediate (Pre-deployment)

1. Final security review
2. Deploy to testnet
3. End-to-end testing with frontend
4. Gas optimization review

### Post-deployment

1. Monitor initial auctions
2. Gather creator feedback
3. Consider enhancements:
   - Alternative payment tokens
   - Batch operations
   - Transfer restrictions (if needed)
   - Enhanced metadata

### Long-term

1. Secondary market integration
2. Cross-chain deployment
3. Advanced auction types
4. Creator tools and analytics

## Summary

We've successfully built a minimal, secure, and effective Collectible Casts system. The journey from a complex 6-contract modular system to a clean 2-contract implementation demonstrates the value of:

- Starting simple
- Following TDD principles
- Being willing to refactor
- Prioritizing user needs over architectural elegance

The system is now ready for production deployment on Base mainnet.
