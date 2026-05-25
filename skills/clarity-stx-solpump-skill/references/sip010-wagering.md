# SIP-010 Wagering Notes

## Token compatibility
Use `sip010-trait.clar` for generic fungible-token integrations.

## Token transfer pattern
- Bet placement transfers from user -> contract.
- Payout transfers from contract -> user.
- Enforce token contract allowlist in admin controls if needed.

## sBTC
Treat sBTC as a SIP-010-compatible token where applicable and verify the deployed mainnet contract ID before activation.
