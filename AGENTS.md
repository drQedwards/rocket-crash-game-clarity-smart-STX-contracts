# AGENTS.md

## Cursor Cloud specific instructions

### Project Structure

This is a two-part blockchain casino application (not a monorepo workspace):
- `crash-game-bakcend/` — Node.js/Express/TypeScript backend (port 4000)
- `crash-game-frontend/` — React/Vite/TypeScript frontend (port 5000)

Both use `npm` as the package manager (lockfiles: `package-lock.json`).

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

| Service | Lint | Build | Dev |
|---------|------|-------|-----|
| Frontend | `npm run lint` | `npm run build` (currently fails, see above) | `npm run dev` |
| Backend | N/A (no lint script) | `npm run build` (webpack) | `npm run dev` |

### Environment Variables

- `MONGO_URI` — MongoDB connection string (backend). Default: placeholder string; set to `mongodb://localhost:27017/pixa` for local dev.
- `PORT` — Backend server port (default: `4000`)
- `JWT_SECRET` — JWT signing secret (default: `"secret"`)
- `ACCOUNT_PRIVATE_KEY` — EVM private key for on-chain withdrawals (optional for basic testing)
- `BACK_URL` — Backend URL for frontend (default: `http://localhost:4000`)
