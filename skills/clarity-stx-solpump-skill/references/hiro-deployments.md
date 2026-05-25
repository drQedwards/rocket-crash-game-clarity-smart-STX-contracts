# Hiro Deployment Workflow (Clarinet)

## 1) Bootstrap
```bash
clarinet new clip-rocket-stx
cd clip-rocket-stx
```

Copy template files from this skill:
- `templates/Clarinet.toml`
- `templates/settings/*.toml`
- `templates/contracts/*.clar`
- `templates/tests/*.test.ts`

Contracts included:
- `clip-orderbook.clar`
- `crash-rocket.clar`
- `fair-flip-commit-reveal.clar`
- `fair-flip-vrf.clar`
- `fair-flip-sip010.clar`

## 2) Configure deployer
```bash
cp templates/.env.example .env
```
Set:
- `DEPLOYER_MAINNET_PRINCIPAL`
- `DEPLOYER_TESTNET_PRINCIPAL`
- `DEPLOYER_MNEMONIC`

## 3) Testnet first
```bash
clarinet check
clarinet test
clarinet deployments generate --testnet
clarinet deployments apply -p deployments/default.testnet-plan.yaml
```

## 4) Mainnet rollout
Only after passing `references/mainnet-checklist.md`:
```bash
clarinet deployments generate --mainnet
clarinet deployments apply -p deployments/default.mainnet-plan.yaml
```

## 5) Verify on explorer
Use Hiro explorer to verify contract IDs, tx status, and deployed source.
