# Using SIP-010 Tokens for Wagers

## Overview

SIP-010 is the Stacks standard for fungible tokens (like ERC-20 on Ethereum). By accepting a SIP-010 trait parameter, your contract can work with any compliant token — including sBTC, ALEX, and custom tokens.

## The SIP-010 Trait

```clarity
(define-trait sip-010-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)
```

## Using in Your Contract

```clarity
;; Import the trait
(use-trait sip010-token .sip-010-trait.sip-010-trait)

;; Accept any SIP-010 token as a parameter
(define-public (deposit (amount uint) (token <sip010-token>))
  (begin
    (unwrap! (contract-call? token transfer
      amount tx-sender (as-contract tx-sender) none)
      (err u1))
    (ok true)
  )
)
```

## sBTC on Stacks

sBTC is a SIP-010 token on Stacks mainnet backed 1:1 by BTC. Contract address:

```
SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sbtc-token
```

To use sBTC in your wager contract:
1. Deploy the `sip-010-trait` contract
2. Use `fair-flip-sip010.clar` (or adapt any contract to accept `<sip010-token>`)
3. Players pass the sBTC contract reference when calling `commit` / `reveal` / `withdraw`

## Decimal Handling

Different tokens have different decimal places:
- **STX**: 6 decimals (1 STX = 1,000,000 microSTX)
- **sBTC**: 8 decimals (1 sBTC = 100,000,000 satoshis)
- **Custom tokens**: Check `get-decimals`

Your min/max bet limits should account for the token's decimals. The `min-bet` and `max-bet` data vars in the contract templates are set in the token's smallest unit.

## Security Considerations

1. **Token validation**: The SIP-010 trait ensures the passed contract implements the required interface, but does not guarantee the token is legitimate. Consider maintaining an allowlist of approved tokens.

2. **Reentrancy**: Clarity is not susceptible to reentrancy attacks (no re-entrant calls in the same transaction), but be careful with `as-contract` patterns.

3. **Balance tracking**: The contract tracks balances internally via `player-balances` map. This is the withdrawal pattern — players call `withdraw` to pull their tokens, rather than the contract pushing tokens.
