;; fair-flip-sip010.clar
;; Token-based coin flip with signed-result settlement.

(use-trait ft-trait .sip010-trait.sip-010-trait)

(define-constant ERR-NOT-OWNER (err u300))
(define-constant ERR-PAUSED (err u301))
(define-constant ERR-ROUND-NOT-FOUND (err u302))
(define-constant ERR-ROUND-ALREADY-SETTLED (err u303))
(define-constant ERR-INVALID-GUESS (err u304))
(define-constant ERR-UNEXPECTED-TOKEN (err u305))
(define-constant ERR-BAD-SIGNATURE (err u306))

(define-data-var owner principal 'SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8)
(define-data-var operator-pubkey (buff 33) 0x020000000000000000000000000000000000000000000000000000000000000001)
(define-data-var paused bool false)
(define-data-var next-round-id uint u0)
(define-data-var house-fee-bps uint u200)

(define-map rounds
  {round-id: uint}
  {
    player: principal,
    amount: uint,
    guess: uint,
    token-contract: principal,
    settled: bool,
    outcome: uint
  })

(define-private (is-owner (p principal))
  (is-eq p (var-get owner)))

(define-private (round-message (round-id uint) (entropy (buff 32)))
  (sha256 (concat (unwrap-panic (to-consensus-buff? round-id)) entropy)))

(define-public (set-owner (new-owner principal))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (var-set owner new-owner)
    (ok new-owner)))

(define-public (set-operator-pubkey (new-pubkey (buff 33)))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (var-set operator-pubkey new-pubkey)
    (ok true)))

(define-public (set-paused (state bool))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (var-set paused state)
    (ok state)))

(define-public (start-round (token <ft-trait>) (guess uint) (amount uint))
  (let ((round-id (+ (var-get next-round-id) u1)))
    (begin
      (asserts! (not (var-get paused)) ERR-PAUSED)
      (asserts! (> amount u0) (err u307))
      (asserts! (or (is-eq guess u0) (is-eq guess u1)) ERR-INVALID-GUESS)
      (try! (contract-call? token transfer amount tx-sender (as-contract tx-sender) none))
      (map-set rounds {round-id: round-id}
        {
          player: tx-sender,
          amount: amount,
          guess: guess,
          token-contract: (contract-of token),
          settled: false,
          outcome: u0
        })
      (var-set next-round-id round-id)
      (ok round-id))))

(define-public (settle-round (token <ft-trait>) (round-id uint) (entropy (buff 32)) (signature (buff 65)))
  (let ((round (unwrap! (map-get? rounds {round-id: round-id}) ERR-ROUND-NOT-FOUND))
        (outcome (mod (unwrap-panic (element-at? entropy u0)) u2)))
    (begin
      (asserts! (not (var-get paused)) ERR-PAUSED)
      (asserts! (not (get settled round)) ERR-ROUND-ALREADY-SETTLED)
      (asserts! (is-eq (contract-of token) (get token-contract round)) ERR-UNEXPECTED-TOKEN)
      (asserts! (secp256k1-verify (round-message round-id entropy) signature (var-get operator-pubkey)) ERR-BAD-SIGNATURE)
      (if (is-eq outcome (get guess round))
        (let ((gross (* (get amount round) u2))
              (fee (/ (* (get amount round) (var-get house-fee-bps)) u10000)))
          (try! (contract-call? token transfer (- gross fee) (as-contract tx-sender) (get player round) none)))
        true)
      (map-set rounds {round-id: round-id}
        {
          player: (get player round),
          amount: (get amount round),
          guess: (get guess round),
          token-contract: (get token-contract round),
          settled: true,
          outcome: outcome
        })
      (ok outcome))))

(define-read-only (get-round (round-id uint))
  (ok (map-get? rounds {round-id: round-id})))
