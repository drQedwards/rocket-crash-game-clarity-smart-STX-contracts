#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${1:-clip-rocket-stx}"

clarinet new "$PROJECT_NAME"
cd "$PROJECT_NAME"

mkdir -p contracts settings tests scripts

echo "Copy templates into the new project root:"
echo "  - templates/Clarinet.toml -> Clarinet.toml"
echo "  - templates/settings/* -> settings/"
echo "  - templates/contracts/* -> contracts/"
echo "  - templates/tests/* -> tests/"
echo "Then run: clarinet check && clarinet test"
