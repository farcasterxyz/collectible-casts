# Collectible Casts

A new way for Farcaster users to support creators through collectible NFTs.

## Overview

Collectible Casts introduce a mechanism where every cast can be *collected*.  
If more than one user attempts to collect the same cast within the bidding window, an ascending auction determines the final owner and price.  

The winning bidder receives an ERC-721 token representing the collectible, minted directly to their wallet.  
- **90%** of the winning bid goes to the creator  
- **10%** accrues to the protocol treasury for growth incentives

For full product details and technical specification see the doc  
[here](https://farcasterhq.notion.site/Collectibles-2306a6c0c10180d7a917c24892662a3c).

## Goals

- Give creators a new, sustainable monetization tool directly on Farcaster  
- Turn memorable or valuable casts into unique digital collectibles  
- Create a fair, transparent, and on-chain auction system when demand exists  
- Keep the collecting experience fast and feel native to the Farcaster app  
- Distribute the majority of revenue to creators (90/10 split)  
- Build a treasury that can fund future protocol development and user incentives

## How It Works (User Flow)

1. Any user sees a “Collect” button on a cast  
2. They choose an amount and submit (minimum price set by creator or protocol)  
3. If they’re the only collector in the window → they get it instantly at their price  
4. If multiple people collect → automatic ascending auction begins  
5. At the end of the auction window, highest bidder wins the ERC-721 NFT  
6. Funds are automatically split: 90% → creator, 10% → treasury  
7. NFT appears in the winner’s wallet and profile

## Links

- Full spec: https://farcasterhq.notion.site/Collectibles-2306a6c0c10180d7a917c24892662a3c
- Repository: https://github.com/[your-org]/collectible-casts
