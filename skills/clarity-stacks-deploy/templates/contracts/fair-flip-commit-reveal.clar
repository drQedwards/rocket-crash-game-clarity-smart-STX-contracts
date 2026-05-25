;; fair-flip-commit-reveal.clar
;;
;; Provably-fair STX coin flip using a two-phase commit-reveal scheme.
;;
;; FAIRNESS MODEL
;; --------------
;; 1. Operator (contract owner) posts `commit-round` with `sha256(secret)`
;;    BEFORE any player bets in that round. The commit is locked: it cannot be
;;    overwritten until the round is settled or expired.
;;
;; 2. Player calls `place-bet` with a chosen side (0 = heads, 1 = tails) and
;;    a wager. The contract records the player's bet AND the
;;    `stacks-block-height` at which the bet landed. The block ID hash at that
;;    height is unknown to the operator at the moment the player's tx is
;;    mined, so the operator cannot retroactively pick a secret that produces
;;    a losing outcome.
;;
;; 3. Operator calls `reveal-round` with the secret. The contract:
;;       - verifies sha256(secret) == stored commit
;;       - waits at least 1 block past the bet's block-height (so the
;;         block-id-header-hash for that height is final and queryable)
;;       - derives outcome = (sha256(secret || block-id-hash(bet-block)) mod 2)
;;       - pays the player if their chosen side == outcome
;;
;; 4. If the operator fails to reveal within REVEAL-WINDOW blocks of the bet,
;;    the player can `claim-refund`. The bet is returned and a slashing penalty
;;    is taken from the house bond.
;;
;; WAGER ASSET
;; -----------
;; This template uses native STX. For SIP-010 / sBTC wagers, see
;; `fair-flip-token.clar`.
;;
;; ADMIN
;; -----
;; The deploying principal is the initial contract owner. Owner is rotatable
;; via `set-contract-owner`. Owner is the only principal that can post
;; commits, reveal, change parameters, or pause the contract. The deploying
;; principal is read at deploy-time; do NOT hardcode a principal here.

;; -----------------------------------------------------------------------------
;; Constants & errors
;; -----------------------------------------------------------------------------

(define-constant SIDE-HEADS u0)
(define-constant SIDE-TAILS u1)

(define-constant ERR-NOT-OWNER         (err u100))
(define-constant ERR-PAUSED            (err u101))
(define-constant ERR-NO-COMMIT         (err u102))
(define-constant ERR-COMMIT-EXISTS     (err u103))
(define-constant ERR-BAD-SECRET        (err u104))
(define-constant ERR-BAD-SIDE          (err u105))
(define-constant ERR-BET-TOO-SMALL     (err u106))
(define-constant ERR-BET-TOO-LARGE     (err u107))
(define-constant ERR-NO-BET            (err u108))
(define-constant ERR-ALREADY-SETTLED   (err u109))
(define-constant ERR-TOO-EARLY         (err u110))
(define-constant ERR-NOT-EXPIRED       (err u111))
(define-constant ERR-NO-BLOCK-HASH     (err u112))
(define-constant ERR-INSUFFICIENT-BOND (err u113))
(define-constant ERR-NOTHING-TO-CLAIM  (err u114))
(define-constant ERR-TRANSFER-FAILED   (err u115))
(define-constant ERR-NOT-PLAYER        (err u116))

;; -----------------------------------------------------------------------------
;; State
;; -----------------------------------------------------------------------------

(define-data-var contract-owner principal tx-sender)
(define-data-var paused bool false)

;; House-fee in basis points (e.g. u250 = 2.5%). Capped at 1000 (10%) by setter.
(define-data-var house-fee-bps uint u250)

;; Wager bounds in microSTX.
(define-data-var min-bet uint u1000000)        ;; 1 STX
(define-data-var max-bet uint u100000000)      ;; 100 STX

;; Number of stacks-blocks the operator has to reveal after a bet.
(define-data-var reveal-window uint u72)       ;; ~12 hours at ~10 min blocks

;; Slashing penalty (microSTX) deducted from the house bond per expired bet,
;; in addition to refunding the player's wager.
(define-data-var expiry-penalty uint u1000000) ;; 1 STX

;; Monotonically increasing round id.
(define-data-var current-round uint u0)

;; sha256(secret) for each round, set by operator before any bet lands.
(define-map round-commit uint (buff 32))

;; The revealed secret, set when the round is settled. Public for auditability.
(define-map round-secret uint (buff 32))

;; Per-round bet, indexed by round id (one bet per round in this template).
(define-map round-bet
  uint
  {
    player: principal,
    side: uint,            ;; 0 or 1
    amount: uint,          ;; microSTX
    bet-block: uint,       ;; stacks-block-height when the bet landed
    settled: bool
  }
)

;; Withdrawable balance per principal (winnings, refunds, accumulated fees).
(define-map balances principal uint)

;; House bond available to back operator obligations. Funded via `fund-bond`.
(define-data-var house-bond uint u0)

;; -----------------------------------------------------------------------------
;; Read-only helpers
;; -----------------------------------------------------------------------------

(define-read-only (is-contract-owner (who principal))
  (is-eq who (var-get contract-owner))
)

(define-read-only (get-contract-owner) (var-get contract-owner))
(define-read-only (get-paused)         (var-get paused))
(define-read-only (get-house-fee-bps)  (var-get house-fee-bps))
(define-read-only (get-min-bet)        (var-get min-bet))
(define-read-only (get-max-bet)        (var-get max-bet))
(define-read-only (get-reveal-window)  (var-get reveal-window))
(define-read-only (get-current-round)  (var-get current-round))
(define-read-only (get-house-bond)     (var-get house-bond))

(define-read-only (get-round-commit (round uint))
  (map-get? round-commit round)
)

(define-read-only (get-round-secret (round uint))
  (map-get? round-secret round)
)

(define-read-only (get-round-bet (round uint))
  (map-get? round-bet round)
)

(define-read-only (get-balance (who principal))
  (default-to u0 (map-get? balances who))
)

;; Compute potential payout for a winning bet of `amount`, after the house fee.
;; Player wagers X, gets back 2X if they win, minus house fee on the winnings.
;; net = X + X * (10000 - fee) / 10000
(define-read-only (compute-payout (amount uint))
  (let
    (
      (fee-bps (var-get house-fee-bps))
      (gross-winnings amount)
      (net-winnings (/ (* gross-winnings (- u10000 fee-bps)) u10000))
    )
    (+ amount net-winnings)
  )
)

;; -----------------------------------------------------------------------------
;; Admin (owner-only)
;; -----------------------------------------------------------------------------

(define-private (assert-owner)
  (if (is-contract-owner tx-sender) (ok true) ERR-NOT-OWNER)
)

(define-private (assert-not-paused)
  (if (var-get paused) ERR-PAUSED (ok true))
)

(define-public (set-contract-owner (new-owner principal))
  (begin
    (try! (assert-owner))
    (var-set contract-owner new-owner)
    (ok true)
  )
)

(define-public (set-paused (p bool))
  (begin
    (try! (assert-owner))
    (var-set paused p)
    (ok true)
  )
)

(define-public (set-house-fee-bps (bps uint))
  (begin
    (try! (assert-owner))
    (asserts! (<= bps u1000) (err u200)) ;; max 10%
    (var-set house-fee-bps bps)
    (ok true)
  )
)

(define-public (set-bet-bounds (mn uint) (mx uint))
  (begin
    (try! (assert-owner))
    (asserts! (and (> mn u0) (>= mx mn)) (err u201))
    (var-set min-bet mn)
    (var-set max-bet mx)
    (ok true)
  )
)

(define-public (set-reveal-window (blocks uint))
  (begin
    (try! (assert-owner))
    (asserts! (and (>= blocks u3) (<= blocks u1008)) (err u202)) ;; ~30 min – 7 days
    (var-set reveal-window blocks)
    (ok true)
  )
)

(define-public (set-expiry-penalty (amount uint))
  (begin
    (try! (assert-owner))
    (var-set expiry-penalty amount)
    (ok true)
  )
)

;; Operator funds the bond pool that backs payouts and expiry penalties.
(define-public (fund-bond (amount uint))
  (begin
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set house-bond (+ (var-get house-bond) amount))
    (ok true)
  )
)

;; Operator withdraws excess bond. Can only withdraw what's not earmarked
;; against open commitments (a single round in this template, so the simplest
;; check is "no active unsettled bet").
(define-public (withdraw-bond (amount uint))
  (let
    (
      (round (var-get current-round))
      (bet (map-get? round-bet round))
    )
    (try! (assert-owner))
    (asserts! (<= amount (var-get house-bond)) ERR-INSUFFICIENT-BOND)
    (asserts!
      (match bet b (get settled b) true)
      (err u203))
    (var-set house-bond (- (var-get house-bond) amount))
    (let ((recipient (var-get contract-owner)))
      (try! (as-contract (stx-transfer? amount tx-sender recipient)))
      (ok amount)
    )
  )
)

;; -----------------------------------------------------------------------------
;; Round lifecycle
;; -----------------------------------------------------------------------------

;; Operator commits to a secret for the next round. Must be called BEFORE the
;; player places a bet for that round.
(define-public (commit-round (commit (buff 32)))
  (let
    (
      (next-round (+ (var-get current-round) u1))
    )
    (try! (assert-owner))
    (try! (assert-not-paused))
    (asserts! (is-none (map-get? round-commit next-round)) ERR-COMMIT-EXISTS)
    (map-set round-commit next-round commit)
    (var-set current-round next-round)
    (ok next-round)
  )
)

;; Player places a bet on the current round.
(define-public (place-bet (side uint) (amount uint))
  (let
    (
      (round (var-get current-round))
      (existing (map-get? round-bet round))
    )
    (try! (assert-not-paused))
    (asserts! (or (is-eq side SIDE-HEADS) (is-eq side SIDE-TAILS)) ERR-BAD-SIDE)
    (asserts! (>= amount (var-get min-bet)) ERR-BET-TOO-SMALL)
    (asserts! (<= amount (var-get max-bet)) ERR-BET-TOO-LARGE)
    (asserts! (is-some (map-get? round-commit round)) ERR-NO-COMMIT)
    (asserts! (is-none existing) ERR-COMMIT-EXISTS)

    ;; House must have enough bond to cover the maximum payout for this bet.
    (asserts! (>= (var-get house-bond) (compute-payout amount)) ERR-INSUFFICIENT-BOND)

    ;; Pull the wager into the contract.
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

    (map-set round-bet round
      {
        player: tx-sender,
        side: side,
        amount: amount,
        bet-block: stacks-block-height,
        settled: false
      }
    )
    (ok round)
  )
)

;; Operator reveals the secret for the round and settles the bet.
(define-public (reveal-round (round uint) (secret (buff 32)))
  (let
    (
      (commit (unwrap! (map-get? round-commit round) ERR-NO-COMMIT))
      (bet (unwrap! (map-get? round-bet round) ERR-NO-BET))
      (player (get player bet))
      (side (get side bet))
      (amount (get amount bet))
      (bet-block (get bet-block bet))
    )
    (try! (assert-owner))
    (asserts! (not (get settled bet)) ERR-ALREADY-SETTLED)
    (asserts! (is-eq (sha256 secret) commit) ERR-BAD-SECRET)
    ;; The block-id-header-hash for `bet-block` only exists once the chain
    ;; has built at least one block on top of it.
    (asserts! (> stacks-block-height bet-block) ERR-TOO-EARLY)

    (let
      (
        (block-hash (unwrap! (get-stacks-block-info? id-header-hash bet-block)
                             ERR-NO-BLOCK-HASH))
        (mix (concat secret block-hash))
        (digest (sha256 mix))
        ;; SHA-256 yields 32 bytes; buff-to-uint-be tops out at 16 bytes (128 bits).
        ;; Take the high 16 bytes; modding by 2 still yields the LSB of the digest's
        ;; high half, which is uniformly distributed for an unbroken hash.
        (digest-hi (unwrap-panic (slice? digest u0 u16)))
        (outcome (mod (buff-to-uint-be digest-hi) u2))
        (player-won (is-eq side outcome))
        (payout (compute-payout amount))
      )
      (map-set round-secret round secret)
      (map-set round-bet round (merge bet {settled: true}))

      (if player-won
        (begin
          ;; Pay player. House bond shrinks by net winnings (the player's stake
          ;; was already in the contract, so only the operator's contribution
          ;; comes from the bond).
          (var-set house-bond
            (- (var-get house-bond) (- payout amount)))
          (map-set balances player (+ (get-balance player) payout))
        )
        ;; House wins. Player's stake is converted into bond, minus fee
        ;; recorded into owner's balance.
        (let
          (
            (fee (/ (* amount (var-get house-fee-bps)) u10000))
            (to-bond (- amount fee))
            (owner (var-get contract-owner))
          )
          (var-set house-bond (+ (var-get house-bond) to-bond))
          (map-set balances owner (+ (get-balance owner) fee))
        )
      )
      (ok {round: round, outcome: outcome, player-won: player-won, payout: payout})
    )
  )
)

;; If the operator has not revealed within REVEAL-WINDOW blocks, the player
;; can refund themselves and trigger a slashing penalty against the house bond.
(define-public (claim-refund (round uint))
  (let
    (
      (bet (unwrap! (map-get? round-bet round) ERR-NO-BET))
      (player (get player bet))
      (amount (get amount bet))
      (bet-block (get bet-block bet))
      (deadline (+ bet-block (var-get reveal-window)))
      (penalty (var-get expiry-penalty))
      (bond (var-get house-bond))
    )
    (asserts! (is-eq tx-sender player) ERR-NOT-PLAYER)
    (asserts! (not (get settled bet)) ERR-ALREADY-SETTLED)
    (asserts! (> stacks-block-height deadline) ERR-NOT-EXPIRED)

    (let
      (
        (slash (if (> bond penalty) penalty bond))
        (refund-total (+ amount slash))
      )
      (map-set round-bet round (merge bet {settled: true}))
      (var-set house-bond (- bond slash))
      (map-set balances player (+ (get-balance player) refund-total))
      (ok refund-total)
    )
  )
)

;; -----------------------------------------------------------------------------
;; Withdrawals
;; -----------------------------------------------------------------------------

(define-public (withdraw)
  (let
    (
      (caller tx-sender)
      (bal (get-balance caller))
    )
    (asserts! (> bal u0) ERR-NOTHING-TO-CLAIM)
    (map-set balances caller u0)
    (try! (as-contract (stx-transfer? bal tx-sender caller)))
    (ok bal)
  )
)

(define-public (withdraw-house-fees)
  (let
    (
      (owner (var-get contract-owner))
      (bal (get-balance owner))
    )
    (try! (assert-owner))
    (asserts! (> bal u0) ERR-NOTHING-TO-CLAIM)
    (map-set balances owner u0)
    (try! (as-contract (stx-transfer? bal tx-sender owner)))
    (ok bal)
  )
)
