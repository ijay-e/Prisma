;; Fractional NFT Contract
;; Allows NFTs to be fractionalized into tradeable shares

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u1700))
(define-constant ERR-NFT-NOT-FOUND (err u1701))
(define-constant ERR-INSUFFICIENT-SHARES (err u1702))
(define-constant ERR-ALREADY-FRACTIONALIZED (err u1703))
(define-constant ERR-INVALID-AMOUNT (err u1704))
(define-constant ERR-BUYOUT-ACTIVE (err u1705))
(define-constant ERR-INSUFFICIENT-FUNDS (err u1706))
(define-constant ERR-BUYOUT-THRESHOLD-NOT-MET (err u1707))
(define-constant ERR-BUYOUT-NOT-ACTIVE (err u1708))
(define-constant ERR-BUYOUT-EXPIRED (err u1709))
(define-constant ERR-INVALID-RECIPIENT (err u1710))
(define-constant ERR-LIST-OVERFLOW (err u1711))
(define-constant ERR-SAME-SENDER-RECIPIENT (err u1712))

;; Constants
(define-constant BUYOUT-THRESHOLD u8000) ;; 80% of shares needed for buyout
(define-constant BUYOUT-PREMIUM u1200) ;; 20% premium for buyout
(define-constant CONTRACT-OWNER tx-sender)

;; Data variables
(define-data-var vault-counter uint u0)

;; NFT trait
(define-trait nft-trait
  (
    (get-owner (uint) (response (optional principal) uint))
    (transfer (uint principal principal) (response bool uint))
  )
)

;; Data maps
(define-map nft-vaults
  { vault-id: uint }
  {
    nft-contract: principal,
    token-id: uint,
    original-owner: principal,
    total-shares: uint,
    shares-outstanding: uint,
    vault-name: (string-utf8 50),
    share-price: uint,
    created-at: uint,
    buyout-active: bool,
    buyout-price: uint,
    buyout-deadline: uint
  }
)

(define-map share-balances
  { vault-id: uint, holder: principal }
  { shares: uint, last-update: uint }
)

(define-map vault-by-nft
  { nft-contract: principal, token-id: uint }
  { vault-id: uint }
)

(define-map share-holders
  { vault-id: uint }
  { holders: (list 100 principal), holder-count: uint }
)

(define-map buyout-offers
  { vault-id: uint }
  {
    buyer: principal,
    offer-price: uint,
    shares-committed: uint,
    deadline: uint,
    active: bool
  }
)

(define-map trading-history
  { vault-id: uint, trade-id: uint }
  {
    seller: principal,
    buyer: principal,
    shares: uint,
    price-per-share: uint,
    timestamp: uint
  }
)

;; Fractionalize an NFT
(define-public (fractionalize-nft
  (nft-contract <nft-trait>)
  (token-id uint)
  (total-shares uint)
  (initial-price uint)
  (vault-name (string-utf8 50))
)
  (let
    (
      (vault-id (+ (var-get vault-counter) u1))
      (nft-contract-principal (contract-of nft-contract))
      (owner-check (try! (contract-call? nft-contract get-owner token-id)))
    )
    ;; Validation checks
    (asserts! (is-some owner-check) ERR-NFT-NOT-FOUND)
    (asserts! (is-eq (some tx-sender) owner-check) ERR-NOT-AUTHORIZED)
    (asserts! (> total-shares u0) ERR-INVALID-AMOUNT)
    (asserts! (> initial-price u0) ERR-INVALID-AMOUNT)
    (asserts! (< total-shares u1000000000) ERR-INVALID-AMOUNT) ;; Prevent overflow
    (asserts! (is-none (map-get? vault-by-nft { nft-contract: nft-contract-principal, token-id: token-id })) ERR-ALREADY-FRACTIONALIZED)
    
    ;; Transfer NFT to contract
    (try! (contract-call? nft-contract transfer token-id tx-sender (as-contract tx-sender)))
    
    ;; Create vault
    (map-set nft-vaults
      { vault-id: vault-id }
      {
        nft-contract: nft-contract-principal,
        token-id: token-id,
        original-owner: tx-sender,
        total-shares: total-shares,
        shares-outstanding: total-shares,
        vault-name: vault-name,
        share-price: initial-price,
        created-at: block-height,
        buyout-active: false,
        buyout-price: u0,
        buyout-deadline: u0
      }
    )
    
    ;; Map NFT to vault
    (map-set vault-by-nft
      { nft-contract: nft-contract-principal, token-id: token-id }
      { vault-id: vault-id }
    )
    
    ;; Give all initial shares to original owner
    (map-set share-balances
      { vault-id: vault-id, holder: tx-sender }
      { shares: total-shares, last-update: block-height }
    )
    
    ;; Initialize share holders list
    (map-set share-holders
      { vault-id: vault-id }
      { holders: (list tx-sender), holder-count: u1 }
    )
    
    (var-set vault-counter vault-id)
    (ok vault-id)
  )
)

;; Transfer shares between users
(define-public (transfer-shares
  (vault-id uint)
  (recipient principal)
  (shares uint)
  (price-per-share uint)
)
  (let
    (
      (vault-data (unwrap! (map-get? nft-vaults { vault-id: vault-id }) ERR-NFT-NOT-FOUND))
      (sender-balance (unwrap! (map-get? share-balances { vault-id: vault-id, holder: tx-sender }) ERR-INSUFFICIENT-SHARES))
      (recipient-balance (default-to { shares: u0, last-update: u0 } 
        (map-get? share-balances { vault-id: vault-id, holder: recipient })))
      (total-cost (* shares price-per-share))
    )
    ;; Validation checks
    (asserts! (not (is-eq tx-sender recipient)) ERR-SAME-SENDER-RECIPIENT)
    (asserts! (not (get buyout-active vault-data)) ERR-BUYOUT-ACTIVE)
    (asserts! (>= (get shares sender-balance) shares) ERR-INSUFFICIENT-SHARES)
    (asserts! (> shares u0) ERR-INVALID-AMOUNT)
    (asserts! (> price-per-share u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (stx-get-balance recipient) total-cost) ERR-INSUFFICIENT-FUNDS)
    
    ;; Overflow check
    (asserts! (>= (+ (get shares recipient-balance) shares) (get shares recipient-balance)) ERR-INVALID-AMOUNT)
    
    ;; Transfer payment from recipient to sender
    (try! (stx-transfer? total-cost recipient tx-sender))
    
    ;; Update sender balance
    (map-set share-balances
      { vault-id: vault-id, holder: tx-sender }
      { shares: (- (get shares sender-balance) shares), last-update: block-height }
    )
    
    ;; Update recipient balance
    (map-set share-balances
      { vault-id: vault-id, holder: recipient }
      { shares: (+ (get shares recipient-balance) shares), last-update: block-height }
    )
    
    ;; Update share price
    (map-set nft-vaults
      { vault-id: vault-id }
      (merge vault-data { share-price: price-per-share })
    )
    
    ;; Add recipient to holders list if new
    (try! (if (is-eq (get shares recipient-balance) u0)
      (let 
        (
          (holders-data (unwrap! (map-get? share-holders { vault-id: vault-id }) ERR-NFT-NOT-FOUND))
          (current-holders (get holders holders-data))
        )
        (match (as-max-len? (append current-holders recipient) u100)
          updated-holders
            (begin
              (map-set share-holders
                { vault-id: vault-id }
                { holders: updated-holders, holder-count: (+ (get holder-count holders-data) u1) }
              )
              (ok true)
            )
          ;; List is full, cannot add more holders
          ERR-LIST-OVERFLOW
        )
      )
      (ok true)
    ))
    
    (ok true)
  )
)

;; Initiate buyout process
(define-public (initiate-buyout (vault-id uint) (buyout-price uint))
  (let
    (
      (vault-data (unwrap! (map-get? nft-vaults { vault-id: vault-id }) ERR-NFT-NOT-FOUND))
      (user-shares (default-to { shares: u0, last-update: u0 } 
        (map-get? share-balances { vault-id: vault-id, holder: tx-sender })))
      (required-shares (/ (* (get total-shares vault-data) BUYOUT-THRESHOLD) u10000))
      (total-buyout-cost (* buyout-price (get total-shares vault-data)))
      (premium-price (/ (* (get share-price vault-data) BUYOUT-PREMIUM) u1000))
    )
    ;; Validation checks
    (asserts! (>= (get shares user-shares) required-shares) ERR-BUYOUT-THRESHOLD-NOT-MET)
    (asserts! (>= buyout-price premium-price) ERR-INSUFFICIENT-FUNDS)
    (asserts! (not (get buyout-active vault-data)) ERR-BUYOUT-ACTIVE)
    (asserts! (> buyout-price u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (stx-get-balance tx-sender) total-buyout-cost) ERR-INSUFFICIENT-FUNDS)
    
    ;; Overflow check for total cost
    (asserts! (>= total-buyout-cost buyout-price) ERR-INVALID-AMOUNT)
    
    ;; Lock buyout funds
    (try! (stx-transfer? total-buyout-cost tx-sender (as-contract tx-sender)))
    
    ;; Activate buyout
    (map-set nft-vaults
      { vault-id: vault-id }
      (merge vault-data {
        buyout-active: true,
        buyout-price: buyout-price,
        buyout-deadline: (+ block-height u1440) ;; 10 days
      })
    )
    
    ;; Create buyout offer
    (map-set buyout-offers
      { vault-id: vault-id }
      {
        buyer: tx-sender,
        offer-price: buyout-price,
        shares-committed: (get shares user-shares),
        deadline: (+ block-height u1440),
        active: true
      }
    )
    
    (ok true)
  )
)

;; Accept buyout (shareholders sell their shares)
(define-public (accept-buyout (vault-id uint))
  (let
    (
      (vault-data (unwrap! (map-get? nft-vaults { vault-id: vault-id }) ERR-NFT-NOT-FOUND))
      (user-shares (unwrap! (map-get? share-balances { vault-id: vault-id, holder: tx-sender }) ERR-INSUFFICIENT-SHARES))
      (buyout-data (unwrap! (map-get? buyout-offers { vault-id: vault-id }) ERR-BUYOUT-NOT-ACTIVE))
      (payout (* (get shares user-shares) (get buyout-price vault-data)))
    )
    ;; Validation checks
    (asserts! (get buyout-active vault-data) ERR-BUYOUT-NOT-ACTIVE)
    (asserts! (<= block-height (get buyout-deadline vault-data)) ERR-BUYOUT-EXPIRED)
    (asserts! (> (get shares user-shares) u0) ERR-INSUFFICIENT-SHARES)
    (asserts! (not (is-eq tx-sender (get buyer buyout-data))) ERR-NOT-AUTHORIZED)
    
    ;; Overflow check
    (asserts! (>= payout (get shares user-shares)) ERR-INVALID-AMOUNT)
    
    ;; Transfer payout to shareholder
    (try! (as-contract (stx-transfer? payout tx-sender tx-sender)))
    
    ;; Remove shares from user
    (map-delete share-balances { vault-id: vault-id, holder: tx-sender })
    
    ;; Update shares outstanding
    (map-set nft-vaults
      { vault-id: vault-id }
      (merge vault-data { shares-outstanding: (- (get shares-outstanding vault-data) (get shares user-shares)) })
    )
    
    (ok payout)
  )
)

;; Complete buyout and claim NFT
(define-public (complete-buyout (vault-id uint) (nft-contract <nft-trait>))
  (let
    (
      (vault-data (unwrap! (map-get? nft-vaults { vault-id: vault-id }) ERR-NFT-NOT-FOUND))
      (buyout-data (unwrap! (map-get? buyout-offers { vault-id: vault-id }) ERR-BUYOUT-NOT-ACTIVE))
    )
    ;; Validation checks
    (asserts! (is-eq tx-sender (get buyer buyout-data)) ERR-NOT-AUTHORIZED)
    (asserts! (get buyout-active vault-data) ERR-BUYOUT-NOT-ACTIVE)
    (asserts! (> block-height (get buyout-deadline vault-data)) ERR-BUYOUT-EXPIRED)
    (asserts! (is-eq (get nft-contract vault-data) (contract-of nft-contract)) ERR-NFT-NOT-FOUND)
    
    ;; Transfer NFT to buyer
    (try! (as-contract (contract-call? nft-contract transfer (get token-id vault-data) tx-sender (get buyer buyout-data))))
    
    ;; Deactivate vault
    (map-set nft-vaults
      { vault-id: vault-id }
      (merge vault-data { buyout-active: false })
    )
    
    ;; Deactivate buyout offer
    (map-set buyout-offers
      { vault-id: vault-id }
      (merge buyout-data { active: false })
    )
    
    (ok true)
  )
)

;; Redeem NFT (if user owns 100% of shares)
(define-public (redeem-nft (vault-id uint) (nft-contract <nft-trait>))
  (let
    (
      (vault-data (unwrap! (map-get? nft-vaults { vault-id: vault-id }) ERR-NFT-NOT-FOUND))
      (user-shares (unwrap! (map-get? share-balances { vault-id: vault-id, holder: tx-sender }) ERR-INSUFFICIENT-SHARES))
    )
    ;; Validation checks
    (asserts! (is-eq (get shares user-shares) (get total-shares vault-data)) ERR-INSUFFICIENT-SHARES)
    (asserts! (not (get buyout-active vault-data)) ERR-BUYOUT-ACTIVE)
    (asserts! (is-eq (get nft-contract vault-data) (contract-of nft-contract)) ERR-NFT-NOT-FOUND)
    
    ;; Transfer NFT back to user
    (try! (as-contract (contract-call? nft-contract transfer (get token-id vault-data) tx-sender tx-sender)))
    
    ;; Clear user shares
    (map-delete share-balances { vault-id: vault-id, holder: tx-sender })
    
    ;; Update vault
    (map-set nft-vaults
      { vault-id: vault-id }
      (merge vault-data { shares-outstanding: u0 })
    )
    
    (ok true)
  )
)

;; Cancel buyout (only by buyer before deadline)
(define-public (cancel-buyout (vault-id uint))
  (let
    (
      (vault-data (unwrap! (map-get? nft-vaults { vault-id: vault-id }) ERR-NFT-NOT-FOUND))
      (buyout-data (unwrap! (map-get? buyout-offers { vault-id: vault-id }) ERR-BUYOUT-NOT-ACTIVE))
      (refund-amount (* (get buyout-price vault-data) (get total-shares vault-data)))
    )
    ;; Validation checks
    (asserts! (is-eq tx-sender (get buyer buyout-data)) ERR-NOT-AUTHORIZED)
    (asserts! (get buyout-active vault-data) ERR-BUYOUT-NOT-ACTIVE)
    (asserts! (<= block-height (get buyout-deadline vault-data)) ERR-BUYOUT-EXPIRED)
    
    ;; Refund locked funds
    (try! (as-contract (stx-transfer? refund-amount tx-sender (get buyer buyout-data))))
    
    ;; Deactivate buyout
    (map-set nft-vaults
      { vault-id: vault-id }
      (merge vault-data { buyout-active: false, buyout-price: u0, buyout-deadline: u0 })
    )
    
    (map-set buyout-offers
      { vault-id: vault-id }
      (merge buyout-data { active: false })
    )
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-vault (vault-id uint))
  (map-get? nft-vaults { vault-id: vault-id })
)

(define-read-only (get-share-balance (vault-id uint) (holder principal))
  (map-get? share-balances { vault-id: vault-id, holder: holder })
)

(define-read-only (get-vault-by-nft (nft-contract principal) (token-id uint))
  (map-get? vault-by-nft { nft-contract: nft-contract, token-id: token-id })
)

(define-read-only (get-share-holders (vault-id uint))
  (map-get? share-holders { vault-id: vault-id })
)

(define-read-only (get-buyout-offer (vault-id uint))
  (map-get? buyout-offers { vault-id: vault-id })
)

(define-read-only (get-vault-count)
  (var-get vault-counter)
)

(define-read-only (calculate-vault-value (vault-id uint))
  (match (map-get? nft-vaults { vault-id: vault-id })
    vault-data (* (get total-shares vault-data) (get share-price vault-data))
    u0
  )
)

(define-read-only (get-ownership-percentage (vault-id uint) (holder principal))
  (match (map-get? share-balances { vault-id: vault-id, holder: holder })
    balance-data
      (match (map-get? nft-vaults { vault-id: vault-id })
        vault-data
          (/ (* (get shares balance-data) u10000) (get total-shares vault-data))
        u0
      )
    u0
  )
)

;; Check if vault exists
(define-read-only (vault-exists (vault-id uint))
  (is-some (map-get? nft-vaults { vault-id: vault-id }))
)

;; Get buyout status
(define-read-only (get-buyout-status (vault-id uint))
  (match (map-get? nft-vaults { vault-id: vault-id })
    vault-data
      (ok {
        active: (get buyout-active vault-data),
        price: (get buyout-price vault-data),
        deadline: (get buyout-deadline vault-data),
        expired: (> block-height (get buyout-deadline vault-data))
      })
    ERR-NFT-NOT-FOUND
  )
)
