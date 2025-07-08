# Collectible Casts - TDD Task Breakdown

Each task follows the TDD cycle: RED → GREEN → REFACTOR → COMMIT

## Current Status: AUCTION CONTRACT COMPLETE ✅

All core contracts have been implemented with 100% test coverage:
- ✅ CollectibleCast (ERC-1155 NFT)
- ✅ Metadata (URI management)  
- ✅ Minter (Authorization layer)
- ✅ TransferValidator (Transfer controls)
- ✅ Royalties (ERC-2981 5% royalty)
- ✅ Auction (Complete implementation with 56 tests)

The Auction contract features:
- EIP-712 signature validation with multiple backend authorizers
- Three clean functions: start(), bid(), settle()
- Random bytes32 nonces from backend
- Automatic USDC refunds on overbidding
- Anti-snipe auction extensions
- 90/10 creator/treasury payment split
- Cast metadata storage for provenance

## Guiding Principles
- **KISS** (Keep It Simple, Stupid) - Choose the simplest solution
- **YAGNI** (You Aren't Gonna Need It) - Don't add functionality until needed
- **100% Test Coverage** - Every line of production code must be tested (verified with `python3 script/check-coverage.py`)
- **Minimal Interfaces** - Start with empty interfaces, add functions only when tests require them
- **Fuzz Test Upgrade** - After each GREEN phase, evaluate if unit tests can be upgraded to fuzz tests

## Coverage Verification
Before each commit, run `python3 script/check-coverage.py` to ensure 100% coverage for all production contracts. This script will fail if any production contract has less than 100% coverage on any metric (lines, statements, branches, or functions).

## Completed Phases

### Phase 1: Contract Interfaces and Test Infrastructure ✅
- Created minimal interfaces for all contracts
- Set up test infrastructure with forge-std patterns
- Removed unnecessary template files

### Phase 2: CollectibleCast Token ✅
- Implemented ERC-1155 token with OpenZeppelin v5
- Added minter authorization with allowlist
- Enforced max supply of 1 per cast
- Implemented module management with setModule pattern
- Added transfer validation hooks
- Implemented EIP-2981 royalties (5% to creator)
- Achieved 100% test coverage

### Phase 3: Metadata Contract ✅
- Implemented URI functions for contract and token metadata
- Added owner-controlled base URI management
- Achieved 100% test coverage

### Phase 4: Minter Contract ✅
- Implemented authorization with allowlist pattern
- Added mint delegation to CollectibleCast
- Achieved 100% test coverage

### Phase 5: TransferValidator Contract ✅
- Implemented one-way transfersEnabled switch
- Added operator allowlist for marketplace curation
- Correctly implemented two orthogonal concepts:
  - transfersEnabled: controls if ANY transfers are allowed
  - allowedOperators: controls third-party operators when transfers ARE enabled
- Achieved 100% test coverage

## Phase 6-8: Auction Contract ✅

The Auction contract is the most complex component. We've successfully implemented it with comprehensive testing.

### Phase 6: Auction Foundation & Configuration ✅

#### 6.1 Basic Structure ✅
- [x] RED: Write test `test_Constructor_SetsConfiguration()`
- [x] GREEN: Create Auction with immutable config (token, minter, usdc, treasury)
- [x] COMMIT: "feat: add Auction constructor with configuration"

#### 6.2 Auction Parameters ✅
- [x] RED: Write test `test_AuctionParams_StoresCorrectly()`
- [x] GREEN: Define AuctionParams struct (minBid, minBidIncrement, duration, extension, extensionThreshold)
- [x] COMMIT: "feat: add auction parameter storage"

#### 6.3 Backend Signer Setup ✅
- [x] RED: Write test `test_AllowAuthorizer_OnlyOwner()`
- [x] GREEN: Add authorizer allowlist management (supports multiple backend signers)
- [x] COMMIT: "feat: add authorizer allowlist management"

### Phase 7: Signature Validation ✅

#### 7.1 EIP-712 Domain ✅
- [x] RED: Write test `test_DomainSeparator_ComputesCorrectly()`
- [x] GREEN: Implement EIP-712 domain separator using OpenZeppelin
- [x] COMMIT: "feat: implement EIP-712 domain"

#### 7.2 Bid Authorization Structure ✅
- [x] RED: Write test `test_BidAuthorization_HashesCorrectly()`
- [x] GREEN: Define BidAuthorization struct with bidderFid and hashing
- [x] COMMIT: "feat: add bid authorization structure"

#### 7.3 Signature Verification ✅
- [x] RED: Write test `test_VerifySignature_ValidatesCorrectly()`
- [x] GREEN: Implement ECDSA signature verification with OpenZeppelin
- [x] COMMIT: "feat: implement signature verification"

- [x] RED: Write test `test_VerifySignature_RejectsExpired()`
- [x] GREEN: Add expiration check
- [x] COMMIT: "feat: add signature expiration"

- [x] RED: Write test `test_VerifySignature_PreventsReplay()`
- [x] GREEN: Add nonce tracking with random bytes32 nonces
- [x] COMMIT: "feat: prevent signature replay"

### Phase 8: Bidding Logic ✅

#### 8.1 Auction State Management ✅
- [x] RED: Write test `test_AuctionState_TracksCorrectly()`
- [x] GREEN: Define AuctionData struct with cast metadata and state derivation
- [x] COMMIT: "feat: add auction state management"

#### 8.2 Auction Start Function ✅
- [x] RED: Write test `test_Start_RequiresMinimum()`
- [x] GREEN: Validate opening bid >= minBid parameter
- [x] COMMIT: "feat: validate opening bid amount"

- [x] RED: Write test `test_Start_CreatesAuction()`
- [x] GREEN: Create auction with cast metadata and configurable duration
- [x] COMMIT: "feat: create auction with start function"

- [x] RED: Write test `test_Start_TransfersUSDC()`
- [x] GREEN: Pull USDC from first bidder
- [x] COMMIT: "feat: transfer USDC on auction start"

- [x] RED: Write test `test_Start_EmitsEvent()`
- [x] GREEN: Emit AuctionStarted and BidPlaced events
- [x] COMMIT: "feat: emit events on auction start"

#### 8.3 Bid Function ✅
- [x] RED: Write test `test_Bid_RequiresSufficientIncrease()`
- [x] GREEN: Validate bid >= currentBid * (1 + minBidIncrement)
- [x] COMMIT: "feat: validate bid increments"

- [x] RED: Write test `test_Bid_RefundsPreviousBidder()`
- [x] GREEN: Implement automatic refund
- [x] COMMIT: "feat: auto-refund previous bidder"

- [x] RED: Write test `test_Bid_ExtendsNearEnd()`
- [x] GREEN: If bid within extensionThreshold, extend by extension amount
- [x] COMMIT: "feat: implement anti-snipe extension"

#### 8.4 Additional Features Implemented ✅
- [x] Separate start(), bid(), and settle() functions for clarity
- [x] StartAuthorization struct for initial bid with full auction parameters
- [x] State machine that derives state from auction data
- [x] Comprehensive test coverage with 56 tests

### Phase 9: Settlement & Refunds ✅

#### 9.1 Settlement Validation ✅
- [x] RED: Write test `test_Settle_RevertsIfActive()`
- [x] GREEN: Check auction has ended
- [x] COMMIT: "feat: validate auction ended before settlement"

- [x] RED: Write test `test_Settle_RevertsIfAlreadySettled()`
- [x] GREEN: Prevent double settlement
- [x] COMMIT: "feat: prevent double settlement"

#### 9.2 Payment Distribution ✅
- [x] RED: Write test `test_Settle_PaysCreator90Percent()`
- [x] GREEN: Transfer 90% to creator
- [x] COMMIT: "feat: pay creator on settlement"

- [x] RED: Write test `test_Settle_PaysTreasury10Percent()`
- [x] GREEN: Transfer 10% to treasury
- [x] COMMIT: "feat: pay treasury on settlement"

#### 9.3 Token Minting ✅
- [x] RED: Write test `test_Settle_MintsToken()`
- [x] GREEN: Call minter to mint token to winner
- [x] COMMIT: "feat: mint token on settlement"

- [x] RED: Write test `test_Settle_EmitsEvent()`
- [x] GREEN: Emit AuctionSettled event
- [x] COMMIT: "feat: emit settlement event"

#### 9.4 Manual Refunds (Not Implemented)
- [ ] Manual refund functionality was not implemented as automatic refunds are handled synchronously
- [ ] Could be added in future if needed for handling USDC blacklist scenarios

### Phase 10: Edge Cases & Security (Partially Implemented)

#### 10.1 Reentrancy Protection (Not Implemented)
- [ ] Reentrancy guards not added as all external calls follow checks-effects-interactions pattern
- [ ] Could be added as extra safety measure using OpenZeppelin's ReentrancyGuard

#### 10.2 Creator Address Handling ✅
- [x] Creator address is passed in start() function and stored in AuctionData
- [x] Creator receives 90% of auction proceeds on settlement

#### 10.3 USDC Blacklist Handling (Not Implemented)
- [ ] Current implementation uses simple transfer() which would revert on blacklist
- [ ] Could be enhanced with try/catch and manual claim mechanism

## Phase 11: Integration & Deployment

### 11.1 Integration Tests
- [ ] Write end-to-end auction flow test
- [ ] Test all edge cases with full contract suite
- [ ] Verify gas costs are reasonable

### 11.2 Deployment Scripts
- [ ] Create deployment script with proper ordering
- [ ] Add verification scripts
- [ ] Test on testnet

### 11.3 Documentation
- [ ] Update README with deployment addresses
- [ ] Add user interaction guide
- [ ] Document admin operations

## Progress Summary

### Completed ✅
1. **CollectibleCast**: Core ERC-1155 token with modular architecture
2. **Metadata**: URI management for on/off-chain metadata
3. **Minter**: Authorization layer with allowlist
4. **TransferValidator**: Transfer control with one-way switch and operator allowlist
5. **Royalties**: Simple 5% royalty to creator
6. **Auction Contract**: Complete implementation with:
   - EIP-712 signature validation for backend authorization
   - Separate start(), bid(), and settle() functions
   - USDC escrow and automatic refund mechanism
   - Anti-snipe auction extensions
   - Settlement with 90/10 payment split
   - Random bytes32 nonces to prevent replay attacks
   - Bidder FID tracking for Farcaster integration
   - 56 comprehensive tests with full coverage

### Next Steps 🚀
1. **USDC Permit Support**: Implement bidWithPermit() and settleWithPermit() functions
   - Allow users to approve and bid in a single transaction
   - Reduces gas costs and improves UX
   - Use IERC20Permit interface for USDC
2. **Integration Testing**: End-to-end flow testing with all contracts
3. **Deployment Scripts**: Create deployment and verification scripts
4. **Documentation**: Update README with deployment info and usage guide
5. **Optional Enhancements**:
   - Manual refund claims for USDC blacklist scenarios
   - Reentrancy guards for extra safety
   - Advanced auction features (reserve prices, buy now, etc.)

## Architecture Notes

### Module Pattern
All contracts follow a consistent module pattern:
- Core contract (CollectibleCast) delegates to modules
- Modules can be updated by owner
- Clean separation of concerns

### Auction Design Decisions
- **Three-function approach**: start(), bid(), settle() for clarity and simplicity
- **Backend authorization**: Multiple authorizers supported via allowlist
- **Random nonces**: Backend provides bytes32 nonces to prevent replay attacks
- **State derivation**: Auction state calculated from data rather than stored explicitly
- **Cast metadata**: Stored on auction start for provenance

### Security Considerations
- One-way switches prevent accidental disabling
- Allowlists provide granular control
- Custom errors for gas efficiency
- Comprehensive test coverage (100% on all production contracts)
- EIP-712 signatures prevent cross-chain replay attacks
- Automatic refunds reduce user friction

### Gas Optimizations
- Struct packing in TokenData and AuctionData
- Immutable variables where possible
- Efficient storage layout
- Minimal external calls
- Single SSTORE for auction creation