# Token wagers with sBTC and SIP-010

Use `contracts/fair-flip-sip010.clar` for token-based wagers. It accepts any
contract implementing `sip010-ft-trait`, which makes it suitable for sBTC or another
audited fungible token.

## Mainnet considerations

- Pin allowed token contracts in the frontend/backend or add an allowlist to the
  contract before mainnet. A fully arbitrary token parameter is flexible, but it can
  create confusing UX and unsupported asset risk.
- Confirm token decimals. sBTC and many SIP-010 tokens do not share STX's micro-STX
  unit semantics.
- Ensure the contract has enough bankroll in the same token before accepting wagers.
- Test token transfer failures, fee rounding, and insufficient-balance payout paths.

## sBTC

sBTC is represented by a SIP-010 contract on Stacks. Use the official mainnet or
testnet contract principal from Hiro/Stacks documentation for the selected network.
Do not copy an address from social media or an unverified block explorer page.

## Suggested additions before production

- Token allowlist managed by the owner or a governance process.
- Per-token minimum wager.
- Per-token max payout exposure.
- Pausable token-specific markets.
- Treasury accounting events for wagers, payouts, and fees.
