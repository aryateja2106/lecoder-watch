---
name: glaze-core-imports
description: Update imports to use the @glaze/core entry points (components, hooks, utils).
---

# Glaze Core Imports

This skill guides you through updating imports to use the `@glaze/core` entry points.

## Overview

The `@glaze/core` package provides components, hooks, and utilities through separate entry points:

| Entry Point              | Purpose                      | Examples                                           |
| ------------------------ | ---------------------------- | -------------------------------------------------- |
| `@glaze/core/components` | UI components                | `Button`, `Dialog`, `Sidebar`, `Select`            |
| `@glaze/core/hooks`      | React hooks                  | `useTheme`, `useConnection`, `useEnvironment`      |
| `@glaze/core/utils`      | Utility functions (no React) | `cn`, `initLogging`, `isDevelopmentFlavor`, `menu` |

### How @glaze/core is resolved

`@glaze/core` is **not** an npm dependency. It is resolved at each tool level:

- **TypeScript**: `tsconfig.json` paths (for type checking only)
- **Vite**: Aliases configured by `@glaze/core` build module (renderer builds)
- **esbuild**: Externals configured by `@glaze/core` build module (backend builds — leaves imports as bare specifiers)
- **Runtime (Node.js)**: ESM resolve hook in `glaze start` CLI reads `GLAZE_SDK_PATH` env var, pointing to Glaze.app's bundled SDK
- **Runtime (WebView)**: Import maps via `glaze-core://` protocol handler

Apps do **not** have `@glaze/core` in `package.json` dependencies or `node_modules/@glaze/core` symlinks.

## Step 0: Update Config Files to Match Template

**Before making any import changes**, update the app's config files to match the template. The template is the source of truth for config files.

**Config files to update (copy from template):**

| File                  | Action                                                     |
| --------------------- | ---------------------------------------------------------- |
| `renderer/styles.css` | Copy from template (replaces old shared/index.css imports) |

Build configuration (`vite.config.ts`, `tsconfig.json`, `eslint.config.js`) is now managed by `@glaze/core` and no longer lives in the app template. Use `glaze.config.ts` for build customization.

> **Note:** The template path is typically `packages/glaze-app-template/` relative to the desktop-glaze project root.

### Remove @glaze/core from package.json

If the app's `package.json` still has `@glaze/core` as a dependency (e.g., `"@glaze/core": "file:../glaze-core"`), **remove it**. The SDK is resolved through build tool configuration, not npm.

```bash
# Check if @glaze/core is in package.json
grep -n "@glaze/core" package.json

# If found, remove the line and run npm install to clean up
npm install --include=dev
```

### Remove .glaze-core directory

If the app has a local `.glaze-core/` directory or symlink, **delete it**. The SDK is no longer bundled per-app.

```bash
rm -rf .glaze-core
```

### Remove node_modules/@glaze/core symlink

If `node_modules/@glaze/core` exists (as a symlink or directory), remove it:

```bash
rm -rf node_modules/@glaze/core
```

After `npm install` with the updated `package.json` (without `@glaze/core`), this symlink will not be recreated.

---

## Migration from @renderer/shared/\*

If your app imports from `@renderer/shared/*`, follow these steps:

### Step 1: Find all @renderer/shared imports

```bash
grep -r "from ['\"]@renderer/shared" renderer/
```

### Step 2: Update component imports

**Before:**

```typescript
import { Button, Dialog } from "@renderer/shared/components/button";
import { Sidebar } from "@renderer/shared/components/sidebar";
```

**After:**

```typescript
import { Button, Dialog, Sidebar } from "@glaze/core/components";
```

### Step 3: Update hook imports

**Before:**

```typescript
import { useTheme } from "@renderer/shared/hooks/use-theme";
import { useConnection } from "@renderer/shared/hooks/use-connection";
```

**After:**

```typescript
import { useTheme, useConnection } from "@glaze/core/hooks";
```

### Step 4: Update utility imports

**Before:**

```typescript
import { cn } from "@renderer/shared/utils/cn";
import { initLogging } from "@renderer/shared/utils/logging-init";
```

**After:**

```typescript
import { cn, initLogging } from "@glaze/core/utils";
```

### Step 5: Update renderer entrypoint CSS import

**Before:**

```typescript
import "@renderer/shared/index.css";
```

**After:**

```typescript
import "../styles.css";
```

Use the app-local `renderer/styles.css` from each renderer entrypoint (`renderer/main/index.tsx`, `renderer/settings/index.tsx`, etc.).  
Do **not** import `@glaze/core/components.css` from app source files — SDK component styles are injected at runtime by the native shell.

### Step 6: Clean up deprecated files

After all imports are updated and the app builds successfully, delete the old shared folder:

```bash
rm -rf renderer/shared/
```

> **CRITICAL: About `sync-from-main.js`**
>
> This script **no longer exists** and **must not be created**. It was removed as part of this migration.
>
> - If the script file doesn't exist: **This is correct. Do nothing.**
> - If you find references to it anywhere: **Delete the references. Do NOT create the script.**
> - **NEVER create a noop, placeholder, or stub** for this script.
>
> Components are now bundled in `@glaze/core` - no sync mechanism is needed.

---

## Migration from @glaze/core/components (splitting entry points)

If your app already imports from `@glaze/core/components` but mixes hooks/utils with components:

### Step 1: Find all imports from @glaze/core/components

```bash
grep -r "from ['\"]@glaze/core/components['\"]" renderer/
```

### Step 2: Categorize each import

For each import, determine which entry point it should come from:

**Hooks (move to `@glaze/core/hooks`):**

- `useTheme`
- `useConnection`
- `useEnvironment`
- `connectionQueryKeys`
- `useWindowFocusState`
- `useOnWindowFocusStateChange`
- `useNativeDropdownMenu` (internal hook for native dropdown menu behavior)
- `useNativeSelect` (internal hook for native select behavior)

**Utils (move to `@glaze/core/utils`):**

- `cn`
- `initLogging`
- `isDevelopmentFlavor`
- `isInternalFlavor`
- `isProductionFlavor`
- `getBuildFlavor`
- `getDeeplinkScheme`
- `menu`
- `buildNativeMenuItems`
- `handleMenuResult`
- `showNativeMenu`
- `getScreenPosition`
- `getElementScreenPosition`
- Type exports: `Rectangle`, `MenuItemType`, `MenuItemRole`, `MenuItemConstructorOptions`, `PopupOptions`, `PopupResult`, `NativeMenuIcon`, `NativeMenuItem`, etc.

**Components (stay in `@glaze/core/components`):**

- All UI components: `Button`, `Dialog`, `Sidebar`, `Panel`, `Toolbar`, `Input`, `Select`, `SelectItem`, `SelectGroup`, `DropdownMenu`, `ContextMenu`, etc.
- Provider components: `TooltipProvider`, `Toaster`

### Step 3: Update imports

**Before:**

```typescript
import { Button, useTheme, cn, initLogging, Sidebar, isDevelopmentFlavor } from "@glaze/core/components";
```

**After:**

```typescript
import { Button, Sidebar } from "@glaze/core/components";
import { useTheme } from "@glaze/core/hooks";
import { cn, initLogging, isDevelopmentFlavor } from "@glaze/core/utils";
```

## Common Migration Patterns

### Pattern 1: Root view with theme and connection

**Before:**

```typescript
import { useTheme, useConnection, useEnvironment, Status, isDevelopmentFlavor } from "@glaze/core/components";
```

**After:**

```typescript
import { Status } from "@glaze/core/components";
import { useTheme, useConnection, useEnvironment } from "@glaze/core/hooks";
import { isDevelopmentFlavor } from "@glaze/core/utils";
```

### Pattern 2: Entry point initialization

**Before:**

```typescript
import { TooltipProvider, Toaster, initLogging } from "@glaze/core/components";
```

**After:**

```typescript
import { TooltipProvider, Toaster } from "@glaze/core/components";
import { initLogging } from "@glaze/core/utils";
```

### Pattern 3: Component with cn utility

**Before:**

```typescript
import { Button, cn } from "@glaze/core/components";
```

**After:**

```typescript
import { Button } from "@glaze/core/components";
import { cn } from "@glaze/core/utils";
```

### Pattern 4: Native menu utilities

**Before:**

```typescript
import { menu, buildNativeMenuItems, handleMenuResult, type NativeMenuItem } from "@glaze/core/components";
```

**After:**

```typescript
import { menu, buildNativeMenuItems, handleMenuResult, type NativeMenuItem } from "@glaze/core/utils";
```

## Important Notes

### SelectItem component vs NativeSelectItem hook type

Be careful not to confuse the `SelectItem` component with the `NativeSelectItem` type:

- **Component** (`SelectItem`) - import from `@glaze/core/components` (this is what you use in JSX)
- **Type** (`type NativeSelectItem`) - import from `@glaze/core/hooks` (used internally by the `useNativeSelect` hook)

In most cases, you want the component:

```typescript
import { Select, SelectItem, SelectContent } from "@glaze/core/components";
```

### Re-exports in native/index.ts

If you have a `renderer/ipc/native/index.ts` that re-exports from `@glaze/core/components`, update those to use `@glaze/core/utils`:

```typescript
// Before
export { menu, buildNativeMenuItems } from "@glaze/core/components";

// After
export { menu, buildNativeMenuItems } from "@glaze/core/utils";
```

## Verification

After migration, verify your app builds successfully:

```bash
glaze build
```

If you see errors about missing exports, double-check which entry point the export should come from using the categorization above.

## Quick Reference

| Export                       | Entry Point              |
| ---------------------------- | ------------------------ |
| Any `use*` hook              | `@glaze/core/hooks`      |
| `cn`                         | `@glaze/core/utils`      |
| `initLogging`                | `@glaze/core/utils`      |
| `*Flavor` functions          | `@glaze/core/utils`      |
| `menu`, `*Menu*` utils       | `@glaze/core/utils`      |
| UI components                | `@glaze/core/components` |
| `Toaster`, `TooltipProvider` | `@glaze/core/components` |

## Troubleshooting

### `import.meta.hot` errors

If you see TypeScript errors like:

```
Property 'hot' does not exist on type 'ImportMeta'
```

This is unrelated to the SDK migration but may surface when running `glaze type-check`. Ensure you have a `renderer/vite-env.d.ts` file with:

```typescript
/// <reference types="vite/client" />
```

This adds Vite's client types which define `import.meta.hot` for HMR support.
