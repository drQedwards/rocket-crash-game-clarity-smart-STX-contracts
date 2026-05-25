;; fair-flip-vrf.clar
;;
;; STX coin flip with operator signed-RNG verified on-chain via secp256k1.
;;
;; FAIRNESS MODEL
;; --------------
;; The operator pre-registers a single secp256k1 public key. For every bet,
;; settlement requires a valid operator signature over a deterministic message
;; that includes a block-id-hash THE OPERATOR DID NOT KNOW WHEN THE BET WAS
;; SUBMITTED. Specifically:
;;
;;   1. Player calls `place-bet` with (side, amount). The contract records the
;;      bet and stores `bet-block = stacks-block-height` (the block the bet
;;      tx landed in).
;;
;;   2. After `bet-block + 1`, the operator (or any relayer) calls
;;      `settle-bet` with a secp256k1 signature over
;;          msg = sha256(domain-tag || bet-id || block-id-hash(bet-block))
;;      The contract:
;;         - reads `block-id-hash(bet-block)` itself (so the operator cannot
;;           lie about which block was used)
;;         - verifies the signature against the registered pubkey
;;         - derives outcome = LSB of sha256(signature)
;;
;; Because ECDSA on the secp256k1 curve produces unique-per-(key,msg) values
;; only when implemented with RFC-6979 deterministic nonces, the operator
;; SHOULD use a deterministic signer. If the operator uses a non-deterministic
;; signer they could grind the nonce until a favourable signature is produced;
;; this is the residual trust assumption for this contract. For full
;; trustlessness use `fair-flip-commit-reveal.clar` instead.
;;
;; Because settlement reads block-id-hash AFTER the bet block is finalised,
;; the operator cannot influence the input that goes into the signed message.
;; Combined with deterministic ECDSA, the outcome is unbiased.
;;
;; Anyone can call `settle-bet` once they have a valid signature, so the
;; operator can run a relayer, or post signatures in a public feed and let
;; the player settle.

(define-constant SIDE-HEADS u0)
(define-constant SIDE-TAILS u1)

;; Domain separation tag — change this if you redeploy with different rules.
(define-constant DOMAIN 0x534b46414952464c4950) ;; "SKFAIRFLIP"

(define-constant ERR-NOT-OWNER         (err u100))
(define-constant ERR-PAUSED            (err u101))
(define-constant ERR-NO-PUBKEY         (err u102))
(define-constant ERR-BAD-SIGNATURE     (err u103))
(define-constant ERR-BAD-SIDE          (err u104))
(define-constant ERR-BET-TOO-SMALL     (err u105))
(define-constant ERR-BET-TOO-LARGE     (err u106))
(define-constant ERR-NO-BET            (err u107))
(define-constant ERR-ALREADY-SETTLED   (err u108))
(define-constant ERR-TOO-EARLY         (err u109))
(define-constant ERR-NOT-EXPIRED       (err u110))
(define-constant ERR-NO-BLOCK-HASH     (err u111))
(define-constant ERR-INSUFFICIENT-BOND (err u112))
(define-constant ERR-NOTHING-TO-CLAIM  (err u113))
(define-constant ERR-NOT-PLAYER        (err u114))

(define-data-var contract-owner principal tx-sender)
(define-data-var paused bool false)
(define-data-var house-fee-bps uint u250)
(define-data-var min-bet uint u1000000)
(define-data-var max-bet uint u100000000)
(define-data-var settle-window uint u72)
(define-data-var expiry-penalty uint u1000000)
(define-data-var house-bond uint u0)

;; The operator's compressed secp256k1 public key (33 bytes).
;; Set via `set-vrf-pubkey` after deploy.
(define-data-var vrf-pubkey (buff 33) 0x000000000000000000000000000000000000000000000000000000000000000000)
(define-data-var vrf-pubkey-set bool false)

(define-data-var next-bet-id uint u0)

(define-map bets
  uint
  {
    player: principal,
    side: uint,
    amount: uint,
    bet-block: uint,
    settled: bool
  }
)

(define-map balances principal uint)

;; -----------------------------------------------------------------------------
;; Read-only
;; -----------------------------------------------------------------------------

(define-read-only (is-contract-owner (who principal))
  (is-eq who (var-get contract-owner)))

(define-read-only (get-contract-owner) (var-get contract-owner))
(define-read-only (get-paused)         (var-get paused))
(define-read-only (get-vrf-pubkey)
  (if (var-get vrf-pubkey-set) (some (var-get vrf-pubkey)) none))
(define-read-only (get-bet (id uint))  (map-get? bets id))
(define-read-only (get-balance (who principal))
  (default-to u0 (map-get? balances who)))
(define-read-only (get-house-bond) (var-get house-bond))
(define-read-only (get-next-bet-id) (var-get next-bet-id))

(define-read-only (compute-payout (amount uint))
  (let
    (
      (fee-bps (var-get house-fee-bps))
      (net-winnings (/ (* amount (- u10000 fee-bps)) u10000))
    )
    (+ amount net-winnings)))

;; Build the deterministic message the operator must sign for bet `id`.
;; Returns sha256(DOMAIN || id-as-buff || block-id-hash(bet-block)).
(define-read-only (compute-vrf-message (id uint))
  (let
    (
      (bet (unwrap! (map-get? bets id) ERR-NO-BET))
      (bet-block (get bet-block bet))
      (block-hash (unwrap! (get-stacks-block-info? id-header-hash bet-block)
                           ERR-NO-BLOCK-HASH))
      (id-buff (unwrap-panic (to-consensus-buff? id)))
    )
    (ok (sha256 (concat DOMAIN (concat id-buff block-hash))))))

;; -----------------------------------------------------------------------------
;; Admin
;; -----------------------------------------------------------------------------

(define-private (assert-owner)
  (if (is-contract-owner tx-sender) (ok true) ERR-NOT-OWNER))

(define-private (assert-not-paused)
  (if (var-get paused) ERR-PAUSED (ok true)))

(define-public (set-contract-owner (new-owner principal))
  (begin (try! (assert-owner)) (var-set contract-owner new-owner) (ok true)))

(define-public (set-paused (p bool))
  (begin (try! (assert-owner)) (var-set paused p) (ok true)))

(define-public (set-vrf-pubkey (pk (buff 33)))
  (begin
    (try! (assert-owner))
    (var-set vrf-pubkey pk)
    (var-set vrf-pubkey-set true)
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

(define-public (set-settle-window (blocks uint))
  (begin
    (try! (assert-owner))
    (asserts! (and (>= blocks u3) (<= blocks u1008)) (err u202))
    (var-set settle-window blocks)
    (ok true)))

(define-public (set-expiry-penalty (amount uint))
  (begin (try! (assert-owner)) (var-set expiry-penalty amount) (ok true)))

(define-public (fund-bond (amount uint))
  (begin
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set house-bond (+ (var-get house-bond) amount))
    (ok true)))

;; -----------------------------------------------------------------------------
;; Bet lifecycle
;; -----------------------------------------------------------------------------

(define-public (place-bet (side uint) (amount uint))
  (let ((id (var-get next-bet-id)))
    (try! (assert-not-paused))
    (asserts! (var-get vrf-pubkey-set) ERR-NO-PUBKEY)
    (asserts! (or (is-eq side SIDE-HEADS) (is-eq side SIDE-TAILS)) ERR-BAD-SIDE)
    (asserts! (>= amount (var-get min-bet)) ERR-BET-TOO-SMALL)
    (asserts! (<= amount (var-get max-bet)) ERR-BET-TOO-LARGE)
    (asserts! (>= (var-get house-bond) (compute-payout amount)) ERR-INSUFFICIENT-BOND)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set bets id
      {
        player: tx-sender,
        side: side,
        amount: amount,
        bet-block: stacks-block-height,
        settled: false
      })
    (var-set next-bet-id (+ id u1))
    (ok id)))

;; Anyone can settle a bet by providing the operator's signature.
;; signature is the 65-byte (or 64-byte) ECDSA signature over compute-vrf-message(id).
;; secp256k1-verify accepts both 64- and 65-byte signatures.
(define-public (settle-bet (id uint) (signature (buff 65)))
  (let
    (
      (bet (unwrap! (map-get? bets id) ERR-NO-BET))
      (player (get player bet))
      (side (get side bet))
      (amount (get amount bet))
      (bet-block (get bet-block bet))
    )
    (asserts! (not (get settled bet)) ERR-ALREADY-SETTLED)
    (asserts! (> stacks-block-height bet-block) ERR-TOO-EARLY)

    (let
      (
        (block-hash (unwrap! (get-stacks-block-info? id-header-hash bet-block)
                             ERR-NO-BLOCK-HASH))
        (id-buff (unwrap-panic (to-consensus-buff? id)))
        (msg (sha256 (concat DOMAIN (concat id-buff block-hash))))
        (pk (var-get vrf-pubkey))
      )
      (asserts! (secp256k1-verify msg signature pk) ERR-BAD-SIGNATURE)

      (let
        (
          (digest (sha256 signature))
          (digest-hi (unwrap-panic (slice? digest u0 u16)))
          (outcome (mod (buff-to-uint-be digest-hi) u2))
          (player-won (is-eq side outcome))
          (payout (compute-payout amount))
        )
        (map-set bets id (merge bet {settled: true}))

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

        (ok {id: id, outcome: outcome, player-won: player-won, payout: payout})))))

(define-public (claim-refund (id uint))
  (let
    (
      (bet (unwrap! (map-get? bets id) ERR-NO-BET))
      (player (get player bet))
      (amount (get amount bet))
      (bet-block (get bet-block bet))
      (deadline (+ bet-block (var-get settle-window)))
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
      (map-set bets id (merge bet {settled: true}))
      (var-set house-bond (- bond slash))
      (map-set balances player (+ (get-balance player) refund-total))
      (ok refund-total))))

(define-public (withdraw)
  (let ((caller tx-sender) (bal (get-balance caller)))
    (asserts! (> bal u0) ERR-NOTHING-TO-CLAIM)
    (map-set balances caller u0)
    (try! (as-contract (stx-transfer? bal tx-sender caller)))
    (ok bal)))

(define-public (withdraw-house-fees)
  (let ((owner (var-get contract-owner)) (bal (get-balance owner)))
    (try! (assert-owner))
    (asserts! (> bal u0) ERR-NOTHING-TO-CLAIM)
    (map-set balances owner u0)
    (try! (as-contract (stx-transfer? bal tx-sender owner)))
    (ok bal)))

(define-public (withdraw-bond (amount uint))
  (begin
    (try! (assert-owner))
    (asserts! (<= amount (var-get house-bond)) ERR-INSUFFICIENT-BOND)
    (var-set house-bond (- (var-get house-bond) amount))
    (let ((recipient (var-get contract-owner)))
      (try! (as-contract (stx-transfer? amount tx-sender recipient)))
      (ok amount))))
