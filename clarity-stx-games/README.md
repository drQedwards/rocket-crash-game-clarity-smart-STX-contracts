# clarity-stx-games

Clarinet project containing the Stacks Clarity contracts for the casino /
coin-flip game in this repo. Scaffolded from the
[`skills/clarity-stx-deployment`](../skills/clarity-stx-deployment/SKILL.md)
skill.

## Contracts

| Contract                | Purpose                                                                                                                                                                                                                                                |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `sip010-ft-trait`       | Standard SIP-010 fungible-token trait, depended on by `fair-flip-sip010`.                                                                                                                                                                              |
| `fair-flip-stx`         | STX wager fair-flip using two-party commit/reveal randomness and a timeout/refund path. Safe to ship to mainnet (after the checklist) because no outcome depends only on `block-height`.                                                               |
| `fair-flip-sip010`      | Same shape as `fair-flip-stx` but settled in any SIP-010 token (e.g. sBTC).                                                                                                                                                                            |
| `fair-flip-signed-vrf`  | Operator-signed randomness variant (suitable when an audited VRF / oracle publishes signed outcomes).                                                                                                                                                  |
| `crash-game-stx`        | Crash multiplier game with house commit/reveal and per-player cash-out targets.                                                                                                                                                                        |
| `flip-stats`            | Informational coin-flip counter + top-10 leaderboard. Ported from the legacy [`Flip.clarinet`](../Flip.clarinet) at the repo root. Does **not** move STX. Its `block-height`-derived "side" output is fine for stats but not safe for real-money play. |

## Quick start

```sh
# 1. Install Clarinet (https://docs.hiro.so/clarinet)
# 2. From the repo root:
cd clarity-stx-games

# 3. Static checks (analyser + check_checker)
clarinet check

# 4. Generate a deployment plan you can inspect
clarinet deployments generate --devnet
clarinet deployments generate --testnet --low-cost
```

## Deployment workflow

The skill mandates a strict deploy ladder. Do not skip ahead.

### 1. simnet (local, no network)

```sh
npm install            # one time, pulls clarinet-sdk + vitest
npm test               # runs the starter test in tests/
```

`tests/fair-flip-stx.test.ts` is a starter; expand it to cover every public
entrypoint, error path, timeout/refund path, fee path, and admin control before
moving on. See `docs/mainnet-checklist.md`.

### 2. devnet (local stacks node)

```sh
clarinet deployments generate --devnet
clarinet deployments apply --devnet      # requires Docker + clarinet devnet up
```

### 3. testnet

1. Fund a fresh testnet deployer account at
   <https://explorer.hiro.so/sandbox/faucet?chain=testnet>.
2. Put the deployer mnemonic into `settings/Testnet.toml` (this file is
   gitignored). The recommended form is the encrypted variant produced by
   `clarinet deployments encrypt`.
3. Generate and inspect the plan:

   ```sh
   clarinet deployments generate --testnet --low-cost
   ```

4. Apply only after the plan matches what you intend to publish:

   ```sh
   clarinet deployments apply --testnet
   ```

### 4. mainnet

Mainnet deployment is gated by `docs/mainnet-checklist.md`. Do not run
`clarinet deployments apply --mainnet` until every box is ticked, including:

- All `*.clar` contracts independently reviewed.
- Tests cover success, failure, timeout/refund, pause, fee, and admin paths.
- `fair-flip-*` contracts deployed and exercised on testnet end to end with
  real wallets.
- Deployer mnemonic is in a secret manager, not in git.
- Project owner principal (`SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8`) confirmed.
- Pause / withdraw procedures documented.
- Jurisdictional / compliance review complete for real-money wagering.

## Generated artifacts

| File                                      | Notes                                                                                                                                                                       |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `deployments/default.devnet-plan.yaml`    | Generated for verification. Local-only, regenerate before each run.                                                                                                         |
| `deployments/default.testnet-plan.yaml`   | Generated with the **public** Clarinet dev mnemonic (`twice kind fence …`) as a placeholder. **Regenerate** with your own funded mnemonic before `apply`. Sender address `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM` will change accordingly. |

The mainnet plan is intentionally not generated in this scaffold.

## Cost estimate

At `--low-cost` fee rate (10 micro-STX/byte) the testnet plan currently
publishes 6 contracts for a total of **~2.26 STX** of testnet fees
(~0.378 STX each). Mainnet costs are network-dependent; regenerate the plan
against `settings/Mainnet.toml` to see live numbers.
