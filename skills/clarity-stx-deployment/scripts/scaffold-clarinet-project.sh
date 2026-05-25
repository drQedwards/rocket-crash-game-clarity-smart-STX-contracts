#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${1:-clarity-stx-games}"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -e "$PROJECT_NAME" ]]; then
  echo "Refusing to overwrite existing path: $PROJECT_NAME" >&2
  exit 1
fi

if ! command -v clarinet >/dev/null 2>&1; then
  echo "clarinet is required. Install it from https://docs.hiro.so/tools/clarinet before scaffolding." >&2
  exit 1
fi

clarinet new "$PROJECT_NAME"
mkdir -p "$PROJECT_NAME/contracts" "$PROJECT_NAME/tests" "$PROJECT_NAME/settings" "$PROJECT_NAME/docs"

cp "$SKILL_DIR/contracts/"*.clar "$PROJECT_NAME/contracts/"
cp "$SKILL_DIR/templates/Clarinet.toml" "$PROJECT_NAME/Clarinet.toml"
cp "$SKILL_DIR/templates/.env.example" "$PROJECT_NAME/.env.example"
cp "$SKILL_DIR/templates/settings/"*.toml "$PROJECT_NAME/settings/"
cp "$SKILL_DIR/tests/"*.ts "$PROJECT_NAME/tests/"
cp "$SKILL_DIR/references/"*.md "$PROJECT_NAME/docs/"

cat <<'MSG'
Scaffold complete.

Next steps:
1. cd into the project.
2. Copy .env.example to .env and fill local/testnet values.
3. Run clarinet check and clarinet test.
4. Deploy to testnet before any mainnet plan.
MSG
