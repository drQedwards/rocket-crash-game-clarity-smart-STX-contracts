# On-chain wagering: jurisdictional notes for operators

The contracts in this skill (fair-flip and crash variants) implement
real-money wagering. Before mainnet deploy, the operator should know:

## What this skill does NOT do

This skill does NOT provide legal advice. It does not enumerate every
jurisdiction's rules. It does not establish that any of the contracts
shipped here are lawful in any specific jurisdiction. It does not provide
KYC/AML controls — there is no identity-verification layer in any contract.

## Common jurisdictional categories

Real-money wagering is regulated to varying degrees in essentially every
jurisdiction. Categories include:

1. **Outright prohibition for residents** — e.g. operating or facilitating
   gambling for residents of the U.S. (state-by-state), Singapore, China,
   most of the Middle East. "Operating" can include hosting a frontend, a
   backend relayer, or even a community Discord that points at a contract,
   regardless of where the contract itself lives.

2. **Licensing requirements** — e.g. UK Gambling Commission, Malta Gaming
   Authority, Curaçao eGaming, Isle of Man, Gibraltar. Operating without
   a licence in these jurisdictions is a criminal offence even if no
   residents from those jurisdictions ever bet.

3. **Geofencing requirements** — many licensed jurisdictions require IP-
   geofencing, address validation, and refusal of service to residents of
   prohibited jurisdictions. A pure on-chain contract has no IP-level
   geofencing; the frontend must implement it.

4. **AML / sanctions screening** — operators may be required to screen
   addresses against OFAC SDN lists and implement transaction monitoring
   above certain thresholds.

5. **Tax reporting** — winnings may be reportable income in the player's
   jurisdiction; payouts above thresholds may trigger withholding obligations
   for the operator.

## Things that are technical concerns, not legal advice

- **Address-level geofencing** is impossible from inside a Clarity
  contract. There is no IP information visible on-chain. Geofencing is a
  frontend / WAF concern.

- **No-KYC operation** is a regulatory risk in licensed jurisdictions and
  generally indicates an unlicensed operation. The contracts shipped here
  do not perform KYC.

- **Anonymous deployer** — deploying from an anonymous mnemonic does NOT
  shield the operator from regulatory action in the operator's actual
  jurisdiction. Chain analysis, social attribution, and exchange records
  routinely identify operators of "anonymous" gambling contracts.

## Recommended action before mainnet deploy

- Engage a lawyer in the operator's jurisdiction who has experience with
  online gambling regulation.
- If targeting players in any specific country, engage a lawyer in that
  country.
- Decide whether to pursue licensing (a months-to-years process) or to
  operate as a "pure tooling provider" with a frontend that disclaims
  service to all jurisdictions.
- Document the decisions and the legal opinions backing them.

## What "MAINNET_AUDIT_ACK=true" means

Setting this env var, in the context of this skill, signifies that the
operator has read this document, accepted the residual risks, and is
proceeding with their own legal counsel. It is a tripwire, not absolution.
