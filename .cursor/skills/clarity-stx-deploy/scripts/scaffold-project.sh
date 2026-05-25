#!/usr/bin/env bash
set -euo pipefail

# Scaffold a new Clarinet project with skill contract templates.
# Usage: ./scaffold-project.sh <project-name> [contract-type]
#
# contract-type: flip-cr | flip-vrf | flip-sip010 | crash | all (default: flip-cr)

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="${1:?Usage: $0 <project-name> [contract-type]}"
CONTRACT_TYPE="${2:-flip-cr}"

echo "==> Creating Clarinet project: $PROJECT_NAME"
clarinet new "$PROJECT_NAME"
cd "$PROJECT_NAME"

echo "==> Copying SIP-010 trait"
cp "$SKILL_DIR/contracts/sip-010-trait.clar" contracts/

copy_contract() {
  local src="$1" name="$2"
  echo "==> Copying $name"
  cp "$SKILL_DIR/contracts/$src" "contracts/$src"
}

case "$CONTRACT_TYPE" in
  flip-cr)
    copy_contract "fair-flip-commit-reveal.clar" "Fair Flip (Commit-Reveal)"
    ;;
  flip-vrf)
    copy_contract "fair-flip-vrf.clar" "Fair Flip (Signed VRF)"
    ;;
  flip-sip010)
    copy_contract "fair-flip-sip010.clar" "Fair Flip (SIP-010)"
    ;;
  crash)
    copy_contract "crash-game.clar" "Crash Game"
    ;;
  all)
    copy_contract "fair-flip-commit-reveal.clar" "Fair Flip (Commit-Reveal)"
    copy_contract "fair-flip-vrf.clar" "Fair Flip (Signed VRF)"
    copy_contract "fair-flip-sip010.clar" "Fair Flip (SIP-010)"
    copy_contract "crash-game.clar" "Crash Game"
    ;;
  *)
    echo "Unknown contract type: $CONTRACT_TYPE"
    echo "Valid types: flip-cr, flip-vrf, flip-sip010, crash, all"
    exit 1
    ;;
esac

echo "==> Copying settings templates"
cp "$SKILL_DIR/templates/settings/Testnet.toml" settings/Testnet.toml
cp "$SKILL_DIR/templates/settings/Mainnet.toml" settings/Mainnet.toml

echo "==> Copying test templates"
mkdir -p tests
cp "$SKILL_DIR/tests/"*.test.ts tests/ 2>/dev/null || true

echo "==> Creating .env template"
cat > .env.example <<'EOF'
# Stacks deployer mnemonic (24-word BIP-39)
# Generate: clarinet console → ::get_stx_address
STX_DEPLOYER_MNEMONIC=
EOF

echo "==> Creating .gitignore additions"
cat >> .gitignore <<'EOF'

# Secrets
.env
*.mnemonic

# Clarinet
.cache/
.devnet/
node_modules/
EOF

echo ""
echo "Project scaffolded at: $(pwd)"
echo ""
echo "Next steps:"
echo "  1. Register contracts in Clarinet.toml"
echo "  2. Run: clarinet check"
echo "  3. Run: npm install && npx vitest run"
echo "  4. Deploy: clarinet devnet start"
