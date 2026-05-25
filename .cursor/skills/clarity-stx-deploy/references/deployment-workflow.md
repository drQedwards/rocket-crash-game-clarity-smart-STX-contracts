# Deployment Workflow

## Overview

Clarinet provides a structured deployment pipeline: simnet → devnet → testnet → mainnet.

## 1. Simnet (Unit Tests)

Simnet runs in-process via the Clarinet SDK. No external services needed.

```bash
npm install --save-dev @stacks/clarinet-sdk @stacks/transactions vitest
npx vitest run
```

## 2. Devnet (Local Network)

Clarinet devnet starts a local Stacks node + Bitcoin regtest.

```bash
clarinet devnet start
```

Contracts auto-deploy using `settings/Devnet.toml` accounts. Access the local explorer at `http://localhost:8000`.

## 3. Testnet

### Prerequisites
- Deployer mnemonic in `.env` as `STX_DEPLOYER_MNEMONIC`
- Fund deployer via [Hiro Faucet](https://explorer.hiro.so/sandbox/faucet?chain=testnet)

### Deploy
```bash
clarinet deployments generate --testnet
# Review: deployments/default.testnet-plan.yaml
clarinet deployments apply -p deployments/default.testnet-plan.yaml
```

### Verify
Check on [Hiro Explorer (testnet)](https://explorer.hiro.so/?chain=testnet).

## 4. Mainnet

### Pre-deployment Checklist

Complete ALL items before proceeding:

- [ ] All tests pass (`npx vitest run`)
- [ ] Deployed and manually tested on testnet
- [ ] Randomness is commit-reveal or signed-VRF (not block-height)
- [ ] Admin functions are owner-gated
- [ ] Pause mechanism works
- [ ] Withdrawal pattern used (pull, not push)
- [ ] No overflow/underflow in wager math
- [ ] House fee is capped (MAX-FEE-BPS)
- [ ] `.env` has mainnet deployer mnemonic
- [ ] Legal review for wagering contracts

### Deploy
```bash
clarinet deployments generate --mainnet
# CAREFULLY review: deployments/default.mainnet-plan.yaml
clarinet deployments apply -p deployments/default.mainnet-plan.yaml
```

### Post-deployment
- Verify on [Hiro Explorer (mainnet)](https://explorer.hiro.so/?chain=mainnet)
- Run integration tests against the deployed contract
- Monitor via Hiro Platform or custom indexer

## Deployment Plan YAML

The generated YAML specifies the transaction ordering, fee rates, and contract publish operations. Always review before applying.

```yaml
---
id: 0
name: "Deploy fair-flip"
network: testnet
stacks-node: "https://api.testnet.hiro.so"
plan:
  batches:
    - id: 0
      transactions:
        - contract-publish:
            contract-name: sip-010-trait
            expected-sender: $DEPLOYER
            cost: 10000
            path: contracts/sip-010-trait.clar
        - contract-publish:
            contract-name: fair-flip
            expected-sender: $DEPLOYER
            cost: 50000
            path: contracts/fair-flip-commit-reveal.clar
```
