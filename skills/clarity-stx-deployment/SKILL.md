# Clarity STX Deployment Skill

Use this skill when a user asks to build, scaffold, review, or deploy Clarity smart
contracts for Stacks using Clarinet and Hiro tooling, especially coin-flip/crash-style
wagering contracts with STX, sBTC, or SIP-010 assets.

This skill is deliberately conservative. It helps create legal, auditable, neutral
contracts and deployment workflows; it does not help target named third-party users,
queues, principals, or launch flows.

## Default project context

- Default Stacks project owner principal:
  `SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8`
- Treat deployer accounts as environment-specific. Read them from `.env`,
  `Clarinet.toml`, or `settings/*.toml`; do not hardcode private keys, mnemonics,
  or signer secrets.
- ENS names such as `ens.app` are Ethereum identifiers and are not Stacks principals.
  If the user wants a name-based identity on Stacks, use a BNS name and resolve it to
  a Stacks principal before using it in a contract or deployment.
- Mainnet deployment target: Hiro Platform / Clarinet deployment plans.

## Non-negotiable safety rules

1. Never ship a real-money wagering contract that uses `block-height`,
   `burn-block-height`, `tx-sender`, transaction id, or mempool ordering as the sole
   randomness source.
2. Prefer either:
   - two-party commit-reveal with timeout/refund paths, or
   - signed-result VRF/oracle flow where the contract verifies the operator signature
     and the operator has published commitments before accepting wagers.
3. Keep mainnet steps behind an explicit checklist: tests, local simnet run, testnet
   deployment, exploit review, jurisdiction/compliance review, pause/withdraw
   controls, and bankroll/liquidity review.
4. Do not implement logic that targets Solpump.io, its users, named competitors, or
   any external queue. Build neutral PvP/PvHouse mechanics only.
5. Do not add a house edge, fee destination, or admin key that is hidden from the
   README, tests, and deployment config.

## Workflow

1. **Clarify scope**
   - Contract type: fair flip, crash multiplier, token wager, or deployment-only.
   - Asset: STX, sBTC, or arbitrary SIP-010 token.
   - Randomness model: commit-reveal, signed VRF, or both.
   - Network: simnet, testnet, or mainnet. Start with simnet/testnet.

2. **Scaffold**
   - Copy `templates/Clarinet.toml` into the new Clarinet project.
   - Copy `templates/settings/Testnet.toml` and `templates/settings/Mainnet.toml`.
   - Copy `.env.example` and set non-secret deployment values. Secrets stay in local
     shell/CI secret stores.
   - Copy only the contract templates needed by the user's chosen scope.

3. **Implement contracts**
   - Use `contracts/fair-flip-stx.clar` for STX commit-reveal wagers.
   - Use `contracts/fair-flip-sip010.clar` plus `contracts/sip010-ft-trait.clar`
     for sBTC or arbitrary SIP-010 token wagers.
   - Use `contracts/fair-flip-signed-vrf.clar` when an off-chain operator publishes
     signed outcomes.
   - Use `contracts/crash-game-stx.clar` as a neutral crash-game settlement template.

4. **Test**
   - Add Clarinet tests for each public entrypoint, error path, timeout path, fee path,
     and admin control.
   - Run `clarinet check`.
   - Run `clarinet test`.
   - If using Hiro Platform, generate and inspect a deployment plan before applying.

5. **Deploy with Hiro/Clarinet**
   - Testnet:
     `clarinet deployments generate --testnet --low-cost`
     then inspect the generated plan and run
     `clarinet deployments apply --testnet`.
   - Mainnet:
     complete `references/mainnet-checklist.md`, then generate/apply a mainnet plan.

## File guide

- `contracts/`: Clarity contract templates and traits.
- `templates/`: Clarinet config and env templates.
- `tests/`: starter Clarinet/Vitest test template.
- `references/randomness.md`: how to choose a randomness model.
- `references/token-wagers.md`: using sBTC and SIP-010 assets.
- `references/hiro-deployment.md`: Hiro/Clarinet deployment flow.
- `references/mainnet-checklist.md`: pre-mainnet gate.
- `scripts/scaffold-clarinet-project.sh`: copies this skill into a fresh Clarinet
  project layout.

## Response pattern for agents

When using this skill, tell the user which randomness model and asset path you chose,
what files were created or modified, and which verification commands passed. If the
user asks for mainnet deployment before the checklist is complete, provide the missing
checklist items and stop before applying the mainnet deployment.
