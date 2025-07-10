# Collectible Casts

## 1 Overview

Collectible Casts introduce a lightweight, on‑chain way for Farcaster users to financially support creators. Every cast can be _collected_; if more than one user attempts to collect the same cast within the bidding window, an ascending auction determines the final owner and price. The winning bidder receives an ERC‑1155 token that represents the collectible, minted directly to their wallet. Ninety percent of the winning bid is paid to the creator; the remaining ten percent accrues to the protocol treasury for growth incentives.

---

## 2 Goals

- **Creator monetisation.** Let any creator earn immediately from their content without waiting for weekly reward cycles.
- **Showcase support.** Give users a collectible that is more meaningful than a tip and shareable across wallets and profiles.
- **Simplicity first.** Ship a minimal, auditable contract suite that we fully understand and can extend later.
- **Extensible periphery.** Enable us to change and experiment with auction parameters by updating parameters in the contract or writing a whole new auction contract.
- **Optional future resale.** Design the token so that transferability and fee enforcement can be enabled later without migrations.

## 3 Non‑Goals

- A fully‑featured secondary marketplace at launch.
- Perfect on‑chain royalty enforcement across _all_ venues.
- Support for arbitrary ERC‑20 payment tokens; we hardcode USDC for v1.

---

## 4 Glossary

| Term               | Meaning                                                          |
| ------------------ | ---------------------------------------------------------------- |
| **Cast**           | A post on Farcaster (identified by a 32 byte hash).              |
| **FID**            | Farcaster ID, a unique integer ID representing a Farcaster user. |
| **Collectible**    | ERC‑1155 token representing ownership of a cast.                 |
| **Opening Bid**    | First bid on a cast; must be ≥ 1 USDC.                           |
| **Overbid**        | A subsequent bid ≥ max(1 USDC, 10 % of current price).           |
| **Backend Signer** | Off‑chain service that authorises auction parameters and bids.   |

---

## 5 Smart‑Contract Architecture

We deploy five small, modular contracts:

### 5.1 `CollectibleCast` (ERC‑721)

Responsibility: The core collectible token contract. This is the core immutable dependency and we must think carefully about the design. We should keep it as simple as possible.

- Use 32 byte cast hash as a synthetic token ID
- Should also store the FID associated with each cast
- Implements EIP‑2981 royalty info (5% royalty to creator).
- Implement contract level and token level metadata functions
- Default metadata "base URL" for contract and token metadata
- Ability to set metadata URL per token
- Ability to set contract metadata URL
- Allow for multiple minters stored in a simple allowlist with allow/deny functions

### 5.5 `Auction`

Responsibility: Manages collectible auction logic.

- Escrows USDC bids (permits one‑shot `permit` + `bid`).
- Emits events: `AuctionCreated`, `BidPlaced`, `AuctionSettled`, `BidRefunded`.
- Backend‑signed message provides initial auction parameters.
- On settlement: mints token via `CollectibleCast`, pays creator 90%, routes 10% to treasury.
- Bids must provide a backend-signed message for authorization.
- Parameterize auction configuration
- Parameterize splits and other high level configuration
- Use USDC permit for one step approve + bid
- Attempt automatic refund on outbid

## Auction Lifecycle & Mechanics

### Bid Flow (opening bid **and** overbid)

1. **Validate amount**  ≥ \$1 USDC _and_ ≥ `currentBid + max($1, 10 %)`.
2. **Escrow funds**   Pull `amount` USDC from bidder into contract.
3. **Automatic refund**  If a `currentBidder` exists:

   - Attempt to transfer `currentBid` back to `currentBidder`.
   - On failure (e.g., blacklist, contract revert) → credit `refunds[currentBidder] += currentBid` for manual `claimRefund`.

4. **State changes**

   - **First bid only**  `startTime = now`, `endTime = startTime + 24 h`, snapshot `creatorPayee`.
   - **Any bid**  If the bid arrives when `now ≥ endTime – 15 minutes`, set `endTime = now + 15 minutes` (Nouns/Zora‑style anti‑sniping).
   - Update `currentBid` and `currentBidder`.

5. **Emit event**  `BidPlaced(tokenId, bidder, amount, endTime)`.

### States

| State       | Entered When                                                  | Allowed Actions                                                                                             |
| ----------- | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| **Active**  | Immediately when first bid is placed (auction struct created) | Place overbid; timer extends on bids within last 15 min; when no bids for 15 min past `endTime` → **Ended** |
| **Ended**   | Clock elapsed (no bids in last 15 min)                        | Anyone may call **settle** → **Settled**                                                                    |
| **Settled** | Settlement completes                                          | Token exists; auction immutable                                                                             |

### Settlement

On `settle(tokenId)`:

1. **Payouts**  Send 90 % of `currentBid` to `creatorPayee`; 10 % to protocol treasury.
2. **Mint**  `CollectibleCastToken.mint(currentBidder, tokenId, 1)`.
3. **Emit**  `AuctionSettled`.

### Invariants

- Exactly **one** collectible per cast.
- Fixed 90 / 10 revenue split.
- USDC‑only bidding simplifies UX & accounting.
- Fifteen‑minute rolling extension prevents last‑second snipes (end time may exceed 24 h).
