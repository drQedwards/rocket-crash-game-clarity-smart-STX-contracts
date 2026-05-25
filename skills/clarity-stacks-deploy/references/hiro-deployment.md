# Hiro / Clarinet deployment workflow

## Tooling

- **Clarinet** (>=2.11) — local Clarity dev environment, deployment-plan generator, simnet test runner. Install via `brew install clarinet` on macOS or follow the [installation guide](https://docs.hiro.so/stacks/clarinet/installation) on Linux/Windows.
- **Hiro API** — `https://api.testnet.hiro.so` and `https://api.hiro.so`. Free tier: 100 req/min. Authenticated tier (with `x-api-key` header from [platform.hiro.so](https://platform.hiro.so/settings/api-keys)): 2k req/min.
- **Stacks Explorer** — `https://explorer.hiro.so` for testnet/mainnet block & tx inspection.

## Network endpoints

| Network | RPC                          | Faucet                                              |
| ------- | ---------------------------- | --------------------------------------------------- |
| Devnet  | `http://localhost:3999`      | Built into `clarinet integrate`                     |
| Testnet | `https://api.testnet.hiro.so`| https://platform.hiro.so/faucet                     |
| Mainnet | `https://api.hiro.so`        | (mainnet STX must be acquired through an exchange)  |

## Deployment-plan flow

Clarinet separates contract authoring from deployment via "plans". A plan is a YAML file that lists every contract to deploy, in order, with inferred fees and dependencies. The flow:

```bash
# 1. Write contracts in contracts/, register them in Clarinet.toml
clarinet check                            # static analysis

# 2. Generate a plan against the target network
clarinet deployments generate --testnet --low-cost

# 3. Inspect the plan
cat deployments/default.testnet-plan.yaml

# 4. Apply the plan
clarinet deployments apply -p deployments/default.testnet-plan.yaml
```

`apply` is interactive by default — it asks for confirmation before broadcasting each tx. Pass `--ci` to skip confirmation in scripts (this skill does NOT pass `--ci` for mainnet deploys).

## Plan options

| Flag           | Effect                                                                  |
| -------------- | ----------------------------------------------------------------------- |
| `--testnet`    | Targets testnet; mnemonic comes from `settings/Testnet.toml`.           |
| `--mainnet`    | Targets mainnet; mnemonic comes from `settings/Mainnet.toml`.           |
| `--low-cost`   | Sets fees just above the minimum mempool requirement.                   |
| `--no-batch`   | One contract per tx (recommended for first-time deploys; easier to debug). |
| `--manifest-path PATH` | Use a non-default `Clarinet.toml`.                              |

## Reading on-chain state without a tx

Use the Hiro API:

```bash
# Read a contract data var
curl -fsS "https://api.testnet.hiro.so/v2/contracts/call-read/${PRINCIPAL}/${CONTRACT}/get-current-round" \
  -H "Content-Type: application/json" \
  -d '{"sender":"'"${PRINCIPAL}"'","arguments":[]}'

# Get full contract interface
curl -fsS "https://api.testnet.hiro.so/v2/contracts/interface/${PRINCIPAL}/${CONTRACT}"

# Get balance
curl -fsS "https://api.testnet.hiro.so/extended/v1/address/${PRINCIPAL}/stx"
```

## Cost estimation

Clarity contracts are billed via "execution cost" units (read-counts, write-counts, runtime). `clarinet check` prints estimated costs per public function. The deployment fee is a separate dimension (number of bytes deployed). For these templates:

| Contract                         | Approx deploy cost |
| -------------------------------- | ------------------ |
| `sip-010-trait.clar`             | ~0.05 STX          |
| `fair-flip-commit-reveal.clar`   | ~0.4 STX           |
| `fair-flip-vrf.clar`             | ~0.4 STX           |
| `fair-flip-token.clar`           | ~0.4 STX           |
| `crash.clar`                     | ~0.5 STX           |

Numbers above are rough; the actual fee in your plan is computed from `--low-cost` or the network's recent fee distribution. Fund the deployer with at least 5 STX before mainnet deploy.

## Common failure modes

- **`Contract already exists at ...`** — pick a fresh deployer principal or rename the contract.
- **`Insufficient balance for fee`** — fund the deployer.
- **`Plan transaction expired`** — the nonce was consumed by another tx; regenerate the plan.
- **`epoch not supported`** — Clarinet < 2.11. Upgrade.
- **`secp256k1-verify is not a known function`** — old epoch in `Clarinet.toml`. Set `epoch = 3.0`.

## Mainnet checklist

Before applying a mainnet plan:

- [ ] All vitest tests pass.
- [ ] `clarinet check` is clean.
- [ ] Testnet plan was applied AND end-to-end tested with real testnet txs (the smoke-test script doesn't replace this — actually invoke `place-bet`, `reveal-round`, `withdraw`, etc.).
- [ ] An external auditor or independent reviewer has read the contract.
- [ ] The deployer mnemonic is hardware-backed and was generated specifically for this deploy.
- [ ] Owner rotation plan is documented (you should rotate to a multisig or hardware-only key shortly after deploy).
- [ ] Jurisdictional review for on-chain wagering completed (see `gambling-disclaimer.md`).
- [ ] `MAINNET_AUDIT_ACK=true` set in env (the deploy script enforces this).
