# Mainnet checklist

Complete this checklist before deploying or activating any mainnet wagering contract.

## Contract correctness

- [ ] `clarinet check` passes.
- [ ] `clarinet test` covers all public entrypoints.
- [ ] Tests cover success, failure, timeout/refund, pause, fee, and admin paths.
- [ ] Contract source has been reviewed by someone who did not write it.
- [ ] No outcome depends only on block height, sender, transaction id, or backend RNG.
- [ ] Bankroll and max-payout exposure have been modeled.
- [ ] Fee math and rounding have been tested at minimum and maximum wager sizes.

## Operations

- [ ] Project owner principal is correct:
  `SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8`.
- [ ] Deployer mnemonic/private key is stored in a secret manager, not in git.
- [ ] Pause procedure is documented.
- [ ] Oracle/VRF signer key rotation is documented if using signed randomness.
- [ ] Monitoring exists for failed settlements, stuck rounds, and low bankroll.
- [ ] Testnet deployment has run with real wallet flows.

## Legal and product

- [ ] Jurisdictional review is complete for real-money wagering.
- [ ] Terms, risk disclosures, and age/location gates are ready if applicable.
- [ ] No logic targets named third-party services, queues, principals, or competitors.
- [ ] Admin powers, fees, and payout rules are documented for users.

## Deployment

- [ ] Generated mainnet deployment plan has been inspected.
- [ ] Contract addresses are recorded in README/config.
- [ ] Source verification steps are complete or scheduled immediately after deploy.
