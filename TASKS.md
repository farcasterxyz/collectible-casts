# Collectible Casts - New Tasks

## 1. Add emergency auction recovery functionality

Add an `onlyOwner` emergency recovery function to handle stuck auctions due to transfer failures (e.g., USDC blacklisted addresses, malicious contract recipients, etc.).

**Requirements:**

- Owner-only function (no offchain authorizer required)
- Add new `Recovered` terminal state to `AuctionState` enum
- Works on both Active and Ended auctions (treat both as emergency cancellation)
- Refund highest bidder to specified recovery address (don't mint NFT)
- Simple function signature: `recover(bytes32 castHash, address refundTo)`
- Emit `AuctionRecovered` event with recovery details
- Comprehensive testing including edge cases and state transitions
- Should handle any transfer failure scenario (not just blacklisting)

This provides a clean "escape hatch" for DoS scenarios - essentially "emergency cancel with custom refund address".
