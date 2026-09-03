---
name: glaze-icon-usage
description: Guidelines for using icons in Glaze apps. Always use solid fill colors, never semi-transparent alpha colors.
---

# Glaze Icon Usage

This skill covers how to correctly use icons in Glaze applications.

**For extracting macOS app icons** (e.g., showing icons of running apps), see the `glaze-backend-performance` skill — it covers `NSWorkspace.iconForFile()` via JXA, maxBuffer safety, and caching patterns.

## Icon Library

Use **lucide-react** for all icons. Import icons directly with the `Icon` suffix:

```typescript
import { PlusIcon, SettingsIcon, ChevronLeftIcon } from "lucide-react";
```

## Icon Sizing

Size icons using Tailwind's width/height utilities via `className`:

| Context                      | Class                 | Size |
| ---------------------------- | --------------------- | ---- |
| Small UI controls            | `w-3.5 h-3.5`         | 14px |
| Standard (buttons, lists)    | `size-4` or `w-4 h-4` | 16px |
| Medium (toolbar icons)       | `w-5 h-5`             | 20px |
| Large (display/empty states) | `w-8 h-8`             | 32px |

## CRITICAL: Always Use Solid Fill Colors

**Always use solid color tokens. NEVER use semi-transparent alpha (`-a`) color variants on icons.**

Lucide icons are stroke-based and have overlapping strokes. When semi-transparent alpha colors are applied, the overlapping areas become visibly darker, producing ugly artifacts. Solid colors avoid this entirely because there is no transparency for overlaps to compound.

| WRONG            | CORRECT         |
| ---------------- | --------------- |
| `text-gray-a10`  | `text-gray-10`  |
| `text-gray-a11`  | `text-gray-11`  |
| `text-gray-a9`   | `text-gray-9`   |
| `text-blue-a10`  | `text-blue-10`  |
| `text-red-a10`   | `text-red-10`   |
| `text-green-a10` | `text-green-10` |

### Examples

```typescript
// CORRECT - solid fills
<PlusIcon className="size-4 text-gray-11" />
<CheckCircle2Icon className="h-4 w-4 text-green-10" />
<AlertTriangleIcon className="h-4 w-4 text-red-10" />
<Loader2Icon className="h-4 w-4 animate-spin text-blue-10" />

// WRONG - semi-transparent alpha colors
<PlusIcon className="size-4 text-gray-a11" />
<Loader2Icon className="h-4 w-4 animate-spin text-gray-a10" />
```

### Always Set an Explicit Color

Do NOT rely on inheriting the parent text color — the default text color in Glaze is semi-transparent, which causes the same overlapping stroke artifacts. Always set an explicit solid color class on icons:

```typescript
// WRONG - inherits semi-transparent default text color
<SettingsIcon className="w-4 h-4" />

// CORRECT - explicit solid color
<SettingsIcon className="w-4 h-4 text-gray-11" />
```

## Usage Patterns

### In Buttons

```typescript
<Button variant="transparent" iconOnly>
  <ChevronLeftIcon className="w-5 h-5" />
</Button>

<Button className="gap-2">
  <PlusIcon className="size-4" />
  Add Item
</Button>
```

### Status Indicators

```typescript
<CheckCircle2Icon className="h-4 w-4 text-green-10" />
<AlertTriangleIcon className="h-4 w-4 text-red-10" />
<ArrowDownCircleIcon className="h-4 w-4 text-blue-10" />
```

### Loading States

```typescript
<Loader2Icon className="w-5 h-5 animate-spin text-blue-10" />
```

### Hover States

```typescript
<ImagePlusIcon className="size-4 text-gray-9 hover:text-gray-11 transition-colors" />
```

## Checklist

- [ ] Icons imported from `lucide-react` with `Icon` suffix
- [ ] Sized with Tailwind `w-*`/`h-*` or `size-*` utilities
- [ ] **Explicit solid color on every icon** (e.g., `text-gray-11`, NOT `text-gray-a11`)
- [ ] **Never rely on inherited text color** — the default is semi-transparent
- [ ] No direct `color`, `fill`, or `stroke` props — use `className` only
