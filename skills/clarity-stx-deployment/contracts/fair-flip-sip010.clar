;; Fair Flip SIP-010 token wager template.
;;
;; Use with sBTC or another audited SIP-010 fungible token. Deploy this contract
;; beside sip010-ft-trait.clar and pin allowed token contracts in your app/config.

(use-trait sip010-ft-trait .sip010-ft-trait.sip010-ft-trait)

(define-constant PROJECT_OWNER 'SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8)

(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_PAUSED (err u301))
(define-constant ERR_BAD_WAGER (err u302))
(define-constant ERR_UNKNOWN_ROUND (err u303))
(define-constant ERR_BAD_STATUS (err u304))
(define-constant ERR_BAD_COMMITMENT (err u305))
(define-constant ERR_TOO_EARLY (err u306))
(define-constant ERR_BAD_TOKEN (err u307))
(define-constant ERR_FEE_TOO_HIGH (err u308))

(define-constant STATUS_OPEN u1)
(define-constant STATUS_PLAYER_REVEALED u2)
(define-constant STATUS_SETTLED u3)
(define-constant STATUS_REFUNDED u4)

(define-data-var contract-owner principal PROJECT_OWNER)
(define-data-var paused bool false)
(define-data-var next-round-id uint u1)
(define-data-var fee-bps uint u250)
(define-data-var min-wager uint u1)
(define-data-var reveal-window uint u144)
(define-data-var fee-recipient principal PROJECT_OWNER)

(define-map rounds
  uint
  {
    player: principal,
    asset-contract: principal,
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

(define-private (result-heads (round-id uint) (player-seed (buff 32)) (house-seed (buff 32)))
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

(define-private (pay-token (token <sip010-ft-trait>) (recipient principal) (amount uint))
  (as-contract (contract-call? token transfer amount tx-sender recipient none))
)

(define-public (create-flip
    (token <sip010-ft-trait>)
    (player-commitment (buff 32))
    (house-commitment (buff 32))
    (wager uint)
    (guess-heads bool)
  )
  (let
    (
      (round-id (var-get next-round-id))
      (expires-at (+ block-height (var-get reveal-window)))
      (asset-contract (contract-of token))
    )
    (not-paused)
    (asserts! (>= wager (var-get min-wager)) ERR_BAD_WAGER)
    (try! (contract-call? token transfer wager tx-sender (as-contract tx-sender) none))
    (map-set rounds round-id
      {
        player: tx-sender,
        asset-contract: asset-contract,
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
    (ok {round-id: round-id, asset-contract: asset-contract, expires-at: expires-at})
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

(define-public (settle-house (token <sip010-ft-trait>) (round-id uint) (house-seed (buff 32)))
  (let
    (
      (round (unwrap! (map-get? rounds round-id) ERR_UNKNOWN_ROUND))
      (player-seed (unwrap! (get player-seed round) ERR_BAD_STATUS))
      (heads (result-heads round-id player-seed house-seed))
      (winner (is-eq heads (get guess-heads round)))
      (gross-payout (* (get wager round) u2))
      (fee (fee-for gross-payout))
      (net-payout (- gross-payout fee))
    )
    (not-paused)
    (asserts! (is-eq (contract-of token) (get asset-contract round)) ERR_BAD_TOKEN)
    (asserts! (is-eq (get status round) STATUS_PLAYER_REVEALED) ERR_BAD_STATUS)
    (asserts! (is-eq (seed-commitment-hash house-seed) (get house-commitment round)) ERR_BAD_COMMITMENT)
    (if winner
      (begin
        (try! (pay-token token (get player round) net-payout))
        (try! (pay-token token (var-get fee-recipient) fee))
        true
      )
      true
    )
    (map-set rounds round-id (merge round {status: STATUS_SETTLED}))
    (ok {winner: winner, result-heads: heads, payout: (if winner net-payout u0)})
  )
)

(define-public (claim-timeout-refund (token <sip010-ft-trait>) (round-id uint))
  (let
    (
      (round (unwrap! (map-get? rounds round-id) ERR_UNKNOWN_ROUND))
    )
    (asserts! (is-eq (contract-of token) (get asset-contract round)) ERR_BAD_TOKEN)
    (asserts! (is-eq tx-sender (get player round)) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq (get status round) STATUS_OPEN) (is-eq (get status round) STATUS_PLAYER_REVEALED)) ERR_BAD_STATUS)
    (asserts! (>= block-height (get expires-at round)) ERR_TOO_EARLY)
    (try! (pay-token token (get player round) (get wager round)))
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

(define-read-only (get-round (round-id uint))
  (map-get? rounds round-id)
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
