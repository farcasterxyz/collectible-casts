# Collectible Casts - TDD Task Breakdown

Each task follows the TDD cycle: RED → GREEN → REFACTOR → COMMIT

## Guiding Principles
- **KISS** (Keep It Simple, Stupid) - Choose the simplest solution
- **YAGNI** (You Aren't Gonna Need It) - Don't add functionality until needed
- **100% Test Coverage** - Every line of production code must be tested
- **Minimal Interfaces** - Start with empty interfaces, add functions only when tests require them

## Phase 1: Contract Interfaces and Test Infrastructure

### 1.1 Create Base Test Infrastructure
- [x] RED: Write failing test for TestConstants existence
- [x] GREEN: Create `test/shared/TestConstants.sol` with basic constants
- [x] REFACTOR: ~~Add all needed test constants~~ Removed unused helpers, use makeAddr pattern
- [x] COMMIT: "test: add TestConstants for shared test values"
- [x] COMMIT: "refactor: simplify test infrastructure with forge-std patterns"

### 1.2 ICollectibleCast Interface
- [x] RED: Write failing test that tries to import ICollectibleCast
- [x] GREEN: Create minimal `src/interfaces/ICollectibleCast.sol`
- [x] ~~RED: Write test expecting ERC-1155 functions~~ Following YAGNI - will add when needed
- [x] ~~GREEN: Add ERC-1155 function signatures~~ Following YAGNI - will add when needed
- [x] COMMIT: "feat: add ICollectibleCast interface"

### 1.3 Other Interfaces (Following Same Pattern)
- [x] IMetadata: RED → GREEN → ~~REFACTOR~~ → (ready to commit)
- [x] IMinter: RED → GREEN → ~~REFACTOR~~ → (ready to commit)
- [x] ITransferValidator: RED → GREEN → ~~REFACTOR~~ → (ready to commit)
- [x] IAuction: RED → GREEN → ~~REFACTOR~~ → (ready to commit)

## Phase 2: CollectibleCast Token - Core ERC-1155

### 2.1 Basic ERC-1155 Implementation
- [x] RED: Write test `test_Constructor_SetsOwner()`
- [x] GREEN: Create CollectibleCast contract with constructor
- [x] REFACTOR: Use OpenZeppelin Ownable2Step for ownership
- [x] COMMIT: "feat: add CollectibleCast constructor with Ownable2Step"

- [x] RED: Write test `test_SupportsERC1155Interface()`
- [x] GREEN: Inherit from ERC-1155 
- [x] COMMIT: "feat: implement ERC-1155 in CollectibleCast" (ready to commit)

### 2.2 Minting with Max Supply
- [x] RED: Write test `test_Mint_RevertsWhenNotMinter()`
- [x] GREEN: Add minter check in mint function
- [x] COMMIT: "feat: add minter authorization to mint" (ready to commit)

- [ ] RED: Write test `test_Mint_SucceedsFirstTime()`
- [ ] GREEN: Implement basic mint function
- [ ] COMMIT: "feat: implement basic minting"

- [ ] RED: Write test `test_Mint_RevertsOnSecondMint()`
- [ ] GREEN: Add max supply = 1 check
- [ ] COMMIT: "feat: enforce max supply of 1 per token"

- [ ] RED: Write fuzz test `testFuzz_Mint_OnlyOncePerTokenId(uint256 tokenId)`
- [ ] GREEN: Ensure implementation handles all token IDs
- [ ] REFACTOR: Optimize storage if needed
- [ ] COMMIT: "test: add fuzz test for mint max supply"

### 2.3 Cast Hash to FID Mapping
- [ ] RED: Write test `test_Mint_StoresCastHashToFid()`
- [ ] GREEN: Add storage mapping and update in mint
- [ ] COMMIT: "feat: store cast hash to FID mapping"

- [ ] RED: Write test `test_GetFidFromCastHash_ReturnsCorrectFid()`
- [ ] GREEN: Add getter function for FID lookup
- [ ] COMMIT: "feat: add FID lookup by cast hash"

- [ ] RED: Write test `test_Mint_EmitsEventWithFid()`
- [ ] GREEN: Add event emission with FID
- [ ] COMMIT: "feat: emit FID in mint event"

### 2.4 Module Management
- [ ] RED: Write test `test_SetMetadata_RevertsWhenNotOwner()`
- [ ] GREEN: Add onlyOwner modifier to setMetadata
- [ ] COMMIT: "feat: add owner-only metadata module setter"

- [ ] RED: Write test `test_SetMetadata_UpdatesModule()`
- [ ] GREEN: Implement metadata module storage and setter
- [ ] COMMIT: "feat: implement metadata module management"

- [ ] RED: Write test `test_SetMetadata_EmitsEvent()`
- [ ] GREEN: Add event emission
- [ ] COMMIT: "feat: emit event on metadata module update"

- [ ] Repeat above pattern for Minter module: RED → GREEN → COMMIT
- [ ] Repeat above pattern for TransferValidator module: RED → GREEN → COMMIT

### 2.5 Transfer Integration
- [ ] RED: Write test `test_Transfer_ChecksTransferValidator()`
- [ ] GREEN: Override _beforeTokenTransfer to check validator
- [ ] COMMIT: "feat: integrate transfer validator checks"

- [ ] RED: Write test `test_Transfer_RevertsWhenValidatorDenies()`
- [ ] GREEN: Ensure revert on validation failure
- [ ] REFACTOR: Add custom error for clarity
- [ ] COMMIT: "feat: revert transfers when validator denies"

### 2.6 EIP-2981 Royalties
- [ ] RED: Write test `test_RoyaltyInfo_ReturnsCorrectAmounts()`
- [ ] GREEN: Implement royaltyInfo function
- [ ] COMMIT: "feat: implement EIP-2981 royalty info"

- [ ] RED: Write fuzz test `testFuzz_RoyaltyInfo_CalculatesCorrectSplit(uint256 salePrice)`
- [ ] GREEN: Ensure calculation handles all prices correctly
- [ ] COMMIT: "test: fuzz test royalty calculations"

## Phase 3: Metadata Contract

### 3.1 Basic Implementation
- [ ] RED: Write test `test_Constructor_SetsOwnerAndBaseUri()`
- [ ] GREEN: Create Metadata contract with constructor
- [ ] COMMIT: "feat: add Metadata contract constructor"

### 3.2 URI Functions
- [ ] RED: Write test `test_ContractURI_ReturnsCorrectFormat()`
- [ ] GREEN: Implement contractURI function
- [ ] COMMIT: "feat: implement contractURI"

- [ ] RED: Write test `test_Uri_ReturnsCorrectTokenUri()`
- [ ] GREEN: Implement uri function for tokens
- [ ] COMMIT: "feat: implement token URI function"

- [ ] RED: Write fuzz test `testFuzz_Uri_HandlesAllTokenIds(uint256 tokenId)`
- [ ] GREEN: Ensure URI generation works for all IDs
- [ ] COMMIT: "test: fuzz test URI generation"

### 3.3 Base URI Management
- [ ] RED: Write test `test_SetBaseURI_RevertsWhenNotOwner()`
- [ ] GREEN: Add onlyOwner check
- [ ] COMMIT: "feat: restrict base URI updates to owner"

- [ ] RED: Write test `test_SetBaseURI_UpdatesUris()`
- [ ] GREEN: Implement base URI update
- [ ] COMMIT: "feat: implement base URI updates"

- [ ] RED: Write test `test_SetBaseURI_EmitsEvent()`
- [ ] GREEN: Add event emission
- [ ] REFACTOR: Optimize URI construction
- [ ] COMMIT: "feat: emit event on base URI update"

## Phase 4: Minter Contract

### 4.1 Basic Authorization
- [ ] RED: Write test `test_Constructor_SetsOwner()`
- [ ] GREEN: Create Minter with owner
- [ ] COMMIT: "feat: add Minter contract with owner"

- [ ] RED: Write test `test_IsMinter_ReturnsFalseByDefault()`
- [ ] GREEN: Implement isMinter function
- [ ] COMMIT: "feat: implement minter authorization check"

### 4.2 Minter Management
- [ ] RED: Write test `test_AddMinter_RevertsWhenNotOwner()`
- [ ] GREEN: Add onlyOwner modifier
- [ ] COMMIT: "feat: restrict minter management to owner"

- [ ] RED: Write test `test_AddMinter_AuthorizesMinter()`
- [ ] GREEN: Implement addMinter function
- [ ] COMMIT: "feat: implement add minter"

- [ ] RED: Write test `test_AddMinter_EmitsEvent()`
- [ ] GREEN: Add MinterAdded event
- [ ] COMMIT: "feat: emit event when minter added"

- [ ] RED: Write test `test_RemoveMinter_DeauthorizesMinter()`
- [ ] GREEN: Implement removeMinter
- [ ] COMMIT: "feat: implement remove minter"

- [ ] RED: Write test `test_RemoveMinter_EmitsEvent()`
- [ ] GREEN: Add MinterRemoved event
- [ ] COMMIT: "feat: emit event when minter removed"

### 4.3 Mint Function
- [ ] RED: Write test `test_Mint_RevertsWhenNotAuthorized()`
- [ ] GREEN: Add authorization check in mint
- [ ] COMMIT: "feat: check authorization in mint"

- [ ] RED: Write test `test_Mint_CallsTokenContract()`
- [ ] GREEN: Implement mint pass-through
- [ ] COMMIT: "feat: implement mint pass-through"

- [ ] RED: Write test `test_Mint_ReturnsTokenId()`
- [ ] GREEN: Return token ID from mint
- [ ] REFACTOR: Add custom errors
- [ ] COMMIT: "feat: return token ID from mint"

## Phase 5: TransferValidator Contract

### 5.1 Transfer Toggle
- [ ] RED: Write test `test_TransfersDisabledByDefault()`
- [ ] GREEN: Create contract with transfers disabled
- [ ] COMMIT: "feat: create TransferValidator with transfers disabled"

- [ ] RED: Write test `test_EnableTransfers_RevertsWhenNotOwner()`
- [ ] GREEN: Add onlyOwner to enableTransfers
- [ ] COMMIT: "feat: restrict transfer toggle to owner"

- [ ] RED: Write test `test_EnableTransfers_EnablesTransfers()`
- [ ] GREEN: Implement one-way enable
- [ ] COMMIT: "feat: implement transfer enable"

- [ ] RED: Write test `test_EnableTransfers_CannotBeDisabled()`
- [ ] GREEN: Ensure one-way switch
- [ ] COMMIT: "feat: make transfer enable one-way"

- [ ] RED: Write test `test_EnableTransfers_EmitsEvent()`
- [ ] GREEN: Add event emission
- [ ] COMMIT: "feat: emit event on transfer enable"

### 5.2 Validation Logic
- [ ] RED: Write test `test_ValidateTransfer_DeniesWhenDisabled()`
- [ ] GREEN: Implement validation function
- [ ] COMMIT: "feat: deny transfers when disabled"

- [ ] RED: Write test `test_ValidateTransfer_AllowsWhenEnabled()`
- [ ] GREEN: Allow transfers when enabled
- [ ] COMMIT: "feat: allow transfers when enabled"

### 5.3 Operator Allowlist
- [ ] RED: Write test `test_AddOperator_RevertsWhenNotOwner()`
- [ ] GREEN: Add owner check
- [ ] COMMIT: "feat: restrict operator management to owner"

- [ ] RED: Write test `test_AddOperator_AllowsOperator()`
- [ ] GREEN: Implement operator allowlist
- [ ] COMMIT: "feat: implement operator allowlist"

- [ ] RED: Write test `test_ValidateTransfer_ChecksOperatorAllowlist()`
- [ ] GREEN: Add allowlist check to validation
- [ ] COMMIT: "feat: check operator allowlist in validation"

- [ ] RED: Write test `test_DisableAllowlist_AllowsAnyOperator()`
- [ ] GREEN: Implement allowlist disable
- [ ] COMMIT: "feat: add option to disable allowlist"

- [ ] RED: Write test `test_OperatorEvents_EmitCorrectly()`
- [ ] GREEN: Add all operator events
- [ ] REFACTOR: Optimize storage layout
- [ ] COMMIT: "feat: emit events for operator changes"

## Phase 6: Auction Contract - Signatures & Parameters

### 6.1 EIP-712 Setup
- [ ] RED: Write test `test_DomainSeparator_ComputesCorrectly()`
- [ ] GREEN: Implement EIP-712 domain
- [ ] COMMIT: "feat: add EIP-712 domain separator"

- [ ] RED: Write test `test_AuctionParamsHash_ComputesCorrectly()`
- [ ] GREEN: Add auction params struct and hash
- [ ] COMMIT: "feat: add auction parameter hashing"

### 6.2 Signature Validation
- [ ] RED: Write test `test_Bid_RevertsWithInvalidSignature()`
- [ ] GREEN: Add signature validation
- [ ] COMMIT: "feat: validate backend signatures"

- [ ] RED: Write test `test_Bid_RevertsWithExpiredSignature()`
- [ ] GREEN: Add expiration check
- [ ] COMMIT: "feat: check signature expiration"

- [ ] RED: Write test `test_Bid_RevertsOnSignatureReuse()`
- [ ] GREEN: Add nonce/replay protection
- [ ] COMMIT: "feat: prevent signature replay"

## Phase 7: Auction Contract - Bidding Logic

### 7.1 Opening Bid
- [ ] RED: Write test `test_Bid_RevertsWhenBelowMinimum()`
- [ ] GREEN: Add minimum bid check
- [ ] COMMIT: "feat: enforce minimum opening bid"

- [ ] RED: Write test `test_Bid_CreatesAuction()`
- [ ] GREEN: Create auction on first bid
- [ ] COMMIT: "feat: create auction on opening bid"

- [ ] RED: Write test `test_Bid_SetsCorrectEndTime()`
- [ ] GREEN: Set 24-hour duration
- [ ] COMMIT: "feat: set auction duration"

- [ ] RED: Write test `test_Bid_EmitsAuctionCreatedEvent()`
- [ ] GREEN: Add event emission
- [ ] COMMIT: "feat: emit auction created event"

### 7.2 USDC Integration
- [ ] RED: Write test `test_Bid_TransfersUSDC()`
- [ ] GREEN: Add USDC transfer
- [ ] COMMIT: "feat: transfer USDC on bid"

- [ ] RED: Write test `test_Bid_SupportsPermit()`
- [ ] GREEN: Add permit support
- [ ] COMMIT: "feat: add USDC permit support"

### 7.3 Overbidding
- [ ] RED: Write test `test_Overbid_RevertsWhenInsufficientIncrease()`
- [ ] GREEN: Add overbid validation
- [ ] COMMIT: "feat: validate overbid amounts"

- [ ] RED: Write test `test_Overbid_RefundsPreviousBidder()`
- [ ] GREEN: Add auto-refund
- [ ] COMMIT: "feat: auto-refund previous bidder"

- [ ] RED: Write test `test_Overbid_HandlesRefundFailure()`
- [ ] GREEN: Add refund failure handling
- [ ] COMMIT: "feat: handle failed auto-refunds"

### 7.4 Anti-Snipe Extension
- [ ] RED: Write test `test_Bid_ExtendsAuctionNearEnd()`
- [ ] GREEN: Implement extension logic
- [ ] COMMIT: "feat: add anti-snipe extension"

- [ ] RED: Write fuzz test `testFuzz_AntiSnipe_ExtendsCorrectly(uint256 timeLeft)`
- [ ] GREEN: Ensure extension works correctly
- [ ] REFACTOR: Optimize time calculations
- [ ] COMMIT: "test: fuzz test anti-snipe extension"

## Phase 8: Auction Contract - Settlement

### 8.1 Settlement Validation
- [ ] RED: Write test `test_Settle_RevertsWhenAuctionActive()`
- [ ] GREEN: Add active auction check
- [ ] COMMIT: "feat: prevent settlement of active auctions"

- [ ] RED: Write test `test_Settle_AllowsAnyoneToSettle()`
- [ ] GREEN: Make settlement permissionless
- [ ] COMMIT: "feat: allow permissionless settlement"

### 8.2 Payment Distribution
- [ ] RED: Write test `test_Settle_PaysCreator90Percent()`
- [ ] GREEN: Implement creator payment
- [ ] COMMIT: "feat: pay creator 90% on settlement"

- [ ] RED: Write test `test_Settle_PaysProtocol10Percent()`
- [ ] GREEN: Implement protocol payment
- [ ] COMMIT: "feat: pay protocol 10% on settlement"

- [ ] RED: Write test `test_Settle_HandlesPaymentFailure()`
- [ ] GREEN: Add payment failure handling
- [ ] COMMIT: "feat: handle settlement payment failures"

### 8.3 Token Minting
- [ ] RED: Write test `test_Settle_MintsTokenToWinner()`
- [ ] GREEN: Call minter to create token
- [ ] COMMIT: "feat: mint token on settlement"

- [ ] RED: Write test `test_Settle_EmitsSettledEvent()`
- [ ] GREEN: Add settlement event
- [ ] COMMIT: "feat: emit settlement event"

### 8.4 Batch Operations
- [ ] RED: Write test `test_BatchSettle_SettlesMultiple()`
- [ ] GREEN: Implement batch settlement
- [ ] COMMIT: "feat: add batch settlement"

- [ ] RED: Write test `test_BatchSettle_ContinuesOnFailure()`
- [ ] GREEN: Add failure handling
- [ ] REFACTOR: Optimize gas usage
- [ ] COMMIT: "feat: handle individual failures in batch"

## Phase 9: Integration & Deployment

### 9.1 Integration Tests
- [ ] RED: Write test for complete auction flow
- [ ] GREEN: Ensure all contracts work together
- [ ] COMMIT: "test: add full auction flow integration test"

- [ ] RED: Write test for edge cases (blacklist, etc.)
- [ ] GREEN: Handle all edge cases properly
- [ ] COMMIT: "test: add edge case integration tests"

### 9.2 Deployment
- [ ] RED: Write test that deployment script exists
- [ ] GREEN: Create deployment script
- [ ] COMMIT: "feat: add deployment script"

- [ ] RED: Write test for deployment verification
- [ ] GREEN: Add verification script
- [ ] REFACTOR: Optimize deployment order
- [ ] COMMIT: "feat: add deployment verification"

### 9.3 Documentation
- [ ] Update README with deployment info
- [ ] Add interaction examples
- [ ] COMMIT: "docs: add deployment and usage documentation"

## Notes

- Each task follows: RED (failing test) → GREEN (minimal implementation) → REFACTOR (optional improvement) → COMMIT
- Fuzz tests are added after basic functionality is working
- Events are tested separately to keep tests focused
- Custom errors are added during refactor phase
- Gas optimizations happen during refactor phase only