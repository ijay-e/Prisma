# Prisma

## Overview

**Prisma** is a decentralized fractional NFT contract that enables the division of NFTs into tradeable fungible shares. It allows NFT owners to fractionalize their assets, trade shares securely, and initiate community-driven buyouts through on-chain governance mechanisms.

## Key Features

* **Fractional Ownership:** Converts NFTs into fractional shares, giving multiple investors ownership rights.
* **Share Transfers:** Allows share trading between users at agreed prices.
* **Buyout Mechanism:** Enables a major shareholder to acquire full ownership of the NFT by meeting a share threshold and offering a premium.
* **NFT Redemption:** Permits users who hold 100% of the shares to reclaim full NFT ownership.
* **Vault System:** Each fractionalized NFT is stored in a unique vault that tracks all details, balances, and trading history.
* **Buyout Safeguards:** Includes premium pricing, deadlines, and cancellation features to ensure fair and transparent buyout processes.

## Core Components

### 1. **Data Structures**

* **`nft-vaults`**: Stores information about each fractionalized NFT, including contract address, token ID, share distribution, price, and buyout status.
* **`share-balances`**: Tracks the number of shares held by each participant within a vault.
* **`vault-by-nft`**: Maps each NFT to its corresponding vault ID to prevent duplicate fractionalization.
* **`share-holders`**: Maintains a list of active shareholders for each vault.
* **`buyout-offers`**: Records buyout proposals, including buyer details, offer price, committed shares, and deadlines.
* **`trading-history`**: Logs share trades between users for transparency and record-keeping.

### 2. **Functional Modules**

* **Fractionalization:**

  * `fractionalize-nft` transfers an NFT to the contract and issues fractional shares to the original owner.
* **Share Management:**

  * `transfer-shares` enables peer-to-peer share trades while updating share balances and prices.
* **Buyout Process:**

  * `initiate-buyout` starts a buyout if the initiator owns at least 80% of the shares.
  * `accept-buyout` allows shareholders to sell their shares for payout.
  * `complete-buyout` transfers NFT ownership to the buyer after a successful buyout.
  * `cancel-buyout` allows the initiator to revoke a buyout offer before expiration.
* **NFT Redemption:**

  * `redeem-nft` allows full NFT recovery if a single user owns all issued shares.

### 3. **Read-Only Functions**

Provides on-chain transparency through accessible queries:

* Vault data: `get-vault`, `get-vault-count`, `vault-exists`
* Share data: `get-share-balance`, `get-share-holders`, `get-ownership-percentage`
* NFT mapping: `get-vault-by-nft`
* Buyout information: `get-buyout-offer`, `get-buyout-status`
* Vault valuation: `calculate-vault-value`

## Error Codes

* **u1700–u1712**: Covers authorization, invalid transactions, insufficient shares, duplicate vault creation, buyout validation, and fund transfer issues.

## Summary

**Prisma** introduces a secure and transparent framework for NFT fractionalization, enabling liquidity, shared ownership, and fair buyout mechanisms. It democratizes access to high-value NFTs by allowing community participation while maintaining protection for both original owners and investors.
