# Collectible Casts - Detailed Task Breakdown

## Phase 1: Interfaces and Base Structure

### 1.1 Create Interface Files
- [ ] Create `src/interfaces/ICollectibleCast.sol`
  - [ ] Define ERC-1155 interface extensions
  - [ ] Add module getter functions
  - [ ] Add cast hash to FID mapping function
  - [ ] Add royalty info function
- [ ] Create `src/interfaces/IMetadata.sol`
  - [ ] Define contractURI() function
  - [ ] Define uri(uint256) function  
  - [ ] Add base URI setter function
- [ ] Create `src/interfaces/IMinter.sol`
  - [ ] Define mint authorization check function
  - [ ] Define mint function signature
  - [ ] Add minter management functions
- [ ] Create `src/interfaces/ITransferValidator.sol`
  - [ ] Define transfer validation function
  - [ ] Add transfer enable/disable functions
  - [ ] Add operator management functions
- [ ] Create `src/interfaces/IAuction.sol`
  - [ ] Define bid function with signature
  - [ ] Define settle function
  - [ ] Define batch settle function
  - [ ] Define refund claim function
  - [ ] Add auction state getter functions

### 1.2 Set Up Test Infrastructure
- [ ] Create `test/shared/TestConstants.sol`
  - [ ] Define common test addresses
  - [ ] Define USDC address for Base
  - [ ] Define test FIDs and cast hashes
- [ ] Update `test/TestSuiteSetup.sol`
  - [ ] Add auction-specific test helpers
  - [ ] Add signature generation helpers
  - [ ] Add USDC deal helper functions

## Phase 2: CollectibleCast Token Contract

### 2.1 Write Token Tests
- [ ] Create `test/CollectibleCast/CollectibleCast.t.sol`
- [ ] Test: Constructor sets owner correctly
- [ ] Test: Only minter can mint tokens
- [ ] Test: Cannot mint more than 1 token per ID
- [ ] Test: Cast hash to FID mapping works correctly
- [ ] Test: Module updates only by owner
- [ ] Test: Module updates emit events
- [ ] Test: Royalty info returns correct values
- [ ] Test: Transfers check TransferValidator

### 2.2 Implement Token Contract
- [ ] Create `src/CollectibleCast.sol`
- [ ] Inherit from ERC-1155 and implement interface
- [ ] Add module storage variables
- [ ] Implement mint with max supply check
- [ ] Implement cast hash to FID mapping
- [ ] Override transfer functions for validation
- [ ] Implement EIP-2981 royalty info
- [ ] Add module management functions

### 2.3 Write Token Fuzz Tests
- [ ] Fuzz: Various token IDs for minting
- [ ] Fuzz: Royalty calculations with different sale prices
- [ ] Fuzz: Module address updates

## Phase 3: Metadata Contract

### 3.1 Write Metadata Tests
- [ ] Create `test/Metadata/Metadata.t.sol`
- [ ] Test: Constructor sets owner and base URI
- [ ] Test: contractURI returns correct format
- [ ] Test: uri returns correct format for token IDs
- [ ] Test: Only owner can update base URI
- [ ] Test: Base URI updates emit events

### 3.2 Implement Metadata Contract
- [ ] Create `src/Metadata.sol`
- [ ] Implement IMetadata interface
- [ ] Add base URI storage
- [ ] Implement URI construction logic
- [ ] Add owner-only URI updates

### 3.3 Write Metadata Fuzz Tests
- [ ] Fuzz: Various token IDs for URI generation
- [ ] Fuzz: Various base URI formats

## Phase 4: Minter Contract

### 4.1 Write Minter Tests
- [ ] Create `test/Minter/Minter.t.sol`
- [ ] Test: Constructor sets owner correctly
- [ ] Test: Owner can add/remove minters
- [ ] Test: Non-owner cannot modify minters
- [ ] Test: Authorized minters can mint
- [ ] Test: Unauthorized addresses cannot mint
- [ ] Test: Adding minter emits event
- [ ] Test: Removing minter emits event

### 4.2 Implement Minter Contract
- [ ] Create `src/Minter.sol`
- [ ] Implement IMinter interface
- [ ] Add minter allowlist mapping
- [ ] Implement authorization checks
- [ ] Add minter management functions
- [ ] Implement mint pass-through to token

### 4.3 Write Minter Fuzz Tests
- [ ] Fuzz: Random addresses for minter checks
- [ ] Fuzz: Multiple minter additions/removals

## Phase 5: TransferValidator Contract

### 5.1 Write TransferValidator Tests
- [ ] Create `test/TransferValidator/TransferValidator.t.sol`
- [ ] Test: Transfers blocked by default
- [ ] Test: Owner can enable transfers (one-way)
- [ ] Test: Cannot disable transfers once enabled
- [ ] Test: Operator allowlist works when enabled
- [ ] Test: Allowlist can be disabled to allow all
- [ ] Test: Operator management emits events

### 5.2 Implement TransferValidator Contract
- [ ] Create `src/TransferValidator.sol`
- [ ] Implement ITransferValidator interface
- [ ] Add transfer enabled flag (one-way)
- [ ] Add operator allowlist mapping
- [ ] Add allowlist enabled flag
- [ ] Implement validation logic

### 5.3 Write TransferValidator Fuzz Tests
- [ ] Fuzz: Various operator addresses
- [ ] Fuzz: Transfer validation with different states

## Phase 6: Auction Core Bidding

### 6.1 Write Auction Signature Tests
- [ ] Create `test/Auction/AuctionSignature.t.sol`
- [ ] Test: Valid EIP-712 signature accepted
- [ ] Test: Invalid signature rejected
- [ ] Test: Expired signature rejected
- [ ] Test: Signature with wrong parameters rejected
- [ ] Test: Signature replay protection

### 6.2 Write Auction Bidding Tests
- [ ] Create `test/Auction/AuctionBidding.t.sol`
- [ ] Test: Opening bid >= 1 USDC required
- [ ] Test: Overbid >= current + 10% required
- [ ] Test: Overbid >= current + 1 USDC required
- [ ] Test: USDC pulled from bidder
- [ ] Test: Previous bidder auto-refunded
- [ ] Test: Auction created on first bid
- [ ] Test: Anti-snipe extension works
- [ ] Test: Events emitted correctly

### 6.3 Implement Auction Core
- [ ] Create `src/Auction.sol`
- [ ] Implement EIP-712 domain separator
- [ ] Add auction parameter struct
- [ ] Add auction state struct
- [ ] Implement signature validation
- [ ] Implement bid validation logic
- [ ] Add USDC permit support
- [ ] Implement auto-refund logic

### 6.4 Write Auction Bidding Fuzz Tests
- [ ] Fuzz: Various bid amounts
- [ ] Fuzz: Multiple bidders
- [ ] Fuzz: Timing scenarios

## Phase 7: Auction Settlement & Refunds

### 7.1 Write Settlement Tests
- [ ] Create `test/Auction/AuctionSettlement.t.sol`
- [ ] Test: Cannot settle active auction
- [ ] Test: Anyone can settle ended auction
- [ ] Test: 90% paid to creator
- [ ] Test: 10% paid to protocol
- [ ] Test: Token minted to winner
- [ ] Test: Settlement events emitted

### 7.2 Write Refund Tests
- [ ] Create `test/Auction/AuctionRefunds.t.sol`
- [ ] Test: Failed auto-refund creates claimable balance
- [ ] Test: Users can claim refunds
- [ ] Test: Cannot claim zero refund
- [ ] Test: Refund events emitted

### 7.3 Write Batch Tests
- [ ] Test: Batch settle multiple auctions
- [ ] Test: Batch continues on individual failures
- [ ] Test: Batch emits individual events

### 7.4 Implement Settlement & Refunds
- [ ] Add settlement logic to Auction.sol
- [ ] Add refund mapping and claim function
- [ ] Implement batch settlement
- [ ] Add failure handling for payments
- [ ] Connect to Minter for token creation

### 7.5 Write Settlement Fuzz Tests
- [ ] Fuzz: Various winning bid amounts
- [ ] Fuzz: Batch settlement sizes

## Phase 8: Integration Testing

### 8.1 Write Full Flow Tests
- [ ] Create `test/integration/FullAuctionFlow.t.sol`
- [ ] Test: Complete auction lifecycle
- [ ] Test: Multiple concurrent auctions
- [ ] Test: Module interaction correctness

### 8.2 Write Edge Case Tests
- [ ] Create `test/integration/EdgeCases.t.sol`
- [ ] Test: USDC blacklisted winner
- [ ] Test: USDC blacklisted creator
- [ ] Test: Reverting creator contract
- [ ] Test: Gas limit scenarios

### 8.3 Write Gas Tests
- [ ] Create `test/gas/GasUsage.t.sol`
- [ ] Measure: Auction creation gas
- [ ] Measure: Bidding gas
- [ ] Measure: Settlement gas
- [ ] Create gas snapshot

## Phase 9: Deployment & Verification

### 9.1 Write Deployment Script
- [ ] Create `script/Deploy.s.sol`
- [ ] Deploy all contracts in order
- [ ] Connect modules to token
- [ ] Set initial parameters
- [ ] Add auction as minter

### 9.2 Write Verification Script
- [ ] Create `script/Verify.s.sol`
- [ ] Verify all module connections
- [ ] Verify ownership setup
- [ ] Verify initial parameters

### 9.3 Documentation
- [ ] Update README with deployment info
- [ ] Document contract addresses
- [ ] Create interaction examples