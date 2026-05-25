#!/usr/bin/env bash
# Deploy contracts to Stacks MAINNET via Hiro.
#
# This script REFUSES TO RUN unless:
#   1. MAINNET_AUDIT_ACK="true" is set in the environment (not just .env)
#   2. A testnet plan exists and was applied (deployments/default.testnet-plan.yaml)
#   3. .env has MAINNET_DEPLOYER_MNEMONIC + MAINNET_DEPLOYER_PRINCIPAL set
#   4. The mainnet deployer account is funded with STX
#   5. None of the contracts are already deployed at the target principal
#
# Even with all gates green, you should manually review:
#   - The crash formula and house bond
#   - The owner principal (rotate from a hot wallet ASAP after deploy)
#   - The jurisdiction-specific implications of operating on-chain wagering
#
# Usage:
#   MAINNET_AUDIT_ACK=true bash scripts/deploy-mainnet.sh

set -euo pipefail

if [[ "${MAINNET_AUDIT_ACK:-false}" != "true" ]]; then
  cat <<'EOF'
========================================================================
MAINNET DEPLOYMENT BLOCKED
========================================================================
This script refuses to run unless you have explicitly set:
    MAINNET_AUDIT_ACK=true
in the environment (not just in .env). This is a deliberate gate so a
mainnet deployment cannot happen by accident.

Before setting it, confirm that:
  [ ] The contracts have been audited (or you've accepted the risk).
  [ ] The testnet plan was applied AND end-to-end tested with real txs.
  [ ] The legal/jurisdictional implications of operating an on-chain
      wagering contract from your jurisdiction have been reviewed.
  [ ] The mainnet deployer is a freshly-generated, hardware-wallet-
      backed mnemonic, NOT a re-used hot wallet.

Then run:
  MAINNET_AUDIT_ACK=true bash scripts/deploy-mainnet.sh
========================================================================
EOF
  exit 1
fi

if [[ ! -f .env ]]; then
  echo "Error: .env not found."
  exit 1
fi
# shellcheck disable=SC1091
source .env

if [[ -z "${MAINNET_DEPLOYER_MNEMONIC:-}" ]] || \
   [[ -z "${MAINNET_DEPLOYER_PRINCIPAL:-}" ]]; then
  echo "Error: MAINNET_DEPLOYER_MNEMONIC and MAINNET_DEPLOYER_PRINCIPAL must be set."
  exit 1
fi

if [[ ! "${MAINNET_DEPLOYER_PRINCIPAL}" =~ ^SP ]]; then
  echo "Error: MAINNET_DEPLOYER_PRINCIPAL must start with 'SP' for mainnet."
  exit 1
fi

# Refuse to deploy if there is no testnet plan record.
TESTNET_PLAN="deployments/default.testnet-plan.yaml"
if [[ ! -f "${TESTNET_PLAN}" ]]; then
  echo "Error: ${TESTNET_PLAN} not found. Run scripts/deploy-testnet.sh first."
  exit 1
fi

# Soft check: did the testnet plan record show the deployer applied transactions?
# Clarinet records this in deployments/default.testnet-plan.yaml after apply.
if ! grep -q "transactions:" "${TESTNET_PLAN}"; then
  echo "Error: ${TESTNET_PLAN} doesn't look like an applied plan."
  exit 1
fi

# Verify deployer is funded on mainnet.
HIRO_HEADERS=()
if [[ -n "${HIRO_API_KEY:-}" ]]; then
  HIRO_HEADERS=(-H "x-api-key: ${HIRO_API_KEY}")
fi

balance_micro=$(curl -fsS "${HIRO_HEADERS[@]}" \
  "https://api.hiro.so/extended/v1/address/${MAINNET_DEPLOYER_PRINCIPAL}/stx" \
  | grep -oE '"balance":"[0-9]+"' | head -1 | grep -oE '[0-9]+' || echo "0")

# Need at least ~3 STX for fees on a multi-contract deploy.
if [[ "${balance_micro}" -lt 3000000 ]]; then
  echo "Error: mainnet deployer has < 3 STX (${balance_micro} microSTX). Fund it first."
  exit 1
fi

# Check the contracts are not already deployed.
for contract in fair-flip fair-flip-vrf fair-flip-token crash sip-010-trait; do
  status=$(curl -fsS -o /dev/null -w "%{http_code}" "${HIRO_HEADERS[@]}" \
    "https://api.hiro.so/v2/contracts/interface/${MAINNET_DEPLOYER_PRINCIPAL}/${contract}" || true)
  if [[ "${status}" == "200" ]]; then
    echo "Error: ${MAINNET_DEPLOYER_PRINCIPAL}.${contract} already exists on mainnet."
    echo "Either pick a fresh deployer or rename the contract in Clarinet.toml."
    exit 1
  fi
done

clarinet check
clarinet deployments generate --mainnet --low-cost --no-batch

PLAN="deployments/default.mainnet-plan.yaml"
if [[ ! -f "${PLAN}" ]]; then
  echo "Error: mainnet plan was not generated at ${PLAN}"
  exit 1
fi

echo ""
echo "MAINNET PLAN GENERATED at ${PLAN}"
echo ""
echo "Review the plan carefully, then apply manually with:"
echo ""
echo "  clarinet deployments apply -p ${PLAN}"
echo ""
echo "This script does NOT auto-apply mainnet deploys."
