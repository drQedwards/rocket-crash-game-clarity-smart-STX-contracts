# Clip + Rocket Pattern on STX

This skill splits responsibilities into separate contracts:

- `clip-orderbook.clar`: order queue and deterministic matching state
- `crash-rocket.clar`: round lifecycle and claim-based crash payouts
- `fair-flip-*`: 50/50 wager flows using either commit-reveal or signed-result verification

## Why split contracts?
- Keeps each contract's state machine smaller and easier to audit.
- Lets teams deploy/update queue logic independently from game logic.
- Supports shared admin controls (owner, pause, fee policy) with explicit wiring.

## Suggested integration
1. Use `clip-orderbook.clar` to create and match intents.
2. Trigger wager rounds from application logic when matched intents are finalized.
3. Resolve fair outcomes with one of the fair-flip contracts.
4. Feed order and round events to indexers for UI books and history pages.
