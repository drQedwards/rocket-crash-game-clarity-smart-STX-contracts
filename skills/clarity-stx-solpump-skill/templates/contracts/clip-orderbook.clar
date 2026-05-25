;; clip-orderbook.clar
;; Minimal on-chain order queue and matching state transitions.
;; Settlement can be handled by a separate escrow/vault contract.

(define-constant ERR-NOT-OWNER (err u500))
(define-constant ERR-PAUSED (err u501))
(define-constant ERR-ORDER-NOT-FOUND (err u502))
(define-constant ERR-NOT-MAKER (err u503))
(define-constant ERR-ORDER-CLOSED (err u504))
(define-constant ERR-INVALID-SIDE (err u505))
(define-constant ERR-PRICE-CROSS (err u506))
(define-constant ERR-BAD-MATCH-AMOUNT (err u507))

(define-data-var owner principal 'SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8)
(define-data-var paused bool false)
(define-data-var next-order-id uint u0)

(define-map orders
  {order-id: uint}
  {
    maker: principal,
    side: uint,
    price-sats: uint,
    amount: uint,
    remaining: uint,
    status: uint,
    created-at: uint
  })

(define-private (is-owner (p principal))
  (is-eq p (var-get owner)))

(define-private (is-open (status uint))
  (is-eq status u0))

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

(define-public (place-order (side uint) (price-sats uint) (amount uint))
  (let ((order-id (+ (var-get next-order-id) u1)))
    (begin
      (asserts! (not (var-get paused)) ERR-PAUSED)
      (asserts! (or (is-eq side u0) (is-eq side u1)) ERR-INVALID-SIDE)
      (asserts! (> price-sats u0) (err u508))
      (asserts! (> amount u0) (err u509))
      (map-set orders {order-id: order-id}
        {
          maker: tx-sender,
          side: side,
          price-sats: price-sats,
          amount: amount,
          remaining: amount,
          status: u0,
          created-at: block-height
        })
      (var-set next-order-id order-id)
      (ok order-id))))

(define-public (cancel-order (order-id uint))
  (let ((order (unwrap! (map-get? orders {order-id: order-id}) ERR-ORDER-NOT-FOUND)))
    (begin
      (asserts! (is-eq tx-sender (get maker order)) ERR-NOT-MAKER)
      (asserts! (is-open (get status order)) ERR-ORDER-CLOSED)
      (map-set orders {order-id: order-id}
        {
          maker: (get maker order),
          side: (get side order),
          price-sats: (get price-sats order),
          amount: (get amount order),
          remaining: (get remaining order),
          status: u2,
          created-at: (get created-at order)
        })
      (ok true))))

(define-public (match-orders (maker-order-id uint) (taker-order-id uint) (match-amount uint))
  (let (
      (maker-order (unwrap! (map-get? orders {order-id: maker-order-id}) ERR-ORDER-NOT-FOUND))
      (taker-order (unwrap! (map-get? orders {order-id: taker-order-id}) ERR-ORDER-NOT-FOUND))
    )
    (begin
      (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
      (asserts! (not (var-get paused)) ERR-PAUSED)
      (asserts! (is-open (get status maker-order)) ERR-ORDER-CLOSED)
      (asserts! (is-open (get status taker-order)) ERR-ORDER-CLOSED)
      (asserts! (not (is-eq (get side maker-order) (get side taker-order))) ERR-INVALID-SIDE)
      (asserts! (> match-amount u0) ERR-BAD-MATCH-AMOUNT)
      (asserts! (<= match-amount (get remaining maker-order)) ERR-BAD-MATCH-AMOUNT)
      (asserts! (<= match-amount (get remaining taker-order)) ERR-BAD-MATCH-AMOUNT)
      ;; Buy side is u0; sell side is u1.
      (asserts!
        (if (is-eq (get side maker-order) u0)
          (>= (get price-sats maker-order) (get price-sats taker-order))
          (>= (get price-sats taker-order) (get price-sats maker-order)))
        ERR-PRICE-CROSS)
      (let ((maker-new-remaining (- (get remaining maker-order) match-amount))
            (taker-new-remaining (- (get remaining taker-order) match-amount)))
        (begin
          (map-set orders {order-id: maker-order-id}
            {
              maker: (get maker maker-order),
              side: (get side maker-order),
              price-sats: (get price-sats maker-order),
              amount: (get amount maker-order),
              remaining: maker-new-remaining,
              status: (if (is-eq maker-new-remaining u0) u1 u0),
              created-at: (get created-at maker-order)
            })
          (map-set orders {order-id: taker-order-id}
            {
              maker: (get maker taker-order),
              side: (get side taker-order),
              price-sats: (get price-sats taker-order),
              amount: (get amount taker-order),
              remaining: taker-new-remaining,
              status: (if (is-eq taker-new-remaining u0) u1 u0),
              created-at: (get created-at taker-order)
            })
          (ok {maker-remaining: maker-new-remaining, taker-remaining: taker-new-remaining}))))))

(define-read-only (get-order (order-id uint))
  (ok (map-get? orders {order-id: order-id})))

(define-read-only (get-next-order-id)
  (ok (+ (var-get next-order-id) u1)))
