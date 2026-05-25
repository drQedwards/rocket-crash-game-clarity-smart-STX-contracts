# Randomness reference

Stacks contracts are deterministic. Public chain values such as `block-height`,
`burn-block-height`, `tx-sender`, and transaction ordering are not safe randomness
for real-money wagers because participants, miners, or searchers can simulate or
influence outcomes.

## Recommended patterns

### Two-party commit/reveal

Use this when you want a fully on-chain settlement flow without an oracle.

1. House/operator commits to `sha256(house-seed)` before accepting wagers.
2. Player commits to `sha256(player-seed + round metadata)` when wagering.
3. Player reveals `player-seed`.
4. House reveals `house-seed`.
5. Contract verifies both commitments and derives the result from both seeds.
6. Timeout paths refund users if either side stops participating.

Tradeoffs:

- More transactions.
- Requires careful timeout and refund design.
- The house can grief by refusing to reveal unless a penalty/bond exists.

### Signed-result VRF/oracle

Use this when an external service produces verifiable random results.

1. Contract records the wager and immutable round metadata.
2. Oracle signs `sha256(round metadata + randomness)`.
3. Contract verifies the signature and computes the result.

Tradeoffs:

- Lower user friction.
- Requires a trusted/audited signer or true VRF system.
- Key rotation, monitoring, and incident response must be documented.

## Forbidden shortcuts

Do not use these as sole entropy sources for money games:

- `block-height`
- `burn-block-height`
- transaction id
- `tx-sender`
- mempool ordering
- "random" values from an unauthenticated backend response

These can be acceptable only as additional domain separators mixed with committed or
VRF-provided entropy.
