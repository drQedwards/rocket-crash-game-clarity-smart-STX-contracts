# Randomness on Stacks: what is and isn't safe for wagering

## tl;dr

| Source                                           | Safe for wagering? | Why                                                                                       |
| ------------------------------------------------ | :-----------------: | ----------------------------------------------------------------------------------------- |
| `block-height`                                   | No                  | Deprecated; trivially predictable.                                                        |
| `stacks-block-height`                            | No                  | Predictable at tx-construction time.                                                      |
| `burn-block-height`                              | No                  | Same as above; Bitcoin block heights are public.                                          |
| `(get-stacks-block-info? id-header-hash N)` for **future** N | No        | Returns `none` until N is finalised; you can't actually use it for the current block.     |
| `(get-stacks-block-info? id-header-hash N)` for **past** N   | Partial   | A miner can choose which forks to release; with a 2-block delay it's reasonably hard to manipulate, but still requires combining with a private secret. |
| `tx-sender`                                      | No                  | Public.                                                                                   |
| `vrf-seed` block info                            | Partial             | Stacks-VRF seed is leaked AFTER the block is mined; a miner sees it before publishing.    |
| **Commit-reveal** (player or house secret)       | **Yes**             | The committer cannot change their secret post-commit; combined with a future block hash it's unmanipulable by either party. |
| **Operator-signed RNG** (secp256k1)              | Yes-ish             | Provided the operator uses RFC-6979 deterministic ECDSA. Otherwise the operator can grind the nonce. |

## Why `block-height` alone is broken

Suppose your contract does:

```clarity
(define-public (flip)
  (let ((side (mod (* (+ block-height u7) (* tx-sender ...)) u2)))
    ...))
```

Anyone can:

1. Read `block-height` from a Hiro API call before broadcasting.
2. Simulate the result locally — it's just `mod` arithmetic.
3. Only broadcast the bet when the simulation says they win.

Even worse: a miner can reorder transactions in their block, picking the order that maximises their personal payout. Stacks' tenure model lets the same miner mine many blocks in a row (Nakamoto), making this attack cheaper than under Stacks 2.0.

The fix is **never let any single party know the random input before the bet is locked**.

## Commit-reveal pattern (used in `fair-flip-commit-reveal.clar`)

```
Operator                     Contract                    Player
========                     ========                    ======
generate `secret` (256 bits)
publish sha256(secret)  ───▶ store as round-commit
                                                         place-bet(side, amount) ◀───
                             record bet, lock bet-block
                                                         (waits ≥ 1 block)
publish `secret`        ───▶ verify sha256(secret) == round-commit
                             read block-id-hash(bet-block)  ← public, finalised
                             outcome = LSB(sha256(secret || block-hash))
```

Why this is fair:

- **Operator can't bias:** at commit time, they don't know which `bet-block` the player will land in, so they can't pick a `secret` that produces a favourable outcome.
- **Player can't bias:** they don't know `secret` and the contract refuses any reveal whose hash doesn't match the commit.
- **Miner can't bias:** the player's bet block is finalised before the reveal tx, and the operator cannot pick a different block-id-hash.

Residual trust:

- **Liveness:** the operator must reveal on time. The contract enforces this via a `claim-refund` path that returns the stake plus a slashing penalty after `reveal-window` blocks.

## Signed-VRF pattern (used in `fair-flip-vrf.clar`)

This pattern uses Stacks' built-in `secp256k1-verify` to prove that a particular signature came from a registered operator key.

```
Operator                     Contract                       Anyone
========                     ========                       ======
register pubkey OPK     ───▶ store as vrf-pubkey
                                                            place-bet(side, amount) ◀───
                             record bet, lock bet-block
                             (waits ≥ 1 block)
                                                            settle-bet(id, signature) ◀───
sign(sha256(DOMAIN || id ||  ◀── verify secp256k1-verify(msg, sig, OPK)
     block-id-hash(bet-block)))                outcome = LSB(sha256(signature))
```

Why this is fair (with a caveat):

- The signed message includes `block-id-hash(bet-block)`, which the operator did not know at the time the bet was placed.
- ECDSA produces unique-per-message signatures **only if** the operator uses RFC-6979 deterministic nonces. If they use a non-deterministic signer they can generate many valid signatures over the same message and pick a favourable one.
- The contract cannot enforce determinism on-chain. This is the residual trust assumption — it's why this template ships with the strongest possible warning to use a deterministic signer.

If you can't accept that assumption, use the commit-reveal contract instead.

## Why we mod by 2 on the digest's high 16 bytes

Clarity's `buff-to-uint-be` accepts a `(buff <= 16)`. SHA-256 returns `(buff 32)`. We slice the high 16 bytes, interpret big-endian, and mod by 2.

A SHA-256 output is uniformly distributed over its 256-bit range. Any single bit is uniformly `0` or `1`. Taking `mod u2` of `buff-to-uint-be` of any 16 contiguous bytes still yields a uniform bit. This is fine for a binary flip.

For multi-bit outcomes (e.g. `mod u100` for a percentile), the same reasoning applies as long as the modulus is much smaller than `2^128`. The crash contract uses 32 bits (`mod 2^32` followed by a formula) which is plenty.

## Off-chain helpers for tests

To produce a valid operator signature for `fair-flip-vrf` tests:

```ts
import * as secp from "@noble/secp256k1";
import { createHash } from "node:crypto";

const DOMAIN = Buffer.from("SKFAIRFLIP", "ascii"); // matches contract constant
const operatorPriv = Buffer.from("…32 bytes…", "hex");
const operatorPub = Buffer.from(secp.getPublicKey(operatorPriv, true)); // 33 bytes

function vrfMessage(betId: bigint, blockIdHash: Buffer): Buffer {
  const idBuff = Buffer.from(
    // (to-consensus-buff? uint) prefixes 0x01 + 16 BE bytes
    Buffer.concat([Buffer.from([0x01]), bigintToBuf16BE(betId)]),
  );
  return createHash("sha256").update(Buffer.concat([DOMAIN, idBuff, blockIdHash])).digest();
}

async function signFor(betId: bigint, blockIdHash: Buffer): Promise<Buffer> {
  const msg = vrfMessage(betId, blockIdHash);
  // RFC-6979 deterministic; @noble/secp256k1 uses it by default.
  const sig = await secp.signAsync(msg, operatorPriv);
  return Buffer.from(sig.toCompactRawBytes()); // 64 bytes
}

function bigintToBuf16BE(n: bigint): Buffer {
  const b = Buffer.alloc(16);
  for (let i = 15; i >= 0; i--) {
    b[i] = Number(n & 0xffn);
    n >>= 8n;
  }
  return b;
}
```

The exact serialization that `to-consensus-buff?` uses for `uint` is the type-tag byte `0x01` followed by 16 big-endian bytes. Confirm by running `(to-consensus-buff? u1)` in `clarinet console` — it returns `0x0100000000000000000000000000000001`.
