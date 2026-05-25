;; Coin Flip - on-chain heads or tails game
;; Users flip a coin, track total flips, personal stats, and leaderboard rank.

(define-data-var total-flips uint u0)
(define-map user-flips principal uint)
(define-map user-last-side principal uint)

(define-data-var leader-1 {who: principal, flips: uint} {who: tx-sender, flips: u0})
(define-data-var leader-2 {who: principal, flips: uint} {who: tx-sender, flips: u0})
(define-data-var leader-3 {who: principal, flips: uint} {who: tx-sender, flips: u0})
(define-data-var leader-4 {who: principal, flips: uint} {who: tx-sender, flips: u0})
(define-data-var leader-5 {who: principal, flips: uint} {who: tx-sender, flips: u0})
(define-data-var leader-6 {who: principal, flips: uint} {who: tx-sender, flips: u0})
(define-data-var leader-7 {who: principal, flips: uint} {who: tx-sender, flips: u0})
(define-data-var leader-8 {who: principal, flips: uint} {who: tx-sender, flips: u0})
(define-data-var leader-9 {who: principal, flips: uint} {who: tx-sender, flips: u0})
(define-data-var leader-10 {who: principal, flips: uint} {who: tx-sender, flips: u0})

(define-public (flip)
  (let
    (
      (caller tx-sender)
      (current (default-to u0 (map-get? user-flips caller)))
      (new-count (+ current u1))
      (side (+ (mod (+ (* new-count u7) block-height) u2) u1))
    )
    (map-set user-flips caller new-count)
    (map-set user-last-side caller side)
    (var-set total-flips (+ (var-get total-flips) u1))
    (update-leaderboard caller new-count)
    (ok {flips: new-count, side: side})
  )
)

(define-private (update-leaderboard (who principal) (flips uint))
  (begin
    (if (>= flips (get flips (var-get leader-10)))
      (begin
        (var-set leader-10 {who: who, flips: flips})
        (bubble-up-9)
      )
      true
    )
    true
  )
)

(define-private (bubble-up-9)
  (if (>= (get flips (var-get leader-10)) (get flips (var-get leader-9)))
    (let ((tmp (var-get leader-9)))
      (var-set leader-9 (var-get leader-10))
      (var-set leader-10 tmp)
      (bubble-up-8)
    )
    true
  )
)

(define-private (bubble-up-8)
  (if (>= (get flips (var-get leader-9)) (get flips (var-get leader-8)))
    (let ((tmp (var-get leader-8)))
      (var-set leader-8 (var-get leader-9))
      (var-set leader-9 tmp)
      (bubble-up-7)
    )
    true
  )
)

(define-private (bubble-up-7)
  (if (>= (get flips (var-get leader-8)) (get flips (var-get leader-7)))
    (let ((tmp (var-get leader-7)))
      (var-set leader-7 (var-get leader-8))
      (var-set leader-8 tmp)
      (bubble-up-6)
    )
    true
  )
)

(define-private (bubble-up-6)
  (if (>= (get flips (var-get leader-7)) (get flips (var-get leader-6)))
    (let ((tmp (var-get leader-6)))
      (var-set leader-6 (var-get leader-7))
      (var-set leader-7 tmp)
      (bubble-up-5)
    )
    true
  )
)

(define-private (bubble-up-5)
  (if (>= (get flips (var-get leader-6)) (get flips (var-get leader-5)))
    (let ((tmp (var-get leader-5)))
      (var-set leader-5 (var-get leader-6))
      (var-set leader-6 tmp)
      (bubble-up-4)
    )
    true
  )
)

(define-private (bubble-up-4)
  (if (>= (get flips (var-get leader-5)) (get flips (var-get leader-4)))
    (let ((tmp (var-get leader-4)))
      (var-set leader-4 (var-get leader-5))
      (var-set leader-5 tmp)
      (bubble-up-3)
    )
    true
  )
)

(define-private (bubble-up-3)
  (if (>= (get flips (var-get leader-4)) (get flips (var-get leader-3)))
    (let ((tmp (var-get leader-3)))
      (var-set leader-3 (var-get leader-4))
      (var-set leader-4 tmp)
      (bubble-up-2)
    )
    true
  )
)

(define-private (bubble-up-2)
  (if (>= (get flips (var-get leader-3)) (get flips (var-get leader-2)))
    (let ((tmp (var-get leader-2)))
      (var-set leader-2 (var-get leader-3))
      (var-set leader-3 tmp)
      (bubble-up-1)
    )
    true
  )
)

(define-private (bubble-up-1)
  (if (>= (get flips (var-get leader-2)) (get flips (var-get leader-1)))
    (let ((tmp (var-get leader-1)))
      (var-set leader-1 (var-get leader-2))
      (var-set leader-2 tmp)
      true
    )
    true
  )
)

(define-read-only (get-total-flips)
  (var-get total-flips)
)

(define-read-only (get-user-flips (user principal))
  (default-to u0 (map-get? user-flips user))
)

(define-read-only (get-user-last-side (user principal))
  (default-to u0 (map-get? user-last-side user))
)

(define-read-only (get-leaderboard)
  (list
    (var-get leader-1)
    (var-get leader-2)
    (var-get leader-3)
    (var-get leader-4)
    (var-get leader-5)
    (var-get leader-6)
    (var-get leader-7)
    (var-get leader-8)
    (var-get leader-9)
    (var-get leader-10)
  )
)
