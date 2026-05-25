;; Crash Game STX template.
;;
;; Players choose a target cash-out multiplier before the round closes. The house
;; commits to a seed before wagers are accepted, then reveals the seed after the
;; round closes. Players whose target is at or below the crash point can claim.

(define-constant PROJECT_OWNER 'SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8)

(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_PAUSED (err u401))
(define-constant ERR_BAD_WAGER (err u402))
(define-constant ERR_UNKNOWN_ROUND (err u403))
(define-constant ERR_BAD_STATUS (err u404))
(define-constant ERR_BAD_COMMITMENT (err u405))
(define-constant ERR_TOO_EARLY (err u406))
(define-constant ERR_TOO_LATE (err u407))
(define-constant ERR_BAD_MULTIPLIER (err u408))
(define-constant ERR_NO_BET (err u409))
(define-constant ERR_ALREADY_CLAIMED (err u410))
(define-constant ERR_FEE_TOO_HIGH (err u411))

(define-constant STATUS_OPEN u1)
(define-constant STATUS_SETTLED u2)
(define-constant STATUS_REFUNDED u3)

(define-data-var contract-owner principal PROJECT_OWNER)
(define-data-var paused bool false)
(define-data-var next-round-id uint u1)
(define-data-var fee-bps uint u250)
(define-data-var min-wager uint u100000)
(define-data-var min-multiplier-bps uint u10100) ;; 1.01x
(define-data-var max-multiplier-bps uint u100000) ;; 10x
(define-data-var fee-recipient principal PROJECT_OWNER)

(define-map rounds
  uint
  {
    house-commitment: (buff 32),
    house-seed: (optional (buff 32)),
    closes-at: uint,
    expires-at: uint,
    crash-bps: uint,
    status: uint
  }
)

(define-map bets
  {round-id: uint, player: principal}
  {
    wager: uint,
    cashout-bps: uint,
    claimed: bool
  }
)

(define-private (only-owner)
  (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
)

(define-private (not-paused)
  (asserts! (not (var-get paused)) ERR_PAUSED)
)

(define-private (seed-commitment-hash (seed (buff 32)))
  (sha256 seed)
)

(define-private (compute-crash-bps (round-id uint) (house-seed (buff 32)))
  ;; Bounded reference formula: 1.00x to 100.99x. Replace with audited game math
  ;; before mainnet if the economics require a specific distribution.
  (+ u10000
    (mod
      (buff-to-uint-be
        (sha256 (concat house-seed (unwrap-panic (to-consensus-buff? round-id))))
      )
      u1000000
    )
  )
)

(define-private (fee-for (amount uint))
  (/ (* amount (var-get fee-bps)) u10000)
)

(define-private (pay-stx (recipient principal) (amount uint))
  (as-contract (stx-transfer? amount tx-sender recipient))
)

(define-public (start-round (house-commitment (buff 32)) (close-in-blocks uint) (refund-window uint))
  (let
    (
      (round-id (var-get next-round-id))
      (closes-at (+ block-height close-in-blocks))
      (expires-at (+ (+ block-height close-in-blocks) refund-window))
    )
    (only-owner)
    (not-paused)
    (map-set rounds round-id
      {
        house-commitment: house-commitment,
        house-seed: none,
        closes-at: closes-at,
        expires-at: expires-at,
        crash-bps: u0,
        status: STATUS_OPEN
      }
    )
    (var-set next-round-id (+ round-id u1))
    (ok {round-id: round-id, closes-at: closes-at, expires-at: expires-at})
  )
)

(define-public (place-bet (round-id uint) (wager uint) (cashout-bps uint))
  (let
    (
      (round (unwrap! (map-get? rounds round-id) ERR_UNKNOWN_ROUND))
    )
    (not-paused)
    (asserts! (is-eq (get status round) STATUS_OPEN) ERR_BAD_STATUS)
    (asserts! (< block-height (get closes-at round)) ERR_TOO_LATE)
    (asserts! (>= wager (var-get min-wager)) ERR_BAD_WAGER)
    (asserts! (and (>= cashout-bps (var-get min-multiplier-bps)) (<= cashout-bps (var-get max-multiplier-bps))) ERR_BAD_MULTIPLIER)
    (try! (stx-transfer? wager tx-sender (as-contract tx-sender)))
    (map-set bets {round-id: round-id, player: tx-sender}
      {
        wager: wager,
        cashout-bps: cashout-bps,
        claimed: false
      }
    )
    (ok true)
  )
)

(define-public (settle-round (round-id uint) (house-seed (buff 32)))
  (let
    (
      (round (unwrap! (map-get? rounds round-id) ERR_UNKNOWN_ROUND))
      (crash-bps (compute-crash-bps round-id house-seed))
    )
    (only-owner)
    (not-paused)
    (asserts! (is-eq (get status round) STATUS_OPEN) ERR_BAD_STATUS)
    (asserts! (>= block-height (get closes-at round)) ERR_TOO_EARLY)
    (asserts! (is-eq (seed-commitment-hash house-seed) (get house-commitment round)) ERR_BAD_COMMITMENT)
    (map-set rounds round-id (merge round {house-seed: (some house-seed), crash-bps: crash-bps, status: STATUS_SETTLED}))
    (ok {round-id: round-id, crash-bps: crash-bps})
  )
)

(define-public (claim-payout (round-id uint))
  (let
    (
      (round (unwrap! (map-get? rounds round-id) ERR_UNKNOWN_ROUND))
      (bet (unwrap! (map-get? bets {round-id: round-id, player: tx-sender}) ERR_NO_BET))
      (won (<= (get cashout-bps bet) (get crash-bps round)))
      (gross-payout (/ (* (get wager bet) (get cashout-bps bet)) u10000))
      (fee (fee-for gross-payout))
      (net-payout (- gross-payout fee))
    )
    (asserts! (is-eq (get status round) STATUS_SETTLED) ERR_BAD_STATUS)
    (asserts! (not (get claimed bet)) ERR_ALREADY_CLAIMED)
    (if won
      (begin
        (try! (pay-stx tx-sender net-payout))
        (if (> fee u0)
          (try! (pay-stx (var-get fee-recipient) fee))
          true
        )
        true
      )
      true
    )
    (map-set bets {round-id: round-id, player: tx-sender} (merge bet {claimed: true}))
    (ok {won: won, payout: (if won net-payout u0), crash-bps: (get crash-bps round)})
  )
)

(define-public (claim-refund (round-id uint))
  (let
    (
      (round (unwrap! (map-get? rounds round-id) ERR_UNKNOWN_ROUND))
      (bet (unwrap! (map-get? bets {round-id: round-id, player: tx-sender}) ERR_NO_BET))
    )
    (asserts! (is-eq (get status round) STATUS_OPEN) ERR_BAD_STATUS)
    (asserts! (>= block-height (get expires-at round)) ERR_TOO_EARLY)
    (asserts! (not (get claimed bet)) ERR_ALREADY_CLAIMED)
    (try! (pay-stx tx-sender (get wager bet)))
    (map-set bets {round-id: round-id, player: tx-sender} (merge bet {claimed: true}))
    (ok true)
  )
)

(define-public (set-paused (value bool))
  (begin
    (only-owner)
    (var-set paused value)
    (ok value)
  )
)

(define-public (set-fee-bps (value uint))
  (begin
    (only-owner)
    (asserts! (<= value u1000) ERR_FEE_TOO_HIGH)
    (var-set fee-bps value)
    (ok value)
  )
)

(define-read-only (get-round (round-id uint))
  (map-get? rounds round-id)
)

(define-read-only (get-bet (round-id uint) (player principal))
  (map-get? bets {round-id: round-id, player: player})
)

(define-read-only (get-config)
  {
    owner: (var-get contract-owner),
    paused: (var-get paused),
    fee-bps: (var-get fee-bps),
    min-wager: (var-get min-wager),
    min-multiplier-bps: (var-get min-multiplier-bps),
    max-multiplier-bps: (var-get max-multiplier-bps),
    fee-recipient: (var-get fee-recipient)
  }
)
