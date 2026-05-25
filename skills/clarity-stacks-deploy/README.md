# clarity-stacks-deploy skill

Scaffolds a Clarinet project, ships three reference Clarity wagering
contracts, and gates mainnet deployment behind explicit testnet validation
and operator acknowledgement.

## What's in the box

```
skills/clarity-stacks-deploy/
├── SKILL.md                      # Entry point, loaded by the agent
├── README.md                     # This file
├── references/
│   ├── randomness.md             # Why block-height isn't safe; commit-reveal & VRF
│   ├── sip010-trait.md           # Wagering arbitrary fungible tokens (sBTC, etc.)
│   ├── hiro-deployment.md        # Clarinet plans, Hiro APIs, mainnet checklist
│   └── gambling-disclaimer.md    # Jurisdictional notes for operators
└── templates/
    ├── Clarinet.toml             # Project manifest
    ├── package.json              # vitest + clarinet-sdk
    ├── vitest.config.ts
    ├── .env.example              # Deployer mnemonic & gating env vars
    ├── .gitignore
    ├── settings/
    │   ├── Devnet.toml           # Standard Clarinet devnet accounts
    │   ├── Testnet.toml          # ${TESTNET_DEPLOYER_MNEMONIC} env interp.
    │   └── Mainnet.toml          # ${MAINNET_DEPLOYER_MNEMONIC} (gitignored)
    ├── contracts/
    │   ├── sip-010-trait.clar              # SIP-010 fungible-token trait
    │   ├── fair-flip-commit-reveal.clar    # STX, commit-reveal, fully on-chain
    │   ├── fair-flip-vrf.clar              # STX, secp256k1 signed RNG
    │   ├── fair-flip-token.clar            # SIP-010 / sBTC, commit-reveal
    │   └── crash.clar                      # Multi-player crash, target-multiplier
    ├── tests/
    │   ├── setup.ts
    │   ├── fair-flip-commit-reveal.test.ts
    │   ├── fair-flip-vrf.test.ts
    │   └── crash.test.ts
    └── scripts/
        ├── deploy-testnet.sh     # Generate plan, sanity-check, do not auto-apply
        ├── deploy-mainnet.sh     # Gated by MAINNET_AUDIT_ACK + testnet plan
        └── smoke-testnet.sh      # Verify each contract is reachable post-deploy
```

## Installation

Drop the directory into wherever your toolchain looks for skills. For
Cursor, copy `skills/clarity-stacks-deploy/` into either:

- `<repo>/.cursor/skills/clarity-stacks-deploy/` for repo-scoped access, or
- the user-level skills directory under `~/.cursor/...`.

Validate with:

```bash
test -f skills/clarity-stacks-deploy/SKILL.md && \
  echo "ok: SKILL.md frontmatter present"
```

## Invoking

The skill triggers on prompts that mention any of:

- "deploy / scaffold a Clarity / Stacks / Clarinet contract"
- "Hiro testnet / mainnet deploy"
- "fair coin flip" / "crash game" on Stacks
- "sBTC wager" / "SIP-010 wager"
- "commit-reveal" / "VRF" on Stacks

When triggered, the agent reads `SKILL.md`, picks the right template set
based on the user's intent, and runs through Steps 1–7 of the workflow.

## Hard "no"s baked in

The `SKILL.md` "Hard constraints" section is **not editable by the agent
at runtime**. The skill will refuse to:

1. Hardcode a principal into a `.clar` file (it is always read from env).
2. Generate logic that targets specific external principals (sniping a
   competing token launch, MEV against a named project's users, etc.).
3. Ship `block-height` / `tx-sender` as the sole randomness source on a
   wagering contract.
4. Auto-apply a mainnet deployment without `MAINNET_AUDIT_ACK=true` and a
   prior testnet plan.

If a user request appears to require any of those, the agent surfaces the
constraint and proposes the safe alternative.

## Bringing your own deployer

If the user supplies a specific mainnet principal — for example,
`SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8` — the workflow:

1. Sets `MAINNET_DEPLOYER_PRINCIPAL` in `.env`.
2. Asks the user to provide the matching 24-word mnemonic out-of-band
   (never in chat).
3. Verifies via `clarinet accounts --network=mainnet` that the mnemonic
   derives to the supplied principal.
4. Refuses to proceed if they don't match.

If the user cannot prove they control the mnemonic for the supplied
principal, the skill generates a fresh testnet mnemonic and uses that
until the user confirms.

## Caveats

- **Audit before mainnet.** None of these templates have been formally
  audited. They follow defensive patterns (commit-reveal, withdraw, owner
  rotation, pausable, bond-bounded exposure) but are reference
  implementations, not production-ready code.
- **Operator liveness.** Both fair-flip variants depend on an operator to
  reveal in time. The contracts enforce a refund-with-slashing path
  after `reveal-window` blocks, but a malicious operator could intentionally
  let close calls fail to drain the bond. Tune `reveal-window` and
  `expiry-penalty` carefully.
- **VRF caveat.** The signed-VRF variant assumes RFC-6979 deterministic
  ECDSA. A non-deterministic signer can grind nonces. The contract
  cannot enforce determinism on-chain.
- **Decimals.** SIP-010 token bounds (`min-bet`, `max-bet`) are in the
  token's smallest unit. Reset them after `set-token` to make sense for
  that token's decimals.

## License

Same as the parent repository.
