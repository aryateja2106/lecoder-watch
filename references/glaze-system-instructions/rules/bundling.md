---
paths:
  - "**/glaze.config.ts"
---

# Packages That Can't Be Bundled (native modules, CJS, runtime assets)

Some npm packages can't be bundled by esbuild — they have native `.node` binaries, use CommonJS `require()` that esbuild can't analyze, or load files from disk at runtime. These need special handling via `glaze.config.ts` build configuration.

## Known packages that need plugins

| Package | Plugin | Notes |
| --- | --- | --- |
| `sharp` | `externalizePackage` | Has platform-specific binaries in scoped `@img/*` deps |
| `jsdom` | `externalizePackage` | Uses `__dirname` to load CSS/HTML assets at runtime |
| `node-pty` | `externalizePackage` | Loads runtime helper files from its package directory |
| `better-sqlite3-multiple-ciphers` | `copyNativeBindings` | Single `.node` file — but prefer `node:sqlite` instead unless you need encryption support |

**General rule:** After `npm install`, if a package ships native `.node` files or non-JS runtime helpers it expects to load from its own directory (executables, assets, templates), it needs a plugin.

## Recognizing bundling errors

| Error message | Cause | Fix |
| --- | --- | --- |
| `Cannot find module '…*.node'` | Native binary not copied to build output | `copyNativeBindings` or `externalizePackage` |
| `Dynamic require of "X" is not supported` | CJS package in ESM bundle | `externalizePackage` |
| `Module did not self-register` | Wrong architecture binary | Reinstall: `npm rebuild <pkg>` |
| Runtime crash with `__dirname` / file-not-found | Package loads assets from disk | `externalizePackage` |

## Which plugin to use

1. Package has a **single `.node` binary** and JS bundles fine → `copyNativeBindings("pkg", "binding.node")`
2. Package loads **files from disk at runtime**, depends on helper executables next to its package files, or has complex deps → `externalizePackage("pkg")`

## Quick reference

```typescript
// glaze.config.ts
import { defineConfig, copyNativeBindings, externalizePackage } from "@glaze/core/build";

const sharp = externalizePackage("sharp");

export default defineConfig({
  build: {
    external: [...sharp.externals],
    plugins: [sharp.plugin, copyNativeBindings("better-sqlite3-multiple-ciphers", "better_sqlite3.node")],
  },
});
```

See GLAZE-APP-GUIDE.md "Packages That Can't Be Bundled" for full code examples.
