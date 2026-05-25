;; fair-flip-token.clar
;;
;; SIP-010 fungible-token coin flip with two-phase commit-reveal RNG.
;;
;; Identical fairness model to fair-flip-commit-reveal.clar, but the wager
;; asset is any SIP-010 fungible token — including sBTC. The token contract
;; is registered once via `set-token` (owner-only); after that, every public
;; function takes a `<ft-trait>` parameter that must match the registered
;; principal.
;;
;; sBTC mainnet:  'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token
;; sBTC testnet:  'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token
;; Verify the canonical addresses against
;; https://docs.stacks.co/concepts/sbtc/contracts before mainnet deploy.

(use-trait ft-trait .sip-010-trait.sip-010-trait)

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
(define-constant ERR-NOT-PLAYER        (err u115))
(define-constant ERR-WRONG-TOKEN       (err u116))
(define-constant ERR-NO-TOKEN          (err u117))

(define-data-var contract-owner principal tx-sender)
(define-data-var paused bool false)
(define-data-var house-fee-bps uint u250)

;; Token bounds are denominated in the token's smallest unit (e.g. satoshis
;; for sBTC). Operator MUST pick numbers that match the token's decimals.
(define-data-var min-bet uint u10000)
(define-data-var max-bet uint u100000000)

(define-data-var reveal-window uint u72)
(define-data-var expiry-penalty uint u10000)
(define-data-var house-bond uint u0)
(define-data-var current-round uint u0)

;; The single SIP-010 token principal accepted by this contract instance.
(define-data-var token-principal (optional principal) none)

(define-map round-commit uint (buff 32))
(define-map round-secret uint (buff 32))
(define-map round-bet
  uint
  {
    player: principal,
    side: uint,
    amount: uint,
    bet-block: uint,
    settled: bool
  })
(define-map balances principal uint)

;; -----------------------------------------------------------------------------
;; Read-only
;; -----------------------------------------------------------------------------

(define-read-only (is-contract-owner (who principal))
  (is-eq who (var-get contract-owner)))

(define-read-only (get-contract-owner) (var-get contract-owner))
(define-read-only (get-paused)         (var-get paused))
(define-read-only (get-house-bond)     (var-get house-bond))
(define-read-only (get-current-round)  (var-get current-round))
(define-read-only (get-token-principal) (var-get token-principal))
(define-read-only (get-round-commit (r uint)) (map-get? round-commit r))
(define-read-only (get-round-bet (r uint)) (map-get? round-bet r))
(define-read-only (get-balance (who principal))
  (default-to u0 (map-get? balances who)))

(define-read-only (compute-payout (amount uint))
  (let
    (
      (fee-bps (var-get house-fee-bps))
      (net-winnings (/ (* amount (- u10000 fee-bps)) u10000))
    )
    (+ amount net-winnings)))

;; -----------------------------------------------------------------------------
;; Helpers
;; -----------------------------------------------------------------------------

(define-private (assert-owner)
  (if (is-contract-owner tx-sender) (ok true) ERR-NOT-OWNER))

(define-private (assert-not-paused)
  (if (var-get paused) ERR-PAUSED (ok true)))

(define-private (assert-token (token <ft-trait>))
  (let ((tp (var-get token-principal)))
    (asserts! (is-some tp) ERR-NO-TOKEN)
    (asserts! (is-eq (contract-of token) (unwrap-panic tp)) ERR-WRONG-TOKEN)
    (ok true)))

;; -----------------------------------------------------------------------------
;; Admin
;; -----------------------------------------------------------------------------

(define-public (set-contract-owner (new-owner principal))
  (begin (try! (assert-owner)) (var-set contract-owner new-owner) (ok true)))

(define-public (set-paused (p bool))
  (begin (try! (assert-owner)) (var-set paused p) (ok true)))

;; Set ONCE; cannot be changed after first bet to avoid stranded balances.
(define-public (set-token (token-contract principal))
  (begin
    (try! (assert-owner))
    (asserts! (is-eq u0 (var-get current-round)) (err u204))
    (var-set token-principal (some token-contract))
    (ok true)))

(define-public (set-house-fee-bps (bps uint))
  (begin
    (try! (assert-owner))
    (asserts! (<= bps u1000) (err u200))
    (var-set house-fee-bps bps)
    (ok true)))

(define-public (set-bet-bounds (mn uint) (mx uint))
  (begin
    (try! (assert-owner))
    (asserts! (and (> mn u0) (>= mx mn)) (err u201))
    (var-set min-bet mn)
    (var-set max-bet mx)
    (ok true)))

(define-public (set-reveal-window (blocks uint))
  (begin
    (try! (assert-owner))
    (asserts! (and (>= blocks u3) (<= blocks u1008)) (err u202))
    (var-set reveal-window blocks)
    (ok true)))

(define-public (set-expiry-penalty (amount uint))
  (begin (try! (assert-owner)) (var-set expiry-penalty amount) (ok true)))

(define-public (fund-bond (token <ft-trait>) (amount uint))
  (begin
    (try! (assert-token token))
    (try! (contract-call? token transfer
            amount tx-sender (as-contract tx-sender) none))
    (var-set house-bond (+ (var-get house-bond) amount))
    (ok true)))

(define-public (withdraw-bond (token <ft-trait>) (amount uint))
  (let
    (
      (round (var-get current-round))
      (bet (map-get? round-bet round))
    )
    (try! (assert-owner))
    (try! (assert-token token))
    (asserts! (<= amount (var-get house-bond)) ERR-INSUFFICIENT-BOND)
    (asserts! (match bet b (get settled b) true) (err u203))
    (var-set house-bond (- (var-get house-bond) amount))
    (let ((recipient (var-get contract-owner)))
      (try! (as-contract (contract-call? token transfer
              amount tx-sender recipient none)))
      (ok amount))))

;; -----------------------------------------------------------------------------
;; Round lifecycle
;; -----------------------------------------------------------------------------

(define-public (commit-round (commit (buff 32)))
  (let ((next-round (+ (var-get current-round) u1)))
    (try! (assert-owner))
    (try! (assert-not-paused))
    (asserts! (is-some (var-get token-principal)) ERR-NO-TOKEN)
    (asserts! (is-none (map-get? round-commit next-round)) ERR-COMMIT-EXISTS)
    (map-set round-commit next-round commit)
    (var-set current-round next-round)
    (ok next-round)))

(define-public (place-bet (token <ft-trait>) (side uint) (amount uint))
  (let
    (
      (round (var-get current-round))
      (existing (map-get? round-bet round))
    )
    (try! (assert-not-paused))
    (try! (assert-token token))
    (asserts! (or (is-eq side SIDE-HEADS) (is-eq side SIDE-TAILS)) ERR-BAD-SIDE)
    (asserts! (>= amount (var-get min-bet)) ERR-BET-TOO-SMALL)
    (asserts! (<= amount (var-get max-bet)) ERR-BET-TOO-LARGE)
    (asserts! (is-some (map-get? round-commit round)) ERR-NO-COMMIT)
    (asserts! (is-none existing) ERR-COMMIT-EXISTS)
    (asserts! (>= (var-get house-bond) (compute-payout amount)) ERR-INSUFFICIENT-BOND)

    (try! (contract-call? token transfer
            amount tx-sender (as-contract tx-sender) none))

    (map-set round-bet round
      {
        player: tx-sender,
        side: side,
        amount: amount,
        bet-block: stacks-block-height,
        settled: false
      })
    (ok round)))

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
    (asserts! (> stacks-block-height bet-block) ERR-TOO-EARLY)

    (let
      (
        (block-hash (unwrap! (get-stacks-block-info? id-header-hash bet-block)
                             ERR-NO-BLOCK-HASH))
        (digest (sha256 (concat secret block-hash)))
        (digest-hi (unwrap-panic (slice? digest u0 u16)))
        (outcome (mod (buff-to-uint-be digest-hi) u2))
        (player-won (is-eq side outcome))
        (payout (compute-payout amount))
      )
      (map-set round-secret round secret)
      (map-set round-bet round (merge bet {settled: true}))

      (if player-won
        (begin
          (var-set house-bond (- (var-get house-bond) (- payout amount)))
          (map-set balances player (+ (get-balance player) payout)))
        (let
          (
            (fee (/ (* amount (var-get house-fee-bps)) u10000))
            (to-bond (- amount fee))
            (owner (var-get contract-owner))
          )
          (var-set house-bond (+ (var-get house-bond) to-bond))
          (map-set balances owner (+ (get-balance owner) fee))))

      (ok {round: round, outcome: outcome, player-won: player-won, payout: payout}))))

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
      (ok refund-total))))

(define-public (withdraw (token <ft-trait>))
  (let ((caller tx-sender) (bal (get-balance caller)))
    (try! (assert-token token))
    (asserts! (> bal u0) ERR-NOTHING-TO-CLAIM)
    (map-set balances caller u0)
    (try! (as-contract (contract-call? token transfer bal tx-sender caller none)))
    (ok bal)))

(define-public (withdraw-house-fees (token <ft-trait>))
  (let ((owner (var-get contract-owner)) (bal (get-balance owner)))
    (try! (assert-owner))
    (try! (assert-token token))
    (asserts! (> bal u0) ERR-NOTHING-TO-CLAIM)
    (map-set balances owner u0)
    (try! (as-contract (contract-call? token transfer bal tx-sender owner none)))
    (ok bal)))
