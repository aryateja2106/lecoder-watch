---
name: glaze-migrate-to-cli
description: One-time migration from legacy template structure (glaze-backend.js, scripts/, vite.config.ts, and local ESLint setup) to the glaze CLI.
---

# Glaze Migrate To CLI

This is a **one-time migration** for apps built before the glaze CLI restructure. The Glaze host now launches the `glaze` CLI directly (no more `glaze-backend.js`), and build/dev/lint are handled by CLI defaults (no legacy `scripts/` or `vite.config.ts`).

## When to Run

Run this skill when the app has **any** of these indicators:

- `glaze-backend.js` exists in the app root
- `scripts/` directory exists (build-main.ts, build-paths.ts, sync-runtime-manifest.js, plugins/)
- `vite.config.ts` exists in the app root
- `eslint.config.js` exists in the app root (legacy template lint config)
- `tsconfig.node.json` exists in the app root
- `package.json` scripts still reference old commands (for example `tsx scripts/build-main.ts`)
- `package.json` is missing CLI tooling devDependencies required by `glaze build/lint/format`

If none of these exist, the migration is already done and this skill can be skipped.

## Migration Steps

### 1. Delete stale files

These files are now handled by the `glaze` CLI and `@glaze/core/build`:

```bash
# Old entry point — Swift now launches glaze CLI directly
rm -f glaze-backend.js

# Old Vite and lint config — now provided by glaze CLI / @glaze/core defaults
rm -f vite.config.ts
rm -f eslint.config.js

# Old tsconfig for build scripts — no longer needed
rm -f tsconfig.node.json

# Old build/dev/manifest scripts — all handled by glaze CLI
rm -f scripts/sync-runtime-manifest.js
rm -f scripts/build-paths.ts
rm -f scripts/plugins/copy-native-bindings.ts
rm -f scripts/plugins/externalize-package.ts
```

**Do not delete `scripts/build-main.ts` yet**. It may contain user customizations. Check step 2 first.

### 2. Migrate `scripts/build-main.ts` customizations to `glaze.config.ts`

If `scripts/build-main.ts` exists, check whether it includes custom esbuild plugins or extra externals beyond defaults.

If it is default-only, delete it.

If it has custom logic, move that logic to `glaze.config.ts`:

```typescript
import { copyNativeBindings, defineConfig } from "@glaze/core/build";

export default defineConfig({
  build: {
    external: ["some-package"],
    plugins: [copyNativeBindings("better-sqlite3-multiple-ciphers", "better_sqlite3.node")],
  },
});
```

After migration:

```bash
rm -f scripts/build-main.ts
rmdir scripts/plugins 2>/dev/null || true
rmdir scripts 2>/dev/null || true
```

### 3. Ensure CLI tooling devDependencies exist in `package.json`

Add these `devDependencies` if missing:

- `esbuild`
- `vite`
- `@vitejs/plugin-react`
- `@tailwindcss/vite`
- `babel-plugin-react-compiler`
- `eslint`
- `@eslint/js`
- `@typescript-eslint/eslint-plugin`
- `@typescript-eslint/parser`
- `eslint-plugin-import`
- `globals`
- `oxfmt`

Notes:

- `glaze build` resolves tooling from app `node_modules` first (SDK fallback second).
- `glaze lint` uses app `eslint` plus the shared framework config from `@glaze/core` by default.
- `glaze format` uses app `oxfmt` by default.
- If the app intentionally has a custom `eslint.config.js`, keep it.

### 4. Update npm scripts

Replace old scripts with CLI wrappers:

```json
"scripts": {
  "build": "node glaze.ts build",
  "dev": "node glaze.ts dev",
  "dev:renderer": "node glaze.ts dev:renderer",
  "lint": "node glaze.ts lint",
  "type-check": "node glaze.ts type-check",
  "format": "node glaze.ts format"
}
```

### 5. Update references in source code

Search and update any lingering references:

- `tsx scripts/build-main.ts` -> `node glaze.ts build`
- old build commands -> `npm run build` or `node glaze.ts build`

Also update references to the skill command itself:

- `/migrate-to-glaze-cli` -> `/glaze-migrate-to-cli`
- `/glaze-cli-migration` -> `/glaze-migrate-to-cli`

### 6. Build and verify

```bash
npm run build
npm run lint
```

Fix errors and rerun until clean.

## Available CLI Commands

| Command              | Description                                              |
| -------------------- | -------------------------------------------------------- |
| `glaze build`        | Build backend + renderer + sync runtime manifest         |
| `glaze dev`          | Start full dev environment (backend + renderer)          |
| `glaze dev:renderer` | Start renderer dev server only                           |
| `glaze start`        | Start the built app                                      |
| `glaze lint`         | Run ESLint (app-local binary, framework config fallback) |
| `glaze type-check`   | Run TypeScript type checking (`tsc --noEmit`)            |
| `glaze format`       | Format code with Oxfmt                                   |

## Important Rules

- Keep `package.json` scripts as thin wrappers (`node glaze.ts <cmd>`). Do not add custom build logic there.
- Do not recreate `glaze-backend.js`, `vite.config.ts`, or legacy `scripts/` files.
- Keep build customizations in `glaze.config.ts` only.
- `@glaze/core` is provided by the Glaze host via shared SDK paths. Do not install it from npm.
- Keep `glaze.ts` as the CLI entrypoint; it resolves the SDK from a sibling `glaze-core` package or the deployed `sdk/current` directory.
