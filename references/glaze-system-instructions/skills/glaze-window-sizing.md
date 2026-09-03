---
name: glaze-window-sizing
description: Chooses window width, height, and minimum dimensions for a Glaze BrowserWindow based on the app's layout and content. Use when creating a new Glaze app, scaffolding from the template, adding a BrowserWindow, or configuring windowWidth, windowHeight, minWidth, or minHeight in main/index.ts.
---

# Glaze Window Sizing

This skill provides guidance for choosing appropriate window dimensions for Glaze applications.

## Configuration Location

Window size is configured in `main/index.ts` via `windowWidth` and `windowHeight` constants.

```typescript
// main/index.ts
const windowWidth = 800;
const windowHeight = 650;
```

## Minimum Size Defaults

Minimum size defaults should be defined in `main/index.ts` and applied to the main window by default.

```typescript
import { BrowserWindow } from "@glaze/core/backend";

const minWindowWidth = 390;
const minWindowHeight = 456;

const window = new BrowserWindow({
  windowKey: "main",
  width: 1000,
  height: 700,
  minWidth: minWindowWidth,
  minHeight: minWindowHeight,
});
```

- Use `390x456` as the default minimum size for the main window and new windows unless there is a strong reason to override.
- Keep existing windows with intentional custom `minWidth` / `minHeight` unchanged.
- If a window must use a different min size, document why near that window creation code.

## Constraints

- **Maximum height: 850px** (enforced automatically)
- **Minimum recommended: 400x300** for usability
- Window should fit all primary content without scrolling

## Size Selection Guide

- Content density: simple single-view apps need less space than multi-panel layouts
- Layout complexity: source list + detail view needs wider window than single column
- Data display: tables/spreadsheets need more width; lists can be narrower
- User workflow: consider if users need to see multiple panels simultaneously
- **Avoid scrolling: window should be large enough to display all primary content without vertical or horizontal scrolling**

## Common Patterns

### Notes App (Two-Column)

```typescript
const windowWidth = 800;
const windowHeight = 650;
```

- Sidebar: ~250px for note list
- Main: ~550px for note content
- Height: Comfortable for editing

### Settings Panel (Single View)

```typescript
const windowWidth = 520;
const windowHeight = 600;
```

- Narrow: Settings don't need width
- Tall enough for common settings

### File Browser (Three-Column)

```typescript
const windowWidth = 1000;
const windowHeight = 700;
```

- Nav sidebar: ~200px
- File list: ~300px
- Preview: ~500px

### Dashboard (Data-Heavy)

```typescript
const windowWidth = 1000;
const windowHeight = 800;
```

- Maximum width for charts/tables
- Near-maximum height for data density

## Common Mistakes

### Wrong: Same size for every app

```typescript
// DON'T DO THIS
const windowWidth = 1000; // Always 1000
const windowHeight = 700; // Always 700
```

### Right: Size based on content

```typescript
// DO THIS - Size matches content needs
// For a simple timer app:
const windowWidth = 400;
const windowHeight = 300;

// For a complex data app:
const windowWidth = 1000;
const windowHeight = 800;
```

### Wrong: Exceeding max height

```typescript
// DON'T DO THIS - Will be clamped to 850
const windowHeight = 900;
```

### Right: Respect constraints

```typescript
// DO THIS
const windowHeight = 850; // Maximum allowed
```
