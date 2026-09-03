# Common Tasks → GLAZE-APP-GUIDE.md Sections

| Task                   | See Section                                             |
| ---------------------- | ------------------------------------------------------- |
| Add IPC handler        | "Adding New Backend Handlers"                           |
| Create window          | "Window Management (BrowserWindow)"                     |
| Add route              | "Key Files" → router.tsx                                |
| Use native dialogs     | "Native macOS Integration"                              |
| Add notifications      | "System Notifications (Notification API)"               |
| Add global shortcut    | "Global Shortcuts"                                      |
| Add system tray        | "System Tray"                                           |
| Customize components   | "renderer/shared/ Components"                           |
| Add setting/preference | Settings window (`renderer/settings/settings-view.tsx`) |

**Settings Convention:** When the user asks to add a "setting" or "preference", always place it in the app's Settings window (`renderer/settings/settings-view.tsx`), not inline in the main UI. The template includes a dedicated Settings window accessible via Cmd+, (Preferences menu item). Only put settings inline in the main view if the user explicitly requests it.

**Cross-window sync:** The Settings window and main window are separate BrowserWindow instances with separate React trees. Saving a setting in the backend does NOT automatically update the main window. You MUST broadcast changes so the main window reacts in real-time:

- **Backend handler:** after saving, call `ipcMain.broadcast("settings:foo-changed", { value })` to push the change to all windows
- **Main window:** listen with `window.glazeAPI.glaze.ipc.onNotification("settings:foo-changed", callback)` and update the React Query cache via `queryClient.setQueryData()`
- Without this, settings only take effect after restarting the app or closing the Settings window.
