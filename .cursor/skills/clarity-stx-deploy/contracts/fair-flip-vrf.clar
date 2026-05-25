;; Fair Flip -- Signed VRF Variant
;;
;; Off-chain operator commits a VRF seed per round. Players join the round
;; by calling (place-bet). Operator reveals the seed; contract verifies
;; the signature via secp256k1-verify and derives outcome.
;;
;; Flow:
;;   1. Operator calls (open-round seed-hash) -- commits hash of seed
;;   2. Players call (place-bet round-id side bet-amount) -- locks STX
;;   3. Operator calls (resolve-round round-id seed signature) -- reveals seed,
;;      contract verifies signature matches operator pubkey and hash matches commit,
;;      then derives outcome and credits winner balances

;; ------- Error codes -------
(define-constant ERR-NOT-OWNER (err u100))
(define-constant ERR-NOT-OPERATOR (err u101))
(define-constant ERR-PAUSED (err u102))
(define-constant ERR-ROUND-EXISTS (err u103))
(define-constant ERR-NO-ROUND (err u104))
(define-constant ERR-ROUND-NOT-OPEN (err u105))
(define-constant ERR-ROUND-NOT-COMMITTED (err u106))
(define-constant ERR-ALREADY-BET (err u107))
(define-constant ERR-INVALID-SIDE (err u108))
(define-constant ERR-BELOW-MIN-BET (err u109))
(define-constant ERR-ABOVE-MAX-BET (err u110))
(define-constant ERR-HASH-MISMATCH (err u111))
(define-constant ERR-SIG-VERIFY-FAILED (err u112))
(define-constant ERR-NOTHING-TO-WITHDRAW (err u113))
(define-constant ERR-TRANSFER-FAILED (err u114))
(define-constant ERR-FEE-TOO-HIGH (err u115))

;; ------- Constants -------
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-FEE-BPS u1000)

;; ------- Data vars -------
(define-data-var paused bool false)
(define-data-var operator-pubkey (buff 33) 0x000000000000000000000000000000000000000000000000000000000000000000)
(define-data-var min-bet uint u1000000)
(define-data-var max-bet uint u100000000000)
(define-data-var fee-bps uint u200)
(define-data-var house-balance uint u0)
(define-data-var round-counter uint u0)

;; ------- Round states -------
;; status: u1 = open (accepting bets), u2 = resolved
(define-map rounds
  uint
  {
    seed-hash: (buff 32),
    status: uint,
    outcome: uint,
    open-block: uint
  }
)

(define-map round-bets
  { round-id: uint, player: principal }
  { side: uint, bet-amount: uint }
)

(define-map player-balances principal uint)

;; ------- Read-only -------
(define-read-only (get-round (round-id uint))
  (map-get? rounds round-id)
)

(define-read-only (get-bet (round-id uint) (player principal))
  (map-get? round-bets { round-id: round-id, player: player })
)

(define-read-only (get-balance-of (player principal))
  (default-to u0 (map-get? player-balances player))
)

(define-read-only (get-config)
  (ok {
    paused: (var-get paused),
    min-bet: (var-get min-bet),
    max-bet: (var-get max-bet),
    fee-bps: (var-get fee-bps),
    house-balance: (var-get house-balance),
    round-counter: (var-get round-counter),
    operator-pubkey: (var-get operator-pubkey)
  })
)

;; ------- Operator: open a round -------
(define-public (open-round (seed-hash (buff 32)))
  (let ((rid (+ (var-get round-counter) u1)))
    (asserts! (not (var-get paused)) ERR-PAUSED)
    (asserts! (is-none (map-get? rounds rid)) ERR-ROUND-EXISTS)

    (var-set round-counter rid)
    (map-set rounds rid {
      seed-hash: seed-hash,
      status: u1,
      outcome: u0,
      open-block: block-height
    })
    (ok rid)
  )
)

;; ------- Player: place a bet -------
(define-public (place-bet (round-id uint) (side uint) (bet-amount uint))
  (let ((round-data (unwrap! (map-get? rounds round-id) ERR-NO-ROUND)))
    (asserts! (not (var-get paused)) ERR-PAUSED)
    (asserts! (is-eq (get status round-data) u1) ERR-ROUND-NOT-OPEN)
    (asserts! (or (is-eq side u1) (is-eq side u2)) ERR-INVALID-SIDE)
    (asserts! (>= bet-amount (var-get min-bet)) ERR-BELOW-MIN-BET)
    (asserts! (<= bet-amount (var-get max-bet)) ERR-ABOVE-MAX-BET)
    (asserts! (is-none (map-get? round-bets { round-id: round-id, player: tx-sender })) ERR-ALREADY-BET)

    (try! (stx-transfer? bet-amount tx-sender (as-contract tx-sender)))

    (map-set round-bets
      { round-id: round-id, player: tx-sender }
      { side: side, bet-amount: bet-amount }
    )
    (ok true)
  )
)

;; ------- Operator: resolve round -------
;; seed must hash to the committed seed-hash
;; signature is operator's secp256k1 signature over sha256(seed)
(define-public (resolve-round (round-id uint) (seed (buff 32)) (signature (buff 65)))
  (let (
    (round-data (unwrap! (map-get? rounds round-id) ERR-NO-ROUND))
    (expected-hash (get seed-hash round-data))
    (actual-hash (sha256 seed))
  )
    (asserts! (is-eq (get status round-data) u1) ERR-ROUND-NOT-OPEN)
    (asserts! (is-eq actual-hash expected-hash) ERR-HASH-MISMATCH)

    ;; Verify operator signature
    (let ((msg-hash (sha256 seed)))
      (asserts! (secp256k1-verify msg-hash signature (var-get operator-pubkey)) ERR-SIG-VERIFY-FAILED)

      ;; Derive outcome: take first byte of sha256(seed || round-id-bytes)
      (let (
        (round-bytes (unwrap! (to-consensus-buff? round-id) ERR-NO-ROUND))
        (entropy (sha256 (concat seed round-bytes)))
        (first-byte-list (list
          0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x09 0x0a 0x0b 0x0c 0x0d 0x0e 0x0f
          0x10 0x11 0x12 0x13 0x14 0x15 0x16 0x17 0x18 0x19 0x1a 0x1b 0x1c 0x1d 0x1e 0x1f
          0x20 0x21 0x22 0x23 0x24 0x25 0x26 0x27 0x28 0x29 0x2a 0x2b 0x2c 0x2d 0x2e 0x2f
          0x30 0x31 0x32 0x33 0x34 0x35 0x36 0x37 0x38 0x39 0x3a 0x3b 0x3c 0x3d 0x3e 0x3f
          0x40 0x41 0x42 0x43 0x44 0x45 0x46 0x47 0x48 0x49 0x4a 0x4b 0x4c 0x4d 0x4e 0x4f
          0x50 0x51 0x52 0x53 0x54 0x55 0x56 0x57 0x58 0x59 0x5a 0x5b 0x5c 0x5d 0x5e 0x5f
          0x60 0x61 0x62 0x63 0x64 0x65 0x66 0x67 0x68 0x69 0x6a 0x6b 0x6c 0x6d 0x6e 0x6f
          0x70 0x71 0x72 0x73 0x74 0x75 0x76 0x77 0x78 0x79 0x7a 0x7b 0x7c 0x7d 0x7e 0x7f
          0x80 0x81 0x82 0x83 0x84 0x85 0x86 0x87 0x88 0x89 0x8a 0x8b 0x8c 0x8d 0x8e 0x8f
          0x90 0x91 0x92 0x93 0x94 0x95 0x96 0x97 0x98 0x99 0x9a 0x9b 0x9c 0x9d 0x9e 0x9f
          0xa0 0xa1 0xa2 0xa3 0xa4 0xa5 0xa6 0xa7 0xa8 0xa9 0xaa 0xab 0xac 0xad 0xae 0xaf
          0xb0 0xb1 0xb2 0xb3 0xb4 0xb5 0xb6 0xb7 0xb8 0xb9 0xba 0xbb 0xbc 0xbd 0xbe 0xbf
          0xc0 0xc1 0xc2 0xc3 0xc4 0xc5 0xc6 0xc7 0xc8 0xc9 0xca 0xcb 0xcc 0xcd 0xce 0xcf
          0xd0 0xd1 0xd2 0xd3 0xd4 0xd5 0xd6 0xd7 0xd8 0xd9 0xda 0xdb 0xdc 0xdd 0xde 0xdf
          0xe0 0xe1 0xe2 0xe3 0xe4 0xe5 0xe6 0xe7 0xe8 0xe9 0xea 0xeb 0xec 0xed 0xee 0xef
          0xf0 0xf1 0xf2 0xf3 0xf4 0xf5 0xf6 0xf7 0xf8 0xf9 0xfa 0xfb 0xfc 0xfd 0xfe 0xff
        ))
        (first-byte (unwrap! (element-at? entropy u0) ERR-NO-ROUND))
        (byte-val (default-to u0 (index-of? first-byte-list first-byte)))
        (outcome (+ (mod byte-val u2) u1))
      )
        ;; Update round
        (map-set rounds round-id (merge round-data { status: u2, outcome: outcome }))

        (ok { round-id: round-id, outcome: outcome })
      )
    )
  )
)

;; ------- Settle a player's bet after round is resolved -------
(define-public (settle-bet (round-id uint) (player principal))
  (let (
    (round-data (unwrap! (map-get? rounds round-id) ERR-NO-ROUND))
    (bet-data (unwrap! (map-get? round-bets { round-id: round-id, player: player }) ERR-ALREADY-BET))
    (outcome (get outcome round-data))
    (won (is-eq (get side bet-data) outcome))
    (bet-amount (get bet-amount bet-data))
    (fee-amount (/ (* bet-amount (var-get fee-bps)) u10000))
    (payout (if won (- (* bet-amount u2) fee-amount) u0))
  )
    (asserts! (is-eq (get status round-data) u2) ERR-ROUND-NOT-COMMITTED)

    (if won
      (begin
        (map-set player-balances player (+ (get-balance-of player) payout))
        (var-set house-balance (+ (var-get house-balance) fee-amount))
      )
      (var-set house-balance (+ (var-get house-balance) bet-amount))
    )

    ;; Remove the bet so it can't be settled twice
    (map-delete round-bets { round-id: round-id, player: player })

    (ok { won: won, payout: payout })
  )
)

;; ------- Withdraw (pull pattern) -------
(define-public (withdraw)
  (let ((balance (get-balance-of tx-sender)))
    (asserts! (> balance u0) ERR-NOTHING-TO-WITHDRAW)
    (map-set player-balances tx-sender u0)
    (try! (as-contract (stx-transfer? balance tx-sender contract-caller)))
    (ok balance)
  )
)

;; ------- Admin -------
(define-public (set-operator-pubkey (pubkey (buff 33)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-OWNER)
    (var-set operator-pubkey pubkey)
    (ok true)
  )
)

(define-public (set-paused (new-paused bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-OWNER)
    (var-set paused new-paused)
    (ok true)
  )
)

(define-public (set-fee-bps (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-OWNER)
    (asserts! (<= new-fee MAX-FEE-BPS) ERR-FEE-TOO-HIGH)
    (var-set fee-bps new-fee)
    (ok true)
  )
)

(define-public (withdraw-house)
  (let ((balance (var-get house-balance)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-OWNER)
    (asserts! (> balance u0) ERR-NOTHING-TO-WITHDRAW)
    (var-set house-balance u0)
    (try! (as-contract (stx-transfer? balance tx-sender CONTRACT-OWNER)))
    (ok balance)
  )
)
