---
name: glaze-app-lifecycle
description: Patterns for quitting apps, menubar apps, and graceful shutdown
---

# App Lifecycle Patterns

Guidelines for managing macOS app lifecycle, quit behavior, and menubar apps.

## Quitting the App

**CRITICAL**: Use the correct method to terminate your app:

| Method        | Effect                      | Use When                 |
| ------------- | --------------------------- | ------------------------ |
| `app.quit()`  | Only exits Node.js backend  | Restarting backend only  |
| `app.exit(0)` | Terminates entire macOS app | User wants to fully quit |

### Common Mistake

```typescript
// WRONG - leaves native shell running
// For menubar apps, dock icon may reappear when reopened
app.quit();

// CORRECT - fully terminates the macOS app
app.exit(0);
```

### Implementation Pattern

```typescript
import { app } from "@glaze/core/backend";

// In your menu or quit handler:
function handleQuit() {
  // Perform any cleanup first
  saveState();

  // Fully terminate the app
  app.exit(0);
}
```

## Menubar Apps (LSUIElement)

For apps that run in the menu bar with a hidden dock icon:

### Key Points

- Dock icon is hidden via `LSUIElement=true` in Info.plist
- **Always use `app.exit(0)` for quit actions** - using `app.quit()` causes:
  - App not fully terminating
  - Dock icon incorrectly appearing when app is re-opened
  - Zombie processes

### Dock Icon Shows on Re-activate

**Problem**: Clicking "Open app" while running shows dock icon unexpectedly.

**Cause**: macOS shows dock on activate, but `app.dock.hide()` is only called at startup.

**Solution**: Call `app.dock.hide()` in the `activate` event handler too:

```typescript
import { app } from "@glaze/core/backend";

app.on("activate", async () => {
  await app.dock.hide(); // Keep dock hidden on re-activate
});
```

### Tray Menu Quit Handler

```typescript
import { app, Tray, Menu } from "@glaze/core/backend";

const tray = new Tray(iconPath);
const contextMenu = Menu.buildFromTemplate([
  { label: "Settings", click: openSettings },
  { type: "separator" },
  {
    label: "Quit",
    click: () => app.exit(0), // NOT app.quit()
  },
]);
tray.setContextMenu(contextMenu);
```

## Graceful Shutdown

The app monitors for shutdown via multiple mechanisms:

| Signal               | Source                        |
| -------------------- | ----------------------------- |
| `SIGINT`             | Ctrl+C in terminal            |
| `SIGTERM`            | System shutdown               |
| `SIGQUIT`            | Quit request                  |
| `SIGHUP`             | Terminal hangup               |
| stdin closure        | Primary shutdown mechanism    |
| Parent process death | Reparented to launchd (PID 1) |

**Timeout**: 5 seconds before force termination.

### Handling Shutdown Events

```typescript
import { app } from "@glaze/core/backend";

app.on("before-quit", () => {
  // Save state, close connections
  saveApplicationState();
});

app.on("will-quit", () => {
  // Final cleanup
  cleanupResources();
});
```

## Checklist

Before implementing quit/exit functionality:

- [ ] Using `app.exit(0)` for user-initiated quit (not `app.quit()`)
- [ ] Menubar apps always use `app.exit(0)` in tray menu
- [ ] Cleanup code in `before-quit` or `will-quit` handlers
- [ ] No blocking operations in quit handlers (5s timeout)
