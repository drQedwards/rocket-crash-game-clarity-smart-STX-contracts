;; Fair Flip STX template.
;;
;; Neutral PvHouse coin flip using two-party commit/reveal:
;; 1. house publishes a house seed commitment,
;; 2. player creates a round with a player seed commitment and STX wager,
;; 3. player reveals their seed,
;; 4. house reveals its seed and the contract settles.
;;
;; This is a template. Mainnet deployments need a funded bankroll, tests, and an
;; explicit legal/compliance review.

(define-constant PROJECT_OWNER 'SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8)

(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_PAUSED (err u101))
(define-constant ERR_BAD_WAGER (err u102))
(define-constant ERR_UNKNOWN_ROUND (err u103))
(define-constant ERR_BAD_STATUS (err u104))
(define-constant ERR_BAD_COMMITMENT (err u105))
(define-constant ERR_TOO_EARLY (err u106))
(define-constant ERR_FEE_TOO_HIGH (err u107))

(define-constant STATUS_OPEN u1)
(define-constant STATUS_PLAYER_REVEALED u2)
(define-constant STATUS_SETTLED u3)
(define-constant STATUS_REFUNDED u4)

(define-data-var contract-owner principal PROJECT_OWNER)
(define-data-var paused bool false)
(define-data-var next-round-id uint u1)
(define-data-var fee-bps uint u250) ;; 2.5%
(define-data-var min-wager uint u100000) ;; 0.1 STX
(define-data-var reveal-window uint u144) ;; about one day of Stacks blocks
(define-data-var fee-recipient principal PROJECT_OWNER)

(define-map rounds
  uint
  {
    player: principal,
    wager: uint,
    guess-heads: bool,
    player-commitment: (buff 32),
    house-commitment: (buff 32),
    player-seed: (optional (buff 32)),
    created-at: uint,
    expires-at: uint,
    status: uint
  }
)

(define-private (only-owner)
  (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
)

(define-private (not-paused)
  (asserts! (not (var-get paused)) ERR_PAUSED)
)

(define-private (player-commitment-hash (round-id uint) (player principal) (guess-heads bool) (seed (buff 32)))
  (sha256
    (concat
      seed
      (unwrap-panic (to-consensus-buff? {round-id: round-id, player: player, guess-heads: guess-heads}))
    )
  )
)

(define-private (seed-commitment-hash (seed (buff 32)))
  (sha256 seed)
)

(define-private (flip-result-heads (round-id uint) (player-seed (buff 32)) (house-seed (buff 32)))
  (is-eq
    (mod
      (buff-to-uint-be
        (sha256
          (concat
            (concat player-seed house-seed)
            (unwrap-panic (to-consensus-buff? round-id))
          )
        )
      )
      u2
    )
    u1
  )
)

(define-private (fee-for (amount uint))
  (/ (* amount (var-get fee-bps)) u10000)
)

(define-private (pay-stx (recipient principal) (amount uint))
  (as-contract (stx-transfer? amount tx-sender recipient))
)

(define-public (create-flip
    (player-commitment (buff 32))
    (house-commitment (buff 32))
    (wager uint)
    (guess-heads bool)
  )
  (let
    (
      (round-id (var-get next-round-id))
      (expires-at (+ block-height (var-get reveal-window)))
    )
    (not-paused)
    (asserts! (>= wager (var-get min-wager)) ERR_BAD_WAGER)
    (try! (stx-transfer? wager tx-sender (as-contract tx-sender)))
    (map-set rounds round-id
      {
        player: tx-sender,
        wager: wager,
        guess-heads: guess-heads,
        player-commitment: player-commitment,
        house-commitment: house-commitment,
        player-seed: none,
        created-at: block-height,
        expires-at: expires-at,
        status: STATUS_OPEN
      }
    )
    (var-set next-round-id (+ round-id u1))
    (ok {round-id: round-id, expires-at: expires-at})
  )
)

(define-public (reveal-player (round-id uint) (player-seed (buff 32)))
  (let
    (
      (round (unwrap! (map-get? rounds round-id) ERR_UNKNOWN_ROUND))
    )
    (not-paused)
    (asserts! (is-eq tx-sender (get player round)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status round) STATUS_OPEN) ERR_BAD_STATUS)
    (asserts! (< block-height (get expires-at round)) ERR_TOO_EARLY)
    (asserts!
      (is-eq
        (player-commitment-hash round-id tx-sender (get guess-heads round) player-seed)
        (get player-commitment round)
      )
      ERR_BAD_COMMITMENT
    )
    (map-set rounds round-id (merge round {player-seed: (some player-seed), status: STATUS_PLAYER_REVEALED}))
    (ok true)
  )
)

(define-public (settle-house (round-id uint) (house-seed (buff 32)))
  (let
    (
      (round (unwrap! (map-get? rounds round-id) ERR_UNKNOWN_ROUND))
      (player-seed (unwrap! (get player-seed round) ERR_BAD_STATUS))
      (result-heads (flip-result-heads round-id player-seed house-seed))
      (winner (is-eq result-heads (get guess-heads round)))
      (gross-payout (* (get wager round) u2))
      (fee (fee-for gross-payout))
      (net-payout (- gross-payout fee))
    )
    (not-paused)
    (asserts! (is-eq (get status round) STATUS_PLAYER_REVEALED) ERR_BAD_STATUS)
    (asserts! (is-eq (seed-commitment-hash house-seed) (get house-commitment round)) ERR_BAD_COMMITMENT)
    (if winner
      (begin
        (try! (pay-stx (get player round) net-payout))
        (try! (pay-stx (var-get fee-recipient) fee))
        true
      )
      true
    )
    (map-set rounds round-id (merge round {status: STATUS_SETTLED}))
    (ok {winner: winner, result-heads: result-heads, payout: (if winner net-payout u0)})
  )
)

(define-public (claim-timeout-refund (round-id uint))
  (let
    (
      (round (unwrap! (map-get? rounds round-id) ERR_UNKNOWN_ROUND))
    )
    (asserts! (is-eq tx-sender (get player round)) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq (get status round) STATUS_OPEN) (is-eq (get status round) STATUS_PLAYER_REVEALED)) ERR_BAD_STATUS)
    (asserts! (>= block-height (get expires-at round)) ERR_TOO_EARLY)
    (try! (pay-stx (get player round) (get wager round)))
    (map-set rounds round-id (merge round {status: STATUS_REFUNDED}))
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

(define-public (set-fee-recipient (recipient principal))
  (begin
    (only-owner)
    (var-set fee-recipient recipient)
    (ok recipient)
  )
)

(define-public (set-min-wager (value uint))
  (begin
    (only-owner)
    (var-set min-wager value)
    (ok value)
  )
)

(define-read-only (get-round (round-id uint))
  (map-get? rounds round-id)
)

(define-read-only (get-next-round-id)
  (var-get next-round-id)
)

(define-read-only (get-config)
  {
    owner: (var-get contract-owner),
    paused: (var-get paused),
    fee-bps: (var-get fee-bps),
    min-wager: (var-get min-wager),
    reveal-window: (var-get reveal-window),
    fee-recipient: (var-get fee-recipient)
  }
)
