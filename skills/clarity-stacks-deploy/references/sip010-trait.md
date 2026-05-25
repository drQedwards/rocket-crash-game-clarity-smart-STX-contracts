# Wagering SIP-010 tokens (including sBTC)

## What SIP-010 is

[SIP-010](https://github.com/stacksgov/sips/blob/main/sips/sip-010/sip-010-fungible-token-standard.md) is the canonical fungible-token interface on Stacks. Every production token (sBTC, USDC on Stacks, ALEX, etc.) implements it. The trait is shipped in `templates/contracts/sip-010-trait.clar` exactly as defined by the SIP.

## How a contract accepts an arbitrary SIP-010 token

The pattern is:

1. The wagering contract `use-trait`s the SIP-010 trait.
2. It stores the canonical token principal in a `data-var` after deployment (set once via an owner-only setter).
3. Every public function that moves tokens takes a `<ft-trait>` parameter.
4. Before transferring, the contract asserts `(contract-of token) == stored-principal` so a caller can't pass in a malicious lookalike.

This is exactly what `templates/contracts/fair-flip-token.clar` does.

```clarity
(use-trait ft-trait .sip-010-trait.sip-010-trait)

(define-data-var token-principal (optional principal) none)

(define-private (assert-token (token <ft-trait>))
  (let ((tp (var-get token-principal)))
    (asserts! (is-some tp) ERR-NO-TOKEN)
    (asserts! (is-eq (contract-of token) (unwrap-panic tp)) ERR-WRONG-TOKEN)
    (ok true)))

(define-public (place-bet (token <ft-trait>) (side uint) (amount uint))
  (begin
    (try! (assert-token token))
    (try! (contract-call? token transfer amount tx-sender (as-contract tx-sender) none))
    ;; ...
  ))
```

## sBTC specifics

sBTC is a SIP-010 token. To wager sBTC:

1. Deploy `sip-010-trait.clar` and `fair-flip-token.clar` to your target network.
2. Call `set-token` once, passing the canonical sBTC contract:
   - mainnet: `'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token`
   - testnet: `'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token`
3. Call `fund-bond`, passing the sBTC contract again as the trait argument.
4. Players call `place-bet` with the sBTC contract as the trait argument.

**Verify the canonical addresses** against [docs.stacks.co/concepts/sbtc/contracts](https://docs.stacks.co/concepts/sbtc/contracts) before any mainnet deploy. The addresses change occasionally during sBTC upgrades.

## Decimals matter

sBTC uses 8 decimals. STX uses 6. USDC on Stacks uses 6. The contract's `min-bet` and `max-bet` are denominated in the smallest unit of whatever token is configured. **You must reset `min-bet` / `max-bet` after `set-token` so they make sense for that token's decimals.**

| Token | Decimals | "1 unit" in smallest units |
| ----- | :------: | -------------------------- |
| STX   | 6        | 1_000_000                  |
| sBTC  | 8        | 100_000_000                |
| USDC  | 6        | 1_000_000                  |

For sBTC, the default `min-bet = u10000` corresponds to 0.0001 sBTC. Adjust to taste.

## Post-conditions

When a frontend submits a `place-bet` tx that pulls tokens, it should attach a SIP-010 post-condition that the player's balance decreased by exactly `amount`. The Stacks chain rejects the tx if the post-condition fails, providing client-side protection against contract bugs that try to pull more than expected.

```ts
import {
  makeContractFungiblePostCondition,
  FungibleConditionCode,
  createAssetInfo,
} from "@stacks/transactions";

const pc = makeContractFungiblePostCondition(
  player,
  FungibleConditionCode.Equal,
  amount,
  createAssetInfo("SM3VDXK3...", "sbtc-token", "sbtc-token"),
);
```

The contract's `withdraw` function transfers in the opposite direction, so its post-condition should assert that the contract's balance decreased by `bal`.
