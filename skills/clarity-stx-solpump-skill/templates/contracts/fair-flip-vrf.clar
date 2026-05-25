;; fair-flip-vrf.clar
;; Signed-result flip settlement with secp256k1 verification.

(define-constant ERR-NOT-OWNER (err u200))
(define-constant ERR-PAUSED (err u201))
(define-constant ERR-INVALID-GUESS (err u202))
(define-constant ERR-ROUND-NOT-FOUND (err u203))
(define-constant ERR-ROUND-ALREADY-SETTLED (err u204))
(define-constant ERR-BAD-SIGNATURE (err u205))

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

(define-public (deposit-bankroll (amount uint))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (ok amount)))

(define-public (start-round (guess uint) (amount uint))
  (let ((round-id (+ (var-get next-round-id) u1)))
    (begin
      (asserts! (not (var-get paused)) ERR-PAUSED)
      (asserts! (> amount u0) (err u206))
      (asserts! (or (is-eq guess u0) (is-eq guess u1)) ERR-INVALID-GUESS)
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (map-set rounds {round-id: round-id}
        {player: tx-sender, amount: amount, guess: guess, settled: false, outcome: u0})
      (var-set next-round-id round-id)
      (ok round-id))))

(define-public (settle-round (round-id uint) (entropy (buff 32)) (signature (buff 65)))
  (let ((round (unwrap! (map-get? rounds {round-id: round-id}) ERR-ROUND-NOT-FOUND))
        (outcome (mod (unwrap-panic (element-at? entropy u0)) u2)))
    (begin
      (asserts! (not (var-get paused)) ERR-PAUSED)
      (asserts! (not (get settled round)) ERR-ROUND-ALREADY-SETTLED)
      (asserts! (secp256k1-verify (round-message round-id entropy) signature (var-get operator-pubkey)) ERR-BAD-SIGNATURE)
      (if (is-eq outcome (get guess round))
        (let ((gross (* (get amount round) u2))
              (fee (/ (* (get amount round) (var-get house-fee-bps)) u10000)))
          (try! (stx-transfer? (- gross fee) (as-contract tx-sender) (get player round))))
        true)
      (map-set rounds {round-id: round-id}
        {
          player: (get player round),
          amount: (get amount round),
          guess: (get guess round),
          settled: true,
          outcome: outcome
        })
      (ok outcome))))

(define-read-only (get-round (round-id uint))
  (ok (map-get? rounds {round-id: round-id})))
