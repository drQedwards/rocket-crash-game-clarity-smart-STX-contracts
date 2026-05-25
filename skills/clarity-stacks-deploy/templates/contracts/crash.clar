;; crash.clar
;;
;; Multi-player provably-fair "crash" game on STX, settled via house
;; commit-reveal. Each player picks a target multiplier when they bet; if the
;; round's crash multiplier exceeds their target, they win
;; `target * amount / 100`. Otherwise they lose their stake.
;;
;; This eliminates the real-time cash-out UX (which can't exist on-chain)
;; and reduces the game to a one-tx-per-bet, one-tx-per-settle pattern.
;;
;; ROUND LIFECYCLE
;; ---------------
;; State machine per round:
;;
;;   READY ──commit-round──▶ OPEN ──close-round──▶ LOCKED ──reveal-round──▶ SETTLED
;;     ▲                                                                       │
;;     └───────────────────────────────────────────────────────────────────────┘
;;
;;   READY     no active round
;;   OPEN      players may place bets, operator's commit is locked
;;   LOCKED    no new bets, awaiting reveal
;;   SETTLED   crash multiplier known, players may individually settle their
;;             bets via `settle-bet`
;;
;; Operator MUST close the round at the same height for a given commit
;; before revealing — `close-round` records the close-block, whose
;; block-id-hash becomes a public, unmanipulable input to the crash multiplier.
;;
;; CRASH FORMULA (1% house edge, payout distribution ~ 1/X for X ≥ 1)
;; ------------------------------------------------------------------
;;   H = first 4 bytes of sha256(secret || close-block-id-hash) as uint32 BE
;;   E = 2^32 = 4294967296
;;   if H == 0:        crash = MAX_MULT (cap)
;;   else:             crash_bp = (E * 9900) / (E - H), in "basis points"
;;
;; Multipliers throughout the contract are expressed in basis points: 100 = 1.00x,
;; 200 = 2.00x, 10000 = 100.00x. Targets must be in [101, MAX_MULT].

(define-constant ERR-NOT-OWNER         (err u100))
(define-constant ERR-PAUSED            (err u101))
(define-constant ERR-NO-COMMIT         (err u102))
(define-constant ERR-COMMIT-EXISTS     (err u103))
(define-constant ERR-BAD-SECRET        (err u104))
(define-constant ERR-BAD-TARGET        (err u105))
(define-constant ERR-BET-TOO-SMALL     (err u106))
(define-constant ERR-BET-TOO-LARGE     (err u107))
(define-constant ERR-NO-BET            (err u108))
(define-constant ERR-ALREADY-SETTLED   (err u109))
(define-constant ERR-NOT-OPEN          (err u110))
(define-constant ERR-NOT-LOCKED        (err u111))
(define-constant ERR-NOT-SETTLED       (err u112))
(define-constant ERR-TOO-EARLY         (err u113))
(define-constant ERR-NOT-EXPIRED       (err u114))
(define-constant ERR-NO-BLOCK-HASH     (err u115))
(define-constant ERR-INSUFFICIENT-BOND (err u116))
(define-constant ERR-NOTHING-TO-CLAIM  (err u117))
(define-constant ERR-NOT-PLAYER        (err u118))
(define-constant ERR-DUPLICATE-BET     (err u119))

;; Round states
(define-constant STATE-OPEN     u1)
(define-constant STATE-LOCKED   u2)
(define-constant STATE-SETTLED  u3)

;; Multiplier scaling — basis points. 1.00x = u100, 100.00x = u10000.
(define-constant MULT-SCALE u100)
(define-constant MIN-TARGET u101)   ;; 1.01x
(define-constant MAX-MULT   u10000) ;; 100x cap; payouts above this clip

(define-data-var contract-owner principal tx-sender)
(define-data-var paused bool false)

(define-data-var house-fee-bps uint u100) ;; 1% additional house edge on top of formula

(define-data-var min-bet uint u1000000)
(define-data-var max-bet uint u100000000)

(define-data-var reveal-window uint u72)
(define-data-var expiry-penalty uint u1000000)
(define-data-var house-bond uint u0)

(define-data-var current-round uint u0)

;; Per-round state.
(define-map rounds
  uint
  {
    state: uint,
    commit: (buff 32),
    secret: (optional (buff 32)),
    open-block: uint,
    close-block: (optional uint),
    crash-bp: (optional uint),
    total-exposure: uint  ;; sum of (potential payout - amount) for unsettled bets
  })

;; Per-(round, player) bet. One bet per player per round.
(define-map bets
  {round: uint, player: principal}
  {
    target-bp: uint,    ;; basis points
    amount: uint,
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
(define-read-only (get-round (r uint)) (map-get? rounds r))
(define-read-only (get-bet (r uint) (p principal))
  (map-get? bets {round: r, player: p}))
(define-read-only (get-balance (who principal))
  (default-to u0 (map-get? balances who)))

;; Potential winning payout for a bet of `amount` at `target-bp` (capped).
;; payout-gross = amount * effective-target / MULT-SCALE
;; effective-target = min(target-bp, MAX-MULT) - house-fee-bps
(define-read-only (compute-payout (amount uint) (target-bp uint))
  (let
    (
      (capped (if (> target-bp MAX-MULT) MAX-MULT target-bp))
      (fee-bps (var-get house-fee-bps))
      (eff (if (> capped fee-bps) (- capped fee-bps) u0))
    )
    (/ (* amount eff) MULT-SCALE)))

;; -----------------------------------------------------------------------------
;; Helpers
;; -----------------------------------------------------------------------------

(define-private (assert-owner)
  (if (is-contract-owner tx-sender) (ok true) ERR-NOT-OWNER))

(define-private (assert-not-paused)
  (if (var-get paused) ERR-PAUSED (ok true)))

;; Derive crash multiplier (in basis points) from secret + close-block-hash.
;; H32 = first 4 bytes of sha256(secret || block-hash)
;; E   = 2^32
;; crash_bp = (E * 9900) / (E - H32)
;; With H32 = 0, returns MAX-MULT (avoids div-by-zero, ultra-high outcome).
(define-private (compute-crash (secret (buff 32)) (close-hash (buff 32)))
  (let
    (
      (digest (sha256 (concat secret close-hash)))
      (h-buff (unwrap-panic (slice? digest u0 u4)))
      (h32 (buff-to-uint-be h-buff))
      (e u4294967296)
    )
    (if (is-eq h32 u0)
      MAX-MULT
      (let ((raw (/ (* e u9900) (- e h32))))
        (if (> raw MAX-MULT) MAX-MULT raw)))))

;; -----------------------------------------------------------------------------
;; Admin
;; -----------------------------------------------------------------------------

(define-public (set-contract-owner (new-owner principal))
  (begin (try! (assert-owner)) (var-set contract-owner new-owner) (ok true)))

(define-public (set-paused (p bool))
  (begin (try! (assert-owner)) (var-set paused p) (ok true)))

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

(define-public (fund-bond (amount uint))
  (begin
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set house-bond (+ (var-get house-bond) amount))
    (ok true)))

(define-public (withdraw-bond (amount uint))
  (begin
    (try! (assert-owner))
    (asserts! (<= amount (var-get house-bond)) ERR-INSUFFICIENT-BOND)
    (var-set house-bond (- (var-get house-bond) amount))
    (let ((recipient (var-get contract-owner)))
      (try! (as-contract (stx-transfer? amount tx-sender recipient)))
      (ok amount))))

;; -----------------------------------------------------------------------------
;; Round lifecycle
;; -----------------------------------------------------------------------------

(define-public (commit-round (commit (buff 32)))
  (let ((next-round (+ (var-get current-round) u1)))
    (try! (assert-owner))
    (try! (assert-not-paused))
    (asserts! (is-none (map-get? rounds next-round)) ERR-COMMIT-EXISTS)
    (map-set rounds next-round
      {
        state: STATE-OPEN,
        commit: commit,
        secret: none,
        open-block: stacks-block-height,
        close-block: none,
        crash-bp: none,
        total-exposure: u0
      })
    (var-set current-round next-round)
    (ok next-round)))

(define-public (place-bet (target-bp uint) (amount uint))
  (let
    (
      (round (var-get current-round))
      (round-data (unwrap! (map-get? rounds round) ERR-NO-COMMIT))
      (existing (map-get? bets {round: round, player: tx-sender}))
    )
    (try! (assert-not-paused))
    (asserts! (is-none existing) ERR-DUPLICATE-BET)
    (asserts! (is-eq (get state round-data) STATE-OPEN) ERR-NOT-OPEN)
    (asserts! (and (>= target-bp MIN-TARGET) (<= target-bp MAX-MULT)) ERR-BAD-TARGET)
    (asserts! (>= amount (var-get min-bet)) ERR-BET-TOO-SMALL)
    (asserts! (<= amount (var-get max-bet)) ERR-BET-TOO-LARGE)

    (let
      (
        (payout (compute-payout amount target-bp))
        (exposure (if (> payout amount) (- payout amount) u0))
        (new-exposure (+ (get total-exposure round-data) exposure))
      )
      (asserts! (>= (var-get house-bond) new-exposure) ERR-INSUFFICIENT-BOND)
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (map-set bets {round: round, player: tx-sender}
        {target-bp: target-bp, amount: amount, settled: false})
      (map-set rounds round (merge round-data {total-exposure: new-exposure}))
      (ok {round: round, target-bp: target-bp, amount: amount, payout: payout}))))

;; Operator closes the round, locking in close-block. The block-id-hash for
;; close-block is the public input that the crash multiplier depends on.
(define-public (close-round (round uint))
  (let ((rd (unwrap! (map-get? rounds round) ERR-NO-COMMIT)))
    (try! (assert-owner))
    (asserts! (is-eq (get state rd) STATE-OPEN) ERR-NOT-OPEN)
    (map-set rounds round (merge rd {
      state: STATE-LOCKED,
      close-block: (some stacks-block-height)
    }))
    (ok true)))

(define-public (reveal-round (round uint) (secret (buff 32)))
  (let
    (
      (rd (unwrap! (map-get? rounds round) ERR-NO-COMMIT))
      (close-block (unwrap! (get close-block rd) ERR-NOT-LOCKED))
    )
    (try! (assert-owner))
    (asserts! (is-eq (get state rd) STATE-LOCKED) ERR-NOT-LOCKED)
    (asserts! (is-eq (sha256 secret) (get commit rd)) ERR-BAD-SECRET)
    (asserts! (> stacks-block-height close-block) ERR-TOO-EARLY)

    (let
      (
        (close-hash (unwrap! (get-stacks-block-info? id-header-hash close-block)
                             ERR-NO-BLOCK-HASH))
        (crash (compute-crash secret close-hash))
      )
      (map-set rounds round (merge rd {
        state: STATE-SETTLED,
        secret: (some secret),
        crash-bp: (some crash)
      }))
      (ok crash))))

;; Anyone can settle a bet once the round is SETTLED.
(define-public (settle-bet (round uint))
  (settle-bet-for round tx-sender))

(define-public (settle-bet-for (round uint) (player principal))
  (let
    (
      (rd (unwrap! (map-get? rounds round) ERR-NO-COMMIT))
      (bet (unwrap! (map-get? bets {round: round, player: player}) ERR-NO-BET))
      (crash (unwrap! (get crash-bp rd) ERR-NOT-SETTLED))
      (target (get target-bp bet))
      (amount (get amount bet))
    )
    (asserts! (is-eq (get state rd) STATE-SETTLED) ERR-NOT-SETTLED)
    (asserts! (not (get settled bet)) ERR-ALREADY-SETTLED)

    (map-set bets {round: round, player: player} (merge bet {settled: true}))

    (if (<= target crash)
      ;; Win: pay out target * amount / 100, after fee.
      (let
        (
          (payout (compute-payout amount target))
          (exposure (if (> payout amount) (- payout amount) u0))
        )
        (var-set house-bond (- (var-get house-bond) exposure))
        (map-set rounds round (merge rd {
          total-exposure: (- (get total-exposure rd) exposure)
        }))
        (map-set balances player (+ (get-balance player) payout))
        (ok {win: true, payout: payout, crash-bp: crash}))
      ;; Loss: stake goes to bond minus a constant house fee on the loss.
      (let
        (
          (fee (/ (* amount (var-get house-fee-bps)) u10000))
          (to-bond (- amount fee))
          (owner (var-get contract-owner))
          (was-exposure (let ((p (compute-payout amount target)))
                          (if (> p amount) (- p amount) u0)))
        )
        (var-set house-bond (+ (var-get house-bond) to-bond))
        (map-set rounds round (merge rd {
          total-exposure: (- (get total-exposure rd) was-exposure)
        }))
        (map-set balances owner (+ (get-balance owner) fee))
        (ok {win: false, payout: u0, crash-bp: crash})))))

;; If the operator fails to reveal within `reveal-window` blocks of close,
;; players can refund themselves.
(define-public (claim-refund (round uint))
  (let
    (
      (rd (unwrap! (map-get? rounds round) ERR-NO-COMMIT))
      (bet (unwrap! (map-get? bets {round: round, player: tx-sender}) ERR-NO-BET))
      (close-block (unwrap! (get close-block rd) ERR-NOT-LOCKED))
      (deadline (+ close-block (var-get reveal-window)))
      (amount (get amount bet))
      (penalty (var-get expiry-penalty))
      (bond (var-get house-bond))
    )
    (asserts! (is-eq (get state rd) STATE-LOCKED) ERR-NOT-LOCKED)
    (asserts! (not (get settled bet)) ERR-ALREADY-SETTLED)
    (asserts! (> stacks-block-height deadline) ERR-NOT-EXPIRED)

    (let
      (
        (slash (if (> bond penalty) penalty bond))
        (refund-total (+ amount slash))
      )
      (map-set bets {round: round, player: tx-sender} (merge bet {settled: true}))
      (var-set house-bond (- bond slash))
      (map-set balances tx-sender (+ (get-balance tx-sender) refund-total))
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
