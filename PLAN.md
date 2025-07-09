# Collectible Casts Implementation Plan

## Overview
This document outlines the TDD implementation approach for the Collectible Casts system. We'll build five modular, immutable contracts following strict test-driven development principles.

## Architecture Summary

```
┌─────────────────┐
│ CollectibleCast │ (Core ERC-1155 token)
└────────┬────────┘
         │ references
         ├─── Metadata (Token/contract metadata)
         ├─── Minter (Mint authorization)
         ├─── TransferValidator (Transfer rules)
         └─── Royalties (ERC-2981 5% royalty)

┌─────────────┐
│   Auction   │ (Auction logic, interacts with Minter to mint tokens)
└─────────────┘
```

## Development Phases

### Phase 1: Interfaces and Base Structure
- Define all contract interfaces
- Set up directory structure
- Create shared test utilities

### Phase 2: Core Token Contract (CollectibleCast)
**Test scenarios:**
- Token minting with max supply = 1 enforcement
- Cast hash to FID mapping storage and retrieval
- EIP-2981 royalty info (5% total: 4.5% creator, 0.5% protocol)
- Module management (set/update Metadata, Minter, TransferValidator)
- Owner-only module updates
- Proper event emissions

**Key features:**
- Use cast hash (bytes32) as token ID
- Store castHash => FID mapping
- Implement modular architecture with updateable modules
- Override transfer functions to check TransferValidator
- Add exists() function to check if tokens have been minted
- Emit URI event when metadata module changes (ERC-1155 standard)

### Phase 3: Metadata Contract
**Test scenarios:**
- Setting/updating base URI
- Contract-level metadata retrieval
- Token-level metadata construction
- Owner-only updates

**Key features:**
- Store pointer to offchain API
- Implement OpenSea-compatible metadata functions

### Phase 4: Minter Contract
**Test scenarios:**
- Adding/removing minters
- Minting authorization checks
- Multi-minter support
- Event emissions for minter changes
- Only authorized minters can mint

**Key features:**
- Owner-managed allowlist
- Simple authorization checks
- Events for allowlist changes

### Phase 5: TransferValidator Contract
**Test scenarios:**
- Transfer blocking when disabled
- Transfer allowing when enabled
- Operator allowlist functionality
- Owner can always transfer their own tokens when enabled
- Third-party operators must be on allowlist

**Key features:**
- One-way transfer enable switch
- Operator allowlist for marketplace curation
- Events for operator changes
- Documented unused parameters for interface compliance

### Phase 5.5: Royalties Contract
**Test scenarios:**
- Fixed 5% royalty to creator
- Proper calculation with no overflow
- Returns zero for unminted tokens
- Handles all edge cases (zero price, max price)

**Key features:**
- ERC-2981 compliant
- BPS_DENOMINATOR constant for clarity
- Simple, immutable implementation

### Phase 6: Auction Contract - Core Bidding
**Test scenarios:**
- EIP-712 signature validation
- Opening bid validation (>= 1 USDC)
- Overbid validation (>= current + max(1 USDC, 10%))
- USDC permit functionality
- Auction parameter validation from signature
- Signature expiration checks
- State transitions and timing

**Key features:**
- Backend-signed auction parameters
- USDC escrow with transferFrom
- Permit support for gasless approvals
- Anti-sniping extension logic
- Comprehensive event emissions

### Phase 7: Auction Contract - Settlement & Refunds
**Test scenarios:**
- Permissionless settlement after auction end
- Configurable protocol fee (default 10%)
- Token minting on settlement
- Automatic refund on overbid
- Manual refund claiming on transfer failure
- Batch settlement functionality
- USDC blacklist handling

**Key features:**
- Pull-pattern refunds as fallback
- Batch operations for efficiency
- Robust error handling

### Phase 8: Integration Testing
**Test scenarios:**
- Full auction lifecycle (create, bid, overbid, settle)
- Multiple concurrent auctions
- Edge cases (blacklisted addresses, reverting contracts)
- Module interaction testing
- Gas usage validation

### Phase 9: Deployment & Verification
- Deployment scripts for all contracts
- Module connection and configuration
- Ownership setup
- Initial parameter configuration

## Testing Strategy

Following TDD principles from CLAUDE.md:
1. **RED**: Write failing test first
2. **GREEN**: Implement minimal code to pass
3. **REFACTOR**: Improve while keeping tests green
4. **COMMIT**: Only commit with all tests passing

Each contract will have:
- Unit tests for every function
- Fuzz tests for all parameterized functions
- Integration tests for contract interactions
- Gas optimization tests
- Failure mode tests

## Configuration Parameters

### Auction Contract
- Protocol fee recipient address
- Fee split (90/10 default)
- Base USDC address (immutable)

### CollectibleCast Token
- Metadata contract address
- Minter contract address  
- TransferValidator contract address
- Royalty configuration (5% default)

### Auction Parameters (per auction, via signature)
- Opening bid amount (minBid)
- Bid increment percentage (minBidIncrement)
- Initial duration
- Extension duration
- Extension threshold
- Protocol fee percentage

## Security Considerations

1. **Reentrancy**: Use checks-effects-interactions pattern
2. **Access Control**: Owner-only functions clearly marked
3. **Signature Validation**: Proper EIP-712 implementation
4. **Integer Overflow**: Solidity 0.8.x built-in protection
5. **USDC Integration**: Handle blacklist edge cases
6. **Immutability**: Contracts non-upgradeable by design

## Implementation Status

### Completed ✅
- All core contracts implemented with 100% test coverage
- 181 comprehensive tests including fuzz tests
- EIP-712 signature validation working perfectly
- Modular architecture allows future extensibility
- Deployment scripts ready for mainnet

### Recent Updates
- Upgraded 83 tests to fuzz tests for better coverage
- Simplified Auction contract logic and error handling
- Removed permit fallback logic - now fails fast
- Standardized all imports to use openzeppelin-contracts
- Removed unused OpenZeppelin remapping from foundry.toml

### Architecture Decisions
- Bytes32 castHash as token ID works well with marketplaces
- Module system provides read/gate functionality (not state modification)
- One-way switches prevent accidental misconfiguration
- No burn, pause, or supply tracking by design (KISS principle)