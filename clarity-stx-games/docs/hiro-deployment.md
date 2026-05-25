# Hiro and Clarinet deployment flow

Use Clarinet locally and Hiro Platform for network deployment visibility.

## Local setup

```sh
clarinet new clarity-stx-games
cp -R skills/clarity-stx-deployment/contracts clarity-stx-games/contracts
cp skills/clarity-stx-deployment/templates/Clarinet.toml clarity-stx-games/Clarinet.toml
cp -R skills/clarity-stx-deployment/templates/settings clarity-stx-games/settings
cp skills/clarity-stx-deployment/templates/.env.example clarity-stx-games/.env
cd clarity-stx-games
clarinet check
clarinet test
```

## Testnet

1. Fund a fresh testnet deployer account.
2. Set `STACKS_DEPLOYER_MNEMONIC` in local shell/CI secret storage.
3. Generate a plan:

```sh
clarinet deployments generate --testnet --low-cost
```

4. Inspect every generated transaction.
5. Apply only after the plan matches the intended contracts:

```sh
clarinet deployments apply --testnet
```

## Mainnet

Do not apply mainnet deployment plans until `mainnet-checklist.md` is complete.

```sh
clarinet deployments generate --mainnet
clarinet deployments apply --mainnet
```

## Hiro Platform notes

- Use Hiro Platform to inspect deployments, contract calls, events, and API access.
- Keep API keys in secret stores.
- Verify public contract source after deployment and link the verified source in the
  project README.
