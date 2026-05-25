;; SIP-010 Fungible Token Trait
;; Standard interface for fungible tokens on Stacks.
;; Reference: https://github.com/stacksgov/sips/blob/main/sips/sip-010/sip-010-fungible-token-standard.md

(define-trait sip-010-trait
  (
    ;; Transfer tokens from sender to recipient
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))

    ;; Get the human-readable name
    (get-name () (response (string-ascii 32) uint))

    ;; Get the ticker symbol
    (get-symbol () (response (string-ascii 32) uint))

    ;; Get the number of decimal places
    (get-decimals () (response uint uint))

    ;; Get the balance of a principal
    (get-balance (principal) (response uint uint))

    ;; Get the total supply
    (get-total-supply () (response uint uint))

    ;; Get the URI for token metadata
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)
