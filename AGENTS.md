# AGENTS.md

## Cursor Cloud specific instructions

### Project Structure

This is a three-part blockchain casino application (not a monorepo workspace):
- `crash-game-bakcend/` — Node.js/Express/TypeScript backend (port 4000)
- `crash-game-frontend/` — React/Vite/TypeScript frontend (port 5000)
- `clarity-stx-games/` — Clarinet project with the on-chain Stacks Clarity
  contracts (`fair-flip-stx`, `fair-flip-sip010`, `fair-flip-signed-vrf`,
  `crash-game-stx`, `sip010-ft-trait`, `flip-stats`). See
  [`clarity-stx-games/README.md`](clarity-stx-games/README.md) for the
  Clarinet/Hiro deployment workflow.

The Node services use `npm` (lockfiles: `package-lock.json`). The Clarinet
project uses `clarinet` (install via Hiro releases) plus `npm` for the
clarinet-sdk vitest harness.

### Prerequisites

- **Node.js >= 18** (pre-installed in Cloud Agent VMs)
- **MongoDB 7.0** must be running on `localhost:27017` before starting the backend

### Starting MongoDB

```sh
mongod --dbpath /data/db --logpath /var/log/mongodb/mongod.log --fork
```

Verify with: `mongosh --eval "db.runCommand({ping:1})"`

### Running Services

**Backend** (port 4000):
```sh
cd crash-game-bakcend
MONGO_URI=mongodb://localhost:27017/pixa npm run dev
```

**Frontend** (port 5000):
```sh
cd crash-game-frontend
npm run dev
```

### Known Pre-existing Code Issues

1. **Backend cannot start**: `src/services/crash.ts` has a syntax error (mismatched braces at line 32 — a stray `};`). This causes `ts-node` (and `tsx`/esbuild) to fail. Using `TS_NODE_TRANSPILE_ONLY=true` does not help since this is a syntax error, not a type error.
2. **Frontend build (`npm run build`) fails**: `tsc -b` fails because page component files are missing — `src/pages/crashGame/index.tsx`, `src/pages/mineGame/index.tsx`, and `src/pages/coinflipGame/index.tsx` do not exist (only their `.module.scss` files do).
3. **Frontend Vite dev server starts** but the app fails to render at runtime because Vite cannot resolve `@pages/crashGame` (same missing files).
4. **ESLint** (`npm run lint` in frontend) runs but reports 28 pre-existing errors and 30 warnings.

### Lint / Test / Build Commands

| Service          | Lint           | Build / Check                                        | Dev                                          |
| ---------------- | -------------- | ---------------------------------------------------- | -------------------------------------------- |
| Frontend         | `npm run lint` | `npm run build` (currently fails, see above)         | `npm run dev`                                |
| Backend          | N/A            | `npm run build` (webpack)                            | `npm run dev`                                |
| Clarity contracts | N/A           | `clarinet check` in `clarity-stx-games/`             | `clarinet console` / `npm test` (simnet)     |

### Deploying the Clarity contracts

1. Install Clarinet from the Hiro releases page (binary at `~/.local/bin/clarinet`).
2. `cd clarity-stx-games && clarinet check`
3. Fund a fresh testnet deployer, put its mnemonic into the gitignored
   `clarity-stx-games/settings/Testnet.toml`.
4. `clarinet deployments generate --testnet --low-cost`, inspect
   `deployments/default.testnet-plan.yaml`, then
   `clarinet deployments apply --testnet`.
5. Do not run mainnet `apply` until every box in
   `clarity-stx-games/docs/mainnet-checklist.md` is ticked.

### Environment Variables

- `MONGO_URI` — MongoDB connection string (backend). Default: placeholder string; set to `mongodb://localhost:27017/pixa` for local dev.
- `PORT` — Backend server port (default: `4000`)
- `JWT_SECRET` — JWT signing secret (default: `"secret"`)
- `ACCOUNT_PRIVATE_KEY` — EVM private key for on-chain withdrawals (optional for basic testing)
- `BACK_URL` — Backend URL for frontend (default: `http://localhost:4000`)
