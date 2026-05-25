# Randomness Patterns for Clarity Contracts

## Why `block-height` is NOT Random

```clarity
;; INSECURE — DO NOT USE FOR REAL-MONEY OUTCOMES
(define-private (bad-random)
  (mod block-height u2))
```

**Problems:**
1. `block-height` is publicly known before a block is mined
2. Miners can choose which block to include your transaction in
3. Users can simulate the transaction before submitting to know the outcome
4. The existing `Flip.clarinet` in this repo uses this pattern — it must be replaced

## Pattern 1: Commit-Reveal (Fully On-Chain)

**How it works:**
1. Player computes `secret` (random 32 bytes) and `side` (1 or 2)
2. Player submits `hash = sha256(secret || side_byte)` + wager (TX 1)
3. After at least 1 block, player submits `secret` and `side` (TX 2)
4. Contract verifies `sha256(secret || side_byte) == stored_hash`
5. Outcome derived from `sha256(secret || id-header-hash-at-commit-block)`

**Why it's fair:**
- Player commits to their choice before the block hash is known
- The block hash adds entropy the player couldn't predict at commit time
- Neither party can manipulate the outcome after both inputs are locked

**Trade-offs:**
- Requires 2 transactions per game (UX friction)
- Player can refuse to reveal (mitigated by expiry + house claims unrevealed bets)
- 144-block reveal window (~24 hours)

**Reference contract:** `contracts/fair-flip-commit-reveal.clar`

## Pattern 2: Signed VRF (Off-Chain Operator)

**How it works:**
1. Operator generates a random seed, commits `sha256(seed)` to open a round
2. Players place bets during the open window
3. Operator reveals `seed` + `signature = secp256k1_sign(sha256(seed))`
4. Contract verifies: `sha256(seed) == committed_hash` AND `secp256k1-verify(msg_hash, signature, operator_pubkey)`
5. Outcome derived from `sha256(seed || round_id_bytes)`

**Why it's fair:**
- Operator commits seed hash before bets, so they can't change it after seeing bets
- Signature verification proves the revealed seed came from the registered operator
- If operator refuses to reveal, a timeout mechanism can refund all bets

**Trade-offs:**
- Requires a trusted operator (but they can only withhold, not manipulate)
- Single transaction per player (better UX than commit-reveal)
- More complex off-chain infrastructure

**Reference contract:** `contracts/fair-flip-vrf.clar`

## Pattern 3: Hybrid (Commit-Reveal + VRF)

Combine both patterns: player commits a secret, operator commits a seed. Outcome derived from both inputs. This is the strongest model but requires the most complex UX.

## Choosing a Pattern

| Factor | Commit-Reveal | Signed VRF |
|--------|--------------|------------|
| On-chain only | Yes | No (needs operator) |
| Player UX | 2 TX | 1 TX |
| Trust model | Trustless | Trusted operator |
| Manipulation risk | Player can refuse reveal | Operator can withhold |
| Mitigation | Expiry → house claims | Timeout → refund |
| Recommended for | Low-stakes / trustless games | High-volume / better UX |
