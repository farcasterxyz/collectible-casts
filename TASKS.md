# Collectible Casts - TDD Task Breakdown

Each task follows the TDD cycle: RED → GREEN → REFACTOR → COMMIT

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

## Phase 6-8: Auction Contract (TODO)

The Auction contract is the most complex component. Let's break it down into manageable pieces:

### Phase 6: Auction Foundation & Configuration

#### 6.1 Basic Structure
- [ ] RED: Write test `test_Constructor_SetsConfiguration()`
- [ ] GREEN: Create Auction with immutable config (token, minter, usdc, treasury)
- [ ] COMMIT: "feat: add Auction constructor with configuration"

#### 6.2 Auction Parameters
- [ ] RED: Write test `test_AuctionParams_StoresCorrectly()`
- [ ] GREEN: Define AuctionParams struct (minBid, minBidIncrement, duration, extension, extensionThreshold)
- [ ] COMMIT: "feat: add auction parameter storage"

#### 6.3 Backend Signer Setup
- [ ] RED: Write test `test_SetBackendSigner_OnlyOwner()`
- [ ] GREEN: Add backend signer management
- [ ] COMMIT: "feat: add backend signer management"

### Phase 7: Signature Validation

#### 7.1 EIP-712 Domain
- [ ] RED: Write test `test_DomainSeparator_ComputesCorrectly()`
- [ ] GREEN: Implement EIP-712 domain separator
- [ ] COMMIT: "feat: implement EIP-712 domain"

#### 7.2 Bid Authorization Structure
- [ ] RED: Write test `test_BidAuthorization_HashesCorrectly()`
- [ ] GREEN: Define BidAuthorization struct and hashing
- [ ] COMMIT: "feat: add bid authorization structure"

#### 7.3 Signature Verification
- [ ] RED: Write test `test_VerifySignature_ValidatesCorrectly()`
- [ ] GREEN: Implement ECDSA signature verification
- [ ] COMMIT: "feat: implement signature verification"

- [ ] RED: Write test `test_VerifySignature_RejectsExpired()`
- [ ] GREEN: Add expiration check
- [ ] COMMIT: "feat: add signature expiration"

- [ ] RED: Write test `test_VerifySignature_PreventsReplay()`
- [ ] GREEN: Add nonce tracking
- [ ] COMMIT: "feat: prevent signature replay"

### Phase 8: Bidding Logic

#### 8.1 Auction State Management
- [ ] RED: Write test `test_AuctionState_TracksCorrectly()`
- [ ] GREEN: Define Auction struct (tokenId, startTime, endTime, currentBidder, currentBid, creator)
- [ ] COMMIT: "feat: add auction state management"

#### 8.2 Opening Bid
- [ ] RED: Write test `test_OpeningBid_RequiresMinimum()`
- [ ] GREEN: Validate opening bid >= $1 USDC
- [ ] COMMIT: "feat: validate opening bid amount"

- [ ] RED: Write test `test_OpeningBid_CreatesAuction()`
- [ ] GREEN: Create auction with 24-hour duration
- [ ] COMMIT: "feat: create auction on opening bid"

- [ ] RED: Write test `test_OpeningBid_TransfersUSDC()`
- [ ] GREEN: Pull USDC from bidder
- [ ] COMMIT: "feat: transfer USDC on bid"

- [ ] RED: Write test `test_OpeningBid_EmitsEvent()`
- [ ] GREEN: Emit AuctionCreated and BidPlaced events
- [ ] COMMIT: "feat: emit events on opening bid"

#### 8.3 USDC Permit Support
- [ ] RED: Write test `test_BidWithPermit_TransfersCorrectly()`
- [ ] GREEN: Implement permit + bid in one transaction
- [ ] COMMIT: "feat: add USDC permit support"

#### 8.4 Overbidding
- [ ] RED: Write test `test_Overbid_RequiresSufficientIncrease()`
- [ ] GREEN: Validate bid >= currentBid + max($1, 10%)
- [ ] COMMIT: "feat: validate overbid amounts"

- [ ] RED: Write test `test_Overbid_RefundsPreviousBidder()`
- [ ] GREEN: Implement automatic refund
- [ ] COMMIT: "feat: auto-refund previous bidder"

- [ ] RED: Write test `test_Overbid_HandlesRefundFailure()`
- [ ] GREEN: Credit failed refunds for manual claim
- [ ] COMMIT: "feat: handle failed auto-refunds"

#### 8.5 Anti-Snipe Extension
- [ ] RED: Write test `test_Bid_ExtendsNearEnd()`
- [ ] GREEN: If bid within 15 min of end, extend by 15 min
- [ ] COMMIT: "feat: implement anti-snipe extension"

- [ ] RED: Write fuzz test `testFuzz_AntiSnipe_CalculatesCorrectly(uint256 timeUntilEnd)`
- [ ] GREEN: Ensure extension logic is correct
- [ ] COMMIT: "test: fuzz test anti-snipe logic"

### Phase 9: Settlement & Refunds

#### 9.1 Settlement Validation
- [ ] RED: Write test `test_Settle_RevertsIfActive()`
- [ ] GREEN: Check auction has ended
- [ ] COMMIT: "feat: validate auction ended before settlement"

- [ ] RED: Write test `test_Settle_RevertsIfAlreadySettled()`
- [ ] GREEN: Prevent double settlement
- [ ] COMMIT: "feat: prevent double settlement"

#### 9.2 Payment Distribution
- [ ] RED: Write test `test_Settle_PaysCreator90Percent()`
- [ ] GREEN: Transfer 90% to creator
- [ ] COMMIT: "feat: pay creator on settlement"

- [ ] RED: Write test `test_Settle_PaysTreasury10Percent()`
- [ ] GREEN: Transfer 10% to treasury
- [ ] COMMIT: "feat: pay treasury on settlement"

#### 9.3 Token Minting
- [ ] RED: Write test `test_Settle_MintsToken()`
- [ ] GREEN: Call minter to mint token to winner
- [ ] COMMIT: "feat: mint token on settlement"

- [ ] RED: Write test `test_Settle_EmitsEvent()`
- [ ] GREEN: Emit AuctionSettled event
- [ ] COMMIT: "feat: emit settlement event"

#### 9.4 Manual Refunds
- [ ] RED: Write test `test_ClaimRefund_TransfersCredit()`
- [ ] GREEN: Implement claimRefund for failed auto-refunds
- [ ] COMMIT: "feat: implement manual refund claims"

- [ ] RED: Write test `test_ClaimRefund_EmitsEvent()`
- [ ] GREEN: Emit BidRefunded event
- [ ] COMMIT: "feat: emit refund event"

### Phase 10: Edge Cases & Security

#### 10.1 Reentrancy Protection
- [ ] RED: Write test `test_Bid_ReentrancyProtected()`
- [ ] GREEN: Add reentrancy guards
- [ ] COMMIT: "feat: add reentrancy protection"

#### 10.2 Creator Address Handling
- [ ] RED: Write test `test_Auction_SnapshotsCreatorOnFirstBid()`
- [ ] GREEN: Store creator address from first bid
- [ ] COMMIT: "feat: snapshot creator on auction start"

#### 10.3 USDC Blacklist Handling
- [ ] RED: Write test `test_Settlement_HandlesBlacklistedCreator()`
- [ ] GREEN: Handle USDC transfer failures gracefully
- [ ] COMMIT: "feat: handle USDC blacklist scenarios"

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

### Next Steps 🚀
1. **Auction Contract**: The main user-facing contract for bidding and settlement
   - Signature validation for backend authorization
   - USDC escrow and refund mechanism
   - Anti-snipe auction extensions
   - Settlement with payment splits

## Architecture Notes

### Module Pattern
All contracts follow a consistent module pattern:
- Core contract (CollectibleCast) delegates to modules
- Modules can be updated by owner
- Clean separation of concerns

### Security Considerations
- One-way switches prevent accidental disabling
- Allowlists provide granular control
- Custom errors for gas efficiency
- Comprehensive test coverage

### Gas Optimizations
- Struct packing in TokenData
- Immutable variables where possible
- Efficient storage layout
- Minimal external calls