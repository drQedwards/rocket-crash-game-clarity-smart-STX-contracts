;; crash-rocket.clar
;; Round-based crash game with claim-based settlement.

(define-constant ERR-NOT-OWNER (err u400))
(define-constant ERR-PAUSED (err u401))
(define-constant ERR-ROUND-NOT-OPEN (err u402))
(define-constant ERR-ROUND-NOT-LOCKED (err u403))
(define-constant ERR-ROUND-NOT-SETTLED (err u404))
(define-constant ERR-BET-NOT-FOUND (err u405))
(define-constant ERR-ALREADY-CLAIMED (err u406))
(define-constant ERR-BAD-HOUSE-REVEAL (err u407))
(define-constant ERR-TARGET-RANGE (err u408))

(define-data-var owner principal 'SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8)
(define-data-var paused bool false)
(define-data-var next-round-id uint u0)
(define-data-var house-fee-bps uint u200)

(define-map rounds
  {round-id: uint}
  {
    house-commitment: (buff 32),
    status: uint,
    crash-point-x100: uint,
    opened-at: uint,
    locked-at: uint,
    settled-at: uint
  })

(define-map bets
  {round-id: uint, player: principal}
  {
    amount: uint,
    target-x100: uint,
    claimed: bool
  })

(define-private (is-owner (p principal))
  (is-eq p (var-get owner)))

(define-public (set-owner (new-owner principal))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (var-set owner new-owner)
    (ok new-owner)))

(define-public (set-paused (state bool))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (var-set paused state)
    (ok state)))

(define-public (open-round (house-commitment (buff 32)))
  (let ((round-id (+ (var-get next-round-id) u1)))
    (begin
      (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
      (asserts! (not (var-get paused)) ERR-PAUSED)
      (map-set rounds {round-id: round-id}
        {
          house-commitment: house-commitment,
          status: u0,
          crash-point-x100: u0,
          opened-at: block-height,
          locked-at: u0,
          settled-at: u0
        })
      (var-set next-round-id round-id)
      (ok round-id))))

(define-public (place-bet (round-id uint) (amount uint) (target-x100 uint))
  (let ((round (unwrap! (map-get? rounds {round-id: round-id}) (err u409))))
    (begin
      (asserts! (not (var-get paused)) ERR-PAUSED)
      (asserts! (is-eq (get status round) u0) ERR-ROUND-NOT-OPEN)
      (asserts! (> amount u0) (err u410))
      (asserts! (and (>= target-x100 u101) (<= target-x100 u1000)) ERR-TARGET-RANGE)
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (map-set bets {round-id: round-id, player: tx-sender}
        {amount: amount, target-x100: target-x100, claimed: false})
      (ok true))))

(define-public (lock-round (round-id uint))
  (let ((round (unwrap! (map-get? rounds {round-id: round-id}) (err u411))))
    (begin
      (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
      (asserts! (is-eq (get status round) u0) ERR-ROUND-NOT-OPEN)
      (map-set rounds {round-id: round-id}
        {
          house-commitment: (get house-commitment round),
          status: u1,
          crash-point-x100: u0,
          opened-at: (get opened-at round),
          locked-at: block-height,
          settled-at: u0
        })
      (ok true))))

(define-public (settle-round (round-id uint) (house-secret (buff 32)))
  (let ((round (unwrap! (map-get? rounds {round-id: round-id}) (err u412))))
    (begin
      (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
      (asserts! (is-eq (get status round) u1) ERR-ROUND-NOT-LOCKED)
      (asserts! (is-eq (sha256 house-secret) (get house-commitment round)) ERR-BAD-HOUSE-REVEAL)
      (let ((entropy (sha256 (concat house-secret (unwrap-panic (to-consensus-buff? round-id)))))
            (crash-point (+ u101 (mod (unwrap-panic (element-at? entropy u0)) u900))))
        (begin
          (map-set rounds {round-id: round-id}
            {
              house-commitment: (get house-commitment round),
              status: u2,
              crash-point-x100: crash-point,
              opened-at: (get opened-at round),
              locked-at: (get locked-at round),
              settled-at: block-height
            })
          (ok crash-point))))))

(define-public (claim (round-id uint))
  (let ((round (unwrap! (map-get? rounds {round-id: round-id}) (err u413)))
        (bet (unwrap! (map-get? bets {round-id: round-id, player: tx-sender}) ERR-BET-NOT-FOUND)))
    (begin
      (asserts! (is-eq (get status round) u2) ERR-ROUND-NOT-SETTLED)
      (asserts! (not (get claimed bet)) ERR-ALREADY-CLAIMED)
      (if (<= (get target-x100 bet) (get crash-point-x100 round))
        (let ((gross (/ (* (get amount bet) (get target-x100 bet)) u100))
              (fee (/ (* (get amount bet) (var-get house-fee-bps)) u10000)))
          (try! (stx-transfer? (- gross fee) (as-contract tx-sender) tx-sender)))
        true)
      (map-set bets {round-id: round-id, player: tx-sender}
        {
          amount: (get amount bet),
          target-x100: (get target-x100 bet),
          claimed: true
        })
      (ok true))))

(define-read-only (get-round (round-id uint))
  (ok (map-get? rounds {round-id: round-id})))
