;; SIP-010 Fungible Token Trait
;;
;; Canonical Stacks fungible-token interface.
;; Reference: https://github.com/stacksgov/sips/blob/main/sips/sip-010/sip-010-fungible-token-standard.md
;;
;; sBTC implements this trait, as do most production fungible tokens on Stacks.
;; A wagering contract that wants to accept any SIP-010 token takes a
;; <ft-trait> argument and calls (contract-call? token transfer ...).
;;
;; Deploy this trait once on testnet and once on mainnet. Other contracts
;; reference it as e.g.
;;
;;   (use-trait ft-trait .sip-010-trait.sip-010-trait)
;;   (use-trait ft-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait.sip-010-trait)

(define-trait sip-010-trait
  (
    ;; Transfer `amount` from `sender` to `recipient` with an optional memo.
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))

    ;; Human-readable name, e.g. "USD Coin".
    (get-name () (response (string-ascii 32) uint))

    ;; Token symbol, e.g. "USDC".
    (get-symbol () (response (string-ascii 32) uint))

    ;; Number of decimals.
    (get-decimals () (response uint uint))

    ;; Balance of `who`.
    (get-balance (principal) (response uint uint))

    ;; Total minted - total burned.
    (get-total-supply () (response uint uint))

    ;; Optional URI returning a metadata document. May be `(ok none)`.
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)
