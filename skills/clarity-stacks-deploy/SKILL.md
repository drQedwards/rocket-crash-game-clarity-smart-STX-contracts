---
name: clarity-stacks-deploy
description: Scaffold, test, and deploy Clarity smart contracts to the Stacks blockchain (Hiro testnet/mainnet) using Clarinet. Bundles audited reference contracts for fair coin-flip (commit-reveal and signed-VRF variants) and a crash multiplier game with STX, sBTC, and arbitrary SIP-010 token wagering. Use when the user asks to deploy, scaffold, or test Clarity contracts; build a Stacks dApp; integrate sBTC; run Clarinet; or build provably-fair on-chain games on Stacks.
---

# Clarity / Stacks deployment skill

This skill scaffolds a [Clarinet](https://docs.hiro.so/stacks/clarinet) project, wires up testnet and mainnet deployment plans against Hiro's APIs, and ships three reference contract templates that are appropriate for real-money use **only after testnet validation and an external audit**.

## When to use

Trigger this skill when the user asks to:

- Scaffold a new Clarity / Stacks / Clarinet project
- Deploy a contract to Stacks testnet or mainnet via Hiro
- Build a provably-fair on-chain game (coin flip, crash, dice) on Stacks
- Wager STX, sBTC, or a SIP-010 fungible token on-chain
- Verify a randomness pattern in Clarity (commit-reveal, signed VRF)
- Migrate a non-Stacks (Solidity / Anchor) contract to Clarity

## Hard constraints (non-negotiable)

These are baked into every template the skill produces. **Do not weaken them:**

1. **No block-height-as-RNG.** `block-height`, `burn-block-height`, `stacks-block-height`, `tx-sender`, and `vrf-seed` alone are all miner-influenced or simulator-visible. They MUST NOT determine a wagering outcome on their own. See `references/randomness.md`.
2. **Deployer principal is read from the environment**, never hardcoded into a contract. The contract owner is captured at deploy time as `(define-data-var contract-owner principal tx-sender)` and rotated through `set-contract-owner`. The deployer mnemonic and target principal live in `.env` / `settings/Mainnet.toml`, both of which are gitignored.
3. **Testnet first.** The mainnet deployment script refuses to run unless a testnet `deployments/default.testnet-plan.yaml` has been applied, the contract has been exercised against the deployed instance, and a `MAINNET_AUDIT_ACK=true` env var has been set.
4. **Withdraw pattern, not push.** Winnings accrue to a per-user balance map and are withdrawn in a separate transaction. This neutralises re-entrancy concerns (Clarity has no re-entrancy in the EVM sense, but post-conditions and contract-call dynamics still benefit from the pattern) and bounds the loss surface if a single tx is replayed or front-run.
5. **Pause + owner rotation.** Every wagering contract ships with `paused`, `set-paused`, `set-contract-owner`, and `withdraw-house-fees` admin functions, all gated on `is-contract-owner`.
6. **No targeting of named third parties.** This skill will not generate logic that snipes, front-runs, or otherwise targets specific external principals, mempool patterns, or competitor launches. Wagering mechanics are PvP (player-vs-player) or PvH (player-vs-house) only.
7. **Jurisdictional disclaimer is present in the README.** On-chain wagering is regulated and prohibited in many jurisdictions. See `references/gambling-disclaimer.md`.

## Workflow

### Step 1 — Confirm intent and pick the template set

Ask the user (or infer from the prompt) which contracts they need. The skill ships four:

| Template                            | Wager asset       | Randomness               | Players  | When to pick                                                            |
| ----------------------------------- | ----------------- | ------------------------ | -------- | ----------------------------------------------------------------------- |
| `fair-flip-commit-reveal.clar`      | STX               | Commit-reveal (2 tx)     | PvH      | Fully on-chain, no off-chain operator. Slowest UX (~2 blocks).           |
| `fair-flip-vrf.clar`                | STX               | Operator signed seed     | PvH      | One-tx UX, requires an off-chain operator key, audit-friendly.          |
| `fair-flip-token.clar`              | SIP-010 / sBTC    | Commit-reveal (2 tx)     | PvH      | Same as commit-reveal but wagers a fungible token via the SIP-010 trait. |
| `crash.clar`                        | STX               | House commit-reveal      | Multi    | Multiplier game with multiple players per round.                        |

The general "deploy" workflow below works for any Clarity contract, not just these. If the user only wants the deploy scaffolding (no game), skip Steps 4–6.

### Step 2 — Scaffold the Clarinet project

```bash
# Install Clarinet if not present
# macOS:  brew install clarinet
# Linux:  See https://docs.hiro.so/stacks/clarinet/installation

clarinet new my-stacks-app
cd my-stacks-app
```

Then copy `templates/Clarinet.toml`, `templates/settings/*.toml`, and `templates/.env.example` over the generated files, adjusting the `[project]` name. The settings split (`Devnet.toml`, `Testnet.toml`, `Mainnet.toml`) is required so that the mainnet mnemonic never gets loaded by `clarinet test` or `clarinet console`.

### Step 3 — Configure the deployer

Copy `templates/.env.example` to `.env` and fill in:

```bash
DEPLOYER_MNEMONIC="word1 word2 ... word24"   # 24-word seed
DEPLOYER_PRINCIPAL="SP3..."                  # public address derived from the mnemonic
HIRO_API_KEY=""                              # optional, increases rate limits
NETWORK="testnet"                            # "testnet" | "mainnet"
```

Then verify the principal matches:

```bash
clarinet accounts                             # lists every account in settings/*.toml
```

If the user hands you a specific principal (for example `SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8`), set it as `DEPLOYER_PRINCIPAL` in `.env` **and** in `settings/Mainnet.toml`. **Never** inline it into a `.clar` file. If the user cannot prove they control the corresponding mnemonic, generate a fresh testnet mnemonic with `clarinet integrate` and use that until they confirm.

### Step 4 — Add contracts

For each contract you want to ship:

1. Copy `templates/contracts/<name>.clar` into the project's `contracts/` directory.
2. Add a matching entry to `Clarinet.toml`:

   ```toml
   [contracts.fair-flip]
   path = "contracts/fair-flip-commit-reveal.clar"
   clarity_version = 2
   epoch = 3.0
   ```

3. Run `clarinet check` to lint. Fix any reported issues before continuing.
4. Copy the matching test template from `templates/tests/` into `tests/`.

### Step 5 — Run unit tests

```bash
npm install
npm test
```

Tests use [`@hirosystems/clarinet-sdk`](https://www.npmjs.com/package/@hirosystems/clarinet-sdk) + Vitest. They are fast (~seconds) and run entirely in-process — no devnet required.

If a test fails, fix the contract, **not** the test, unless the test is asserting incorrect behaviour. The shipped tests cover: happy path, paused-state rejection, owner-only enforcement, double-claim rejection, expired-commit refund, and over-bet rejection.

### Step 6 — Generate and apply the testnet deployment plan

```bash
clarinet deployments generate --testnet --low-cost
clarinet deployments apply -p deployments/default.testnet-plan.yaml
```

This broadcasts to `https://api.testnet.hiro.so`. After it confirms (1–2 blocks, 10–20 minutes), exercise the deployed contract end-to-end. The skill ships `templates/scripts/deploy-testnet.sh` to wrap this and `templates/scripts/smoke-testnet.sh` to run a basic end-to-end check.

### Step 7 — Mainnet deployment (gated)

Only run this after Step 6 passes **and** the user explicitly confirms.

```bash
MAINNET_AUDIT_ACK=true ./scripts/deploy-mainnet.sh
```

The script verifies:

- A testnet plan was applied (`deployments/default.testnet-plan.yaml` exists and shows `applied: true`)
- `MAINNET_AUDIT_ACK=true` is set in the environment
- `DEPLOYER_PRINCIPAL` matches a real, funded mainnet account (queried via `https://api.hiro.so/extended/v1/address/<principal>/balances`)
- The contract has not already been deployed at that contract-id

Then it generates `deployments/default.mainnet-plan.yaml` and applies it.

## Decision tree

```
User asks for...
├── "deploy a Clarity contract"             → Steps 1–3, 6, 7. Skip 4–6 game stuff.
├── "build a coin flip on Stacks"
│   ├── "fully on-chain, no operator"       → fair-flip-commit-reveal.clar
│   ├── "single-tx UX, ok with operator"    → fair-flip-vrf.clar
│   └── "wager sBTC / SIP-010"              → fair-flip-token.clar
├── "build a crash game"                    → crash.clar
├── "use sBTC / SIP-010"                    → references/sip010-trait.md, fair-flip-token.clar
├── "what's safe randomness on Stacks?"     → references/randomness.md
└── "deploy via Hiro / Clarinet"            → references/hiro-deployment.md
```

## References

- `references/randomness.md` — Why `block-height` is unsafe; commit-reveal and signed-VRF patterns in Clarity.
- `references/sip010-trait.md` — How to use the SIP-010 trait for sBTC and arbitrary fungible tokens.
- `references/hiro-deployment.md` — Hiro API, Clarinet deployment plans, mainnet checklist.
- `references/gambling-disclaimer.md` — Jurisdictional notes the operator must read before mainnet.

## Templates

- `templates/Clarinet.toml` — Project manifest skeleton.
- `templates/settings/{Devnet,Testnet,Mainnet}.toml` — Network-specific settings (mnemonic placeholder).
- `templates/.env.example` — Deployer environment template.
- `templates/.gitignore` — Excludes `.env`, `settings/Mainnet.toml`, `deployments/`.
- `templates/contracts/sip-010-trait.clar` — SIP-010 fungible token trait.
- `templates/contracts/fair-flip-commit-reveal.clar` — STX wager, two-tx commit-reveal.
- `templates/contracts/fair-flip-vrf.clar` — STX wager, operator signed seed verified via `secp256k1-verify`.
- `templates/contracts/fair-flip-token.clar` — SIP-010 wager, two-tx commit-reveal.
- `templates/contracts/crash.clar` — Multi-player crash game, house commit-reveal.
- `templates/tests/*.test.ts` — Vitest + clarinet-sdk unit tests.
- `templates/scripts/deploy-testnet.sh` — Generates and applies the testnet plan.
- `templates/scripts/deploy-mainnet.sh` — Gated mainnet deployment.
- `templates/scripts/smoke-testnet.sh` — Basic end-to-end check after testnet apply.

## Operator notes

- `clarity_version = 2` and `epoch = 3.0` (Nakamoto) are required for `secp256k1-verify` to be available.
- `block-height` was deprecated in favour of `stacks-block-height` and `burn-block-height` in epoch 3.0. The templates use the new names.
- The skill assumes Clarinet >= 2.11. Older versions silently ignore `epoch`.
- `to-consensus-buff?` is the canonical way to serialise a `uint` for hashing. Do not roll your own byte-packing helper — earlier drafts of this skill did and the result was an off-by-one in the high byte.
