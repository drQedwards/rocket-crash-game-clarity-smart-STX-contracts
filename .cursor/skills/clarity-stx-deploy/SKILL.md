# Clarity STX Deploy Skill

## When to Use

Use this skill when:
- Scaffolding a new Clarinet project for Stacks smart contracts
- Deploying Clarity contracts to devnet, testnet, or mainnet via Hiro tooling
- Building a fair coin-flip (PvP or PvHouse) contract with provable randomness
- Building a crash/multiplier game contract on Stacks
- Wiring STX, sBTC, or arbitrary SIP-010 token wagers into a contract
- Generating Clarinet deployment plans (`clarinet deployments generate`)
- Writing vitest unit tests for Clarity contracts using `@stacks/clarinet-sdk`

**Trigger keywords**: clarity, clarinet, stacks deploy, STX contract, coin flip contract, crash game contract, SIP-010 wager, hiro deploy, mainnet deployment plan

---

## Decision Tree

```
START
│
├─ User wants to scaffold a new Clarinet project?
│  → Section A: Project Scaffold
│
├─ User wants a fair-flip / coin-flip contract?
│  ├─ Fully on-chain (no off-chain operator)?
│  │  → Use contracts/fair-flip-commit-reveal.clar (two-tx commit-reveal)
│  ├─ Off-chain operator signs randomness?
│  │  → Use contracts/fair-flip-vrf.clar (secp256k1-verify)
│  └─ Wager with SIP-010 token (sBTC etc.)?
│     → Use contracts/fair-flip-sip010.clar
│
├─ User wants a crash / multiplier game?
│  → Use contracts/crash-game.clar
│
├─ User wants to deploy?
│  ├─ Devnet → Section B: Devnet Deployment
│  ├─ Testnet → Section C: Testnet Deployment
│  └─ Mainnet → Section D: Mainnet Deployment (gated by checklist)
│
└─ User wants tests?
   → Section E: Vitest Tests
```

---

## Section A: Project Scaffold

Run:
```bash
clarinet new <project-name>
cd <project-name>
```

This generates:
```
<project-name>/
├── Clarinet.toml
├── contracts/
├── settings/
│   ├── Devnet.toml
│   ├── Testnet.toml
│   └── Mainnet.toml
├── tests/
└── package.json
```

Then copy the desired contract template(s) from this skill's `contracts/` directory into the project's `contracts/` folder and register them in `Clarinet.toml`:

```toml
[contracts.fair-flip]
path = "contracts/fair-flip-commit-reveal.clar"
```

### Deployer Principal

The deployer address comes from the network settings files, NOT hardcoded in contracts. For the project owner `SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8`, set it in `settings/Mainnet.toml`:

```toml
[accounts.deployer]
mnemonic = "${STX_DEPLOYER_MNEMONIC}"
```

And in `.env`:
```
STX_DEPLOYER_MNEMONIC=<your 24-word mnemonic>
```

**Never commit mnemonics. Add `.env` to `.gitignore`.**

---

## Section B: Devnet Deployment

```bash
clarinet devnet start
```

This starts a local Stacks node + Bitcoin regtest and auto-deploys all contracts in `Clarinet.toml`.

---

## Section C: Testnet Deployment

```bash
clarinet deployments generate --testnet
clarinet deployments apply -p deployments/default.testnet-plan.yaml
```

Verify on [Hiro Explorer (testnet)](https://explorer.hiro.so/?chain=testnet).

---

## Section D: Mainnet Deployment

**CRITICAL: Complete this checklist before mainnet deployment.**

### Pre-Mainnet Checklist

- [ ] All contract tests pass (`npm test` / `vitest run`)
- [ ] Contract has been deployed and tested on testnet
- [ ] Randomness uses commit-reveal or signed-VRF (never `block-height` alone)
- [ ] Admin functions are owner-gated (`contract-caller` check)
- [ ] Pause mechanism works and has been tested
- [ ] Withdrawal pattern is used (users pull funds, contract doesn't push)
- [ ] No arithmetic overflow/underflow in wager calculations
- [ ] House fee percentage is configurable and capped
- [ ] `.env` has the correct mainnet deployer mnemonic
- [ ] Jurisdiction review: on-chain wagering has legal implications

```bash
clarinet deployments generate --mainnet
# Review the plan CAREFULLY
clarinet deployments apply -p deployments/default.mainnet-plan.yaml
```

---

## Section E: Vitest Tests

Install the SDK:
```bash
npm install --save-dev @stacks/clarinet-sdk @stacks/transactions vitest
```

See `tests/fair-flip.test.ts` in this skill for a reference test file.

Run tests:
```bash
npx vitest run
```

---

## Contract Templates

| File | Description | Randomness |
|------|-------------|------------|
| `contracts/sip-010-trait.clar` | Standard SIP-010 fungible token trait | N/A |
| `contracts/fair-flip-commit-reveal.clar` | PvP/PvHouse coin flip, STX wager, two-tx commit-reveal | Commit-reveal (on-chain) |
| `contracts/fair-flip-vrf.clar` | Coin flip with operator-signed VRF seed | secp256k1-verify |
| `contracts/fair-flip-sip010.clar` | Coin flip accepting any SIP-010 token wager | Commit-reveal (on-chain) |
| `contracts/crash-game.clar` | Crash/multiplier game, STX wager | Commit-reveal (on-chain) |

---

## References

- `references/deployment-workflow.md` — Full deployment lifecycle
- `references/randomness-patterns.md` — Why block-height is insecure, commit-reveal and VRF patterns
- `references/sip010-wagers.md` — Using SIP-010 traits for sBTC and arbitrary token wagers

---

## Important Safety Notes

1. **Randomness**: `block-height` and `burn-block-height` are publicly known before a block is mined. Miners can manipulate outcomes. Always use commit-reveal (two-tx pattern) or a signed VRF with `secp256k1-verify`.

2. **Wagering contracts**: On-chain gambling has legal implications depending on jurisdiction. This skill provides the technical implementation; the operator is responsible for legal compliance.

3. **Testnet first**: Always deploy and test on testnet before mainnet. The skill gates mainnet deployment behind a checklist.

4. **Key management**: Never hardcode mnemonics or private keys. Use `.env` files (gitignored) and Clarinet's settings files.
