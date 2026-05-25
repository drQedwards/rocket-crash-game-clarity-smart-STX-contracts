;; fair-flip-commit-reveal.clar
;; Two-party commitment model for 50/50 outcomes.

(define-constant ERR-NOT-OWNER (err u100))
(define-constant ERR-PAUSED (err u101))
(define-constant ERR-NO-HOUSE-COMMITMENT (err u102))
(define-constant ERR-ROUND-NOT-FOUND (err u103))
(define-constant ERR-NOT-PLAYER (err u104))
(define-constant ERR-ROUND-ALREADY-SETTLED (err u105))
(define-constant ERR-INVALID-GUESS (err u106))
(define-constant ERR-BAD-PLAYER-REVEAL (err u107))
(define-constant ERR-HOUSE-SECRET-MISSING (err u108))
(define-constant ERR-STALE-ROUND (err u109))

(define-data-var owner principal 'SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8)
(define-data-var paused bool false)
(define-data-var next-round-id uint u0)
(define-data-var house-fee-bps uint u200)
(define-data-var reveal-timeout uint u144)
(define-data-var active-house-commitment (optional (buff 32)) none)

(define-map revealed-house-secrets
  {commitment: (buff 32)}
  {secret: (buff 32), revealed-at: uint})

(define-map rounds
  {round-id: uint}
  {
    player: principal,
    amount: uint,
    guess: uint,
    player-commitment: (buff 32),
    house-commitment: (buff 32),
    created-at: uint,
    settled: bool
  })

(define-private (is-owner (p principal))
  (is-eq p (var-get owner)))

(define-read-only (get-owner)
  (ok (var-get owner)))

(define-public (set-owner (new-owner principal))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (var-set owner new-owner)
    (ok true)))

(define-public (set-paused (state bool))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (var-set paused state)
    (ok state)))

(define-public (set-house-fee-bps (new-fee uint))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (asserts! (<= new-fee u1000) (err u110))
    (var-set house-fee-bps new-fee)
    (ok new-fee)))

(define-public (set-active-house-commitment (commitment (buff 32)))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (var-set active-house-commitment (some commitment))
    (ok commitment)))

(define-public (reveal-house-secret (secret (buff 32)))
  (let ((active (unwrap! (var-get active-house-commitment) ERR-NO-HOUSE-COMMITMENT)))
    (begin
      (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
      (asserts! (is-eq (sha256 secret) active) (err u111))
      (map-set revealed-house-secrets {commitment: active} {secret: secret, revealed-at: block-height})
      (var-set active-house-commitment none)
      (ok true))))

(define-public (deposit-bankroll (amount uint))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (ok amount)))

(define-public (withdraw-bankroll (amount uint) (recipient principal))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (try! (stx-transfer? amount (as-contract tx-sender) recipient))
    (ok amount)))

(define-public (start-round (guess uint) (amount uint) (player-commitment (buff 32)))
  (let ((house-commitment (unwrap! (var-get active-house-commitment) ERR-NO-HOUSE-COMMITMENT))
        (round-id (+ (var-get next-round-id) u1)))
    (begin
      (asserts! (not (var-get paused)) ERR-PAUSED)
      (asserts! (> amount u0) (err u112))
      (asserts! (or (is-eq guess u0) (is-eq guess u1)) ERR-INVALID-GUESS)
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (map-set rounds {round-id: round-id}
        {
          player: tx-sender,
          amount: amount,
          guess: guess,
          player-commitment: player-commitment,
          house-commitment: house-commitment,
          created-at: block-height,
          settled: false
        })
      (var-set next-round-id round-id)
      (ok round-id))))

(define-public (settle-round (round-id uint) (salt (buff 32)))
  (let ((round (unwrap! (map-get? rounds {round-id: round-id}) ERR-ROUND-NOT-FOUND)))
    (begin
      (asserts! (not (var-get paused)) ERR-PAUSED)
      (asserts! (is-eq tx-sender (get player round)) ERR-NOT-PLAYER)
      (asserts! (not (get settled round)) ERR-ROUND-ALREADY-SETTLED)
      (asserts! (<= block-height (+ (get created-at round) (var-get reveal-timeout))) ERR-STALE-ROUND)
      (asserts!
        (is-eq (sha256 (concat (unwrap-panic (to-consensus-buff? (get guess round))) salt)) (get player-commitment round))
        ERR-BAD-PLAYER-REVEAL)
      (let ((house-secret-row (unwrap! (map-get? revealed-house-secrets {commitment: (get house-commitment round)}) ERR-HOUSE-SECRET-MISSING))
            (gross-payout (* (get amount round) u2))
            (fee (/ (* (get amount round) (var-get house-fee-bps)) u10000))
            (entropy (sha256 (concat salt (get secret house-secret-row))))
            (outcome (mod (unwrap-panic (element-at? entropy u0)) u2)))
        (begin
          (if (is-eq outcome (get guess round))
            (try! (stx-transfer? (- gross-payout fee) (as-contract tx-sender) tx-sender))
            true)
          (map-set rounds {round-id: round-id}
            {
              player: (get player round),
              amount: (get amount round),
              guess: (get guess round),
              player-commitment: (get player-commitment round),
              house-commitment: (get house-commitment round),
              created-at: (get created-at round),
              settled: true
            })
          (ok outcome))))))

(define-public (refund-expired-round (round-id uint))
  (let ((round (unwrap! (map-get? rounds {round-id: round-id}) ERR-ROUND-NOT-FOUND)))
    (begin
      (asserts! (is-eq tx-sender (get player round)) ERR-NOT-PLAYER)
      (asserts! (not (get settled round)) ERR-ROUND-ALREADY-SETTLED)
      (asserts! (> block-height (+ (get created-at round) (var-get reveal-timeout))) ERR-STALE-ROUND)
      (try! (stx-transfer? (get amount round) (as-contract tx-sender) tx-sender))
      (map-set rounds {round-id: round-id}
        {
          player: (get player round),
          amount: (get amount round),
          guess: (get guess round),
          player-commitment: (get player-commitment round),
          house-commitment: (get house-commitment round),
          created-at: (get created-at round),
          settled: true
        })
      (ok true))))

(define-read-only (get-round (round-id uint))
  (ok (map-get? rounds {round-id: round-id})))
