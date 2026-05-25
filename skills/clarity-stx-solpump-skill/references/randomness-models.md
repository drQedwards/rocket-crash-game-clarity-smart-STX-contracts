# Randomness Models for Clarity Wagering

## Commit-reveal (on-chain)
- House posts a commitment hash first.
- Player posts their commitment and wager.
- House reveals secret.
- Player reveals secret and settles.

Pros:
- No external dependency.

Tradeoffs:
- Multiple transactions.
- Requires timeout logic for stale rounds.

## Signed-result (operator signature)
- Operator signs `(round-id, entropy)`.
- Contract verifies with `secp256k1-verify`.
- Settlement happens in one call after bet placement.

Pros:
- Fewer round trips.

Tradeoffs:
- Requires secure signer operations and key rotation process.

## Disallowed anti-pattern
- Do not use raw block height or burn block fields alone as the outcome source.
