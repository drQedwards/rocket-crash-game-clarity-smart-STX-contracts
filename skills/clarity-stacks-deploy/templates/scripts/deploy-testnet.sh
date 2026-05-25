#!/usr/bin/env bash
# Deploy contracts to Stacks testnet via Hiro.
#
# Prereqs:
#   - Clarinet >= 2.11 installed
#   - .env populated with TESTNET_DEPLOYER_MNEMONIC and TESTNET_DEPLOYER_PRINCIPAL
#   - Deployer account funded with testnet STX
#     ( https://platform.hiro.so/faucet )
#
# Usage:
#   bash scripts/deploy-testnet.sh

set -euo pipefail

if [[ ! -f .env ]]; then
  echo "Error: .env not found. Copy .env.example to .env and fill it in."
  exit 1
fi
# shellcheck disable=SC1091
source .env

if [[ -z "${TESTNET_DEPLOYER_MNEMONIC:-}" ]]; then
  echo "Error: TESTNET_DEPLOYER_MNEMONIC is not set in .env"
  exit 1
fi
if [[ -z "${TESTNET_DEPLOYER_PRINCIPAL:-}" ]]; then
  echo "Error: TESTNET_DEPLOYER_PRINCIPAL is not set in .env"
  exit 1
fi

# Sanity-check the principal looks like a testnet address.
if [[ ! "${TESTNET_DEPLOYER_PRINCIPAL}" =~ ^ST ]]; then
  echo "Error: TESTNET_DEPLOYER_PRINCIPAL must start with 'ST' for testnet."
  exit 1
fi

# Verify the deployer is funded (>= 1 STX recommended).
HIRO_HEADERS=()
if [[ -n "${HIRO_API_KEY:-}" ]]; then
  HIRO_HEADERS=(-H "x-api-key: ${HIRO_API_KEY}")
fi

balance_micro=$(curl -fsS "${HIRO_HEADERS[@]}" \
  "https://api.testnet.hiro.so/extended/v1/address/${TESTNET_DEPLOYER_PRINCIPAL}/stx" \
  | grep -oE '"balance":"[0-9]+"' | head -1 | grep -oE '[0-9]+' || echo "0")

if [[ "${balance_micro}" -lt 1000000 ]]; then
  echo "Error: deployer ${TESTNET_DEPLOYER_PRINCIPAL} has < 1 STX (balance: ${balance_micro} microSTX)."
  echo "Fund it at https://platform.hiro.so/faucet"
  exit 1
fi

echo "Deployer ${TESTNET_DEPLOYER_PRINCIPAL} has ${balance_micro} microSTX. Generating plan..."

clarinet check
clarinet deployments generate --testnet --low-cost --no-batch

PLAN="deployments/default.testnet-plan.yaml"
if [[ ! -f "${PLAN}" ]]; then
  echo "Error: plan was not generated at ${PLAN}"
  exit 1
fi

echo "Plan generated. Review it before applying:"
echo "  ${PLAN}"
echo ""
echo "Run:  clarinet deployments apply -p ${PLAN}"
echo "      (this skill does not auto-apply — review the plan first)"
