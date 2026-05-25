;; Fair Flip signed-randomness template.
;;
;; This template is for an operator/oracle that publishes signed randomness for each
;; round. In production, the signer should be backed by a real VRF or externally
;; auditable randomness process, not by an opaque house-controlled script.

(define-constant PROJECT_OWNER 'SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8)

(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_PAUSED (err u201))
(define-constant ERR_BAD_WAGER (err u202))
(define-constant ERR_UNKNOWN_ROUND (err u203))
(define-constant ERR_BAD_STATUS (err u204))
(define-constant ERR_BAD_SIGNATURE (err u205))
(define-constant ERR_TOO_EARLY (err u206))
(define-constant ERR_FEE_TOO_HIGH (err u207))

(define-constant STATUS_OPEN u1)
(define-constant STATUS_SETTLED u2)
(define-constant STATUS_REFUNDED u3)

(define-data-var contract-owner principal PROJECT_OWNER)
(define-data-var paused bool false)
(define-data-var next-round-id uint u1)
(define-data-var fee-bps uint u250)
(define-data-var min-wager uint u100000)
(define-data-var settle-window uint u144)
(define-data-var fee-recipient principal PROJECT_OWNER)

;; Replace this in deployment config before mainnet. It must match the signer that
;; produces round randomness signatures.
(define-data-var oracle-public-key (buff 33) 0x020000000000000000000000000000000000000000000000000000000000000001)

(define-map rounds
  uint
  {
    player: principal,
    wager: uint,
    guess-heads: bool,
    created-at: uint,
    expires-at: uint,
    status: uint,
    randomness: (optional (buff 32))
  }
)

(define-private (only-owner)
  (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
)

(define-private (not-paused)
  (asserts! (not (var-get paused)) ERR_PAUSED)
)

(define-private (round-message-hash (round-id uint) (player principal) (wager uint) (guess-heads bool) (randomness (buff 32)))
  (sha256
    (unwrap-panic
      (to-consensus-buff?
        {
          contract: (as-contract tx-sender),
          round-id: round-id,
          player: player,
          wager: wager,
          guess-heads: guess-heads,
          randomness: randomness
        }
      )
    )
  )
)

(define-private (result-heads (round-id uint) (randomness (buff 32)))
  (is-eq
    (mod
      (buff-to-uint-be
        (sha256 (concat randomness (unwrap-panic (to-consensus-buff? round-id))))
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

(define-public (create-flip (wager uint) (guess-heads bool))
  (let
    (
      (round-id (var-get next-round-id))
      (expires-at (+ block-height (var-get settle-window)))
    )
    (not-paused)
    (asserts! (>= wager (var-get min-wager)) ERR_BAD_WAGER)
    (try! (stx-transfer? wager tx-sender (as-contract tx-sender)))
    (map-set rounds round-id
      {
        player: tx-sender,
        wager: wager,
        guess-heads: guess-heads,
        created-at: block-height,
        expires-at: expires-at,
        status: STATUS_OPEN,
        randomness: none
      }
    )
    (var-set next-round-id (+ round-id u1))
    (ok {round-id: round-id, expires-at: expires-at})
  )
)

(define-public (settle (round-id uint) (randomness (buff 32)) (signature (buff 65)))
  (let
    (
      (round (unwrap! (map-get? rounds round-id) ERR_UNKNOWN_ROUND))
      (message-hash (round-message-hash round-id (get player round) (get wager round) (get guess-heads round) randomness))
      (heads (result-heads round-id randomness))
      (winner (is-eq heads (get guess-heads round)))
      (gross-payout (* (get wager round) u2))
      (fee (fee-for gross-payout))
      (net-payout (- gross-payout fee))
    )
    (not-paused)
    (asserts! (is-eq (get status round) STATUS_OPEN) ERR_BAD_STATUS)
    (asserts! (secp256k1-verify message-hash signature (var-get oracle-public-key)) ERR_BAD_SIGNATURE)
    (if winner
      (begin
        (try! (pay-stx (get player round) net-payout))
        (try! (pay-stx (var-get fee-recipient) fee))
        true
      )
      true
    )
    (map-set rounds round-id (merge round {status: STATUS_SETTLED, randomness: (some randomness)}))
    (ok {winner: winner, result-heads: heads, payout: (if winner net-payout u0)})
  )
)

(define-public (claim-timeout-refund (round-id uint))
  (let
    (
      (round (unwrap! (map-get? rounds round-id) ERR_UNKNOWN_ROUND))
    )
    (asserts! (is-eq tx-sender (get player round)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status round) STATUS_OPEN) ERR_BAD_STATUS)
    (asserts! (>= block-height (get expires-at round)) ERR_TOO_EARLY)
    (try! (pay-stx (get player round) (get wager round)))
    (map-set rounds round-id (merge round {status: STATUS_REFUNDED}))
    (ok true)
  )
)

(define-public (set-oracle-public-key (public-key (buff 33)))
  (begin
    (only-owner)
    (var-set oracle-public-key public-key)
    (ok public-key)
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
    oracle-public-key: (var-get oracle-public-key),
    fee-bps: (var-get fee-bps),
    min-wager: (var-get min-wager),
    settle-window: (var-get settle-window),
    fee-recipient: (var-get fee-recipient)
  }
)
