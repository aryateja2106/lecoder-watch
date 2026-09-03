---
name: glaze-sdk-externalize
description: One-time migration from legacy shared components (renderer/shared/) to the externalized @glaze/core SDK.
---

# Glaze SDK Externalize

This is a **one-time migration** for apps created before the SDK was externalized. Once completed, this skill is no longer needed for future upgrades.

## When to Run

Run this skill when `renderer/shared/` still exists in the app's source code. This means the app is using the legacy bundled components and needs to migrate to `@glaze/core`.

If `renderer/shared/` does not exist, the migration is already done — skip this skill.

## Migration Steps

### 1. Migrate imports from `@renderer/shared/*` to `@glaze/core/*`

Run the `/glaze-core-imports` skill. It handles:

- `@renderer/shared/components/*` → `@glaze/core/components`
- `@renderer/shared/hooks/*` → `@glaze/core/hooks`
- `@renderer/shared/utils/*` → `@glaze/core/utils`

### 2. Remove `renderer/shared/`

Only after all imports are migrated and building successfully:

```bash
rm -rf renderer/shared/
```

### 3. Fix CSS references

In `renderer/styles.css`:

- Keep `@import "@glaze/core/components.tailwind.css"` (Tailwind needs this for SDK theme token definitions)
- Remove any legacy `@reference "@glaze/core/components.css"` line

### 4. Fix renderer entrypoint imports

Ensure each renderer entrypoint (e.g., `renderer/main/index.tsx`) imports local styles:

```typescript
import "../styles.css";
```

Do **not** import `@glaze/core/components.css` or `@glaze/core/components.tailwind.css` from entrypoints. SDK styles are loaded at runtime by the native shell.

### 5. Build and verify

```bash
glaze build
```

Fix any errors and rebuild until clean.

## Important Rules

- Do not add `@glaze/core` as an npm dependency. It is provided by the Glaze host via a shared SDK directory and resolved via tsconfig paths and ESM hooks — NOT from `node_modules`.
- Do not create or restore legacy sync scripts (e.g., `sync-from-main.js`).
- Do not add `@reference "@glaze/core/components.css"` or `@import "@glaze/core/components.css"` to app CSS files.
- Do not rewrite renderer entrypoints to `import "@glaze/core/components.css"` or `import "@glaze/core/components.tailwind.css"`.
