#!/usr/bin/env bash
# Quick smoke check after a testnet deploy: verify each contract's interface
# is reachable on Hiro testnet under the deployer principal.
#
# Usage: bash scripts/smoke-testnet.sh

set -euo pipefail

if [[ ! -f .env ]]; then
  echo "Error: .env not found."
  exit 1
fi
# shellcheck disable=SC1091
source .env

if [[ -z "${TESTNET_DEPLOYER_PRINCIPAL:-}" ]]; then
  echo "Error: TESTNET_DEPLOYER_PRINCIPAL not set."
  exit 1
fi

HIRO_HEADERS=()
if [[ -n "${HIRO_API_KEY:-}" ]]; then
  HIRO_HEADERS=(-H "x-api-key: ${HIRO_API_KEY}")
fi

pass=0
fail=0
for contract in sip-010-trait fair-flip fair-flip-vrf fair-flip-token crash; do
  url="https://api.testnet.hiro.so/v2/contracts/interface/${TESTNET_DEPLOYER_PRINCIPAL}/${contract}"
  status=$(curl -fsS -o /dev/null -w "%{http_code}" "${HIRO_HEADERS[@]}" "${url}" || true)
  if [[ "${status}" == "200" ]]; then
    echo "  OK   ${contract}"
    pass=$((pass + 1))
  else
    echo "  FAIL ${contract}  (HTTP ${status})"
    fail=$((fail + 1))
  fi
done

echo ""
echo "${pass} ok, ${fail} missing"
[[ ${fail} -eq 0 ]] || exit 1
