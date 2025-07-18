# Collectible Casts - New Tasks

## 1. Add a BidRefunded event to auctions

When the auction contract refunds a bid, we should emit a `BidRefunded(address indexed to, amount uint256)` event. Please add this event and TDD your change.

## 2. Add `refundedBidderFid` to `AuctionCancelled` event

We should add the FID of the refunded bidder to the `AuctionCancelled` event for consistency with the rest of the auction events. Please update this event and TDD your change.

## 3. Allow cancellation of ended auctions

We should allow cancellation of auctions in either Active or Ended state. This is a larger change to the state transitionst than items 1 and 2, so please thoroughly test it.
