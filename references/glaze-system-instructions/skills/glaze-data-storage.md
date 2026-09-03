---
name: glaze-data-storage
description: Patterns and best practices for persisting data in Glaze apps using the two-tier storage model.
---

# Glaze Data Storage

This skill guides you in implementing data persistence for Glaze apps using the correct storage patterns.

## Two-Tier Persistence Model

Glaze apps use **two storage tiers**:

- **localStorage** (frontend) - UI state only
- **JSON files in Application Support** (backend) - App data

---

## CRITICAL: Never Store Data in Repository

```
❌ NEVER use process.cwd() for persistent data
❌ NEVER use path.join(__dirname, '..', 'data.json')
❌ NEVER store in .glaze_memory/ or any repository-relative path
❌ NEVER hardcode paths like /Users/xxx/Dev/...
❌ NEVER store data alongside source code

✅ ALWAYS use app.getPath("userData") for persistent storage
✅ ALWAYS create directory before first write (mkdir recursive)
✅ ALWAYS handle missing file gracefully (return defaults)
```

---

## Storage Decision Tree

```
Is this UI layout state (panel sizes, selected tabs, filters)?
├─ Yes → localStorage (frontend)
└─ No → Does data need to persist across app updates?
    ├─ No → In-memory (React state)
    └─ Yes → Is data relational with complex queries OR 10k+ records?
        ├─ No → JSON files in Application Support (default)
        └─ Yes → Consider SQLite
```

---

## 1. localStorage - UI State (Frontend)

**Use for:** Panel sizes, sidebar widths, selected tabs, filter selections, sort order.

```typescript
// renderer/main/home-view.tsx
localStorage.setItem("sidebar-width", "280");
localStorage.setItem("selected-tab", "history");

// Load with defaults
const sidebarWidth = localStorage.getItem("sidebar-width") ?? "250";
```

**Why localStorage:** Zero IPC overhead, instant, survives app restarts.

---

## 2. JSON Files - App Data (Backend, Default)

**Use for:** User settings, user-created content, saved items, history, cached API data.

**Location:** `~/Library/Application Support/<BUNDLE_ID>/`

```typescript
// main/services/settings.ts
import { app } from "@glaze/core/backend";
import fs from "fs/promises";
import path from "path";

class SettingsService {
  private cache: Record<string, unknown> = {};
  private settingsPath: string | null = null;

  private async getSettingsPath(): Promise<string> {
    if (!this.settingsPath) {
      const userDataPath = await app.getPath("userData");
      await fs.mkdir(userDataPath, { recursive: true });
      this.settingsPath = path.join(userDataPath, "settings.json");
    }
    return this.settingsPath;
  }

  async load(): Promise<void> {
    try {
      const filePath = await this.getSettingsPath();
      const data = await fs.readFile(filePath, "utf-8");
      this.cache = JSON.parse(data);
    } catch {
      this.cache = {}; // File doesn't exist yet - that's OK
    }
  }

  async get<T>(key: string, defaultValue?: T): Promise<T | undefined> {
    return (this.cache[key] as T) ?? defaultValue;
  }

  async set(key: string, value: unknown): Promise<void> {
    this.cache[key] = value;
    const filePath = await this.getSettingsPath();
    await fs.writeFile(filePath, JSON.stringify(this.cache, null, 2));
  }
}

export const settingsService = new SettingsService();
```

---

## 3. safeStorage - Secrets (Backend)

**Use for:** API keys, tokens, or secrets that should never be stored in plaintext.

```typescript
import { app, safeStorage } from "@glaze/core/backend";
import fs from "fs/promises";
import path from "path";

const userDataPath = await app.getPath("userData");
const secretsPath = path.join(userDataPath, "secrets.bin");
const encrypted = await safeStorage.encryptString("my-api-key");
await fs.writeFile(secretsPath, encrypted);

const decrypted = await safeStorage.decryptString(await fs.readFile(secretsPath));
```

---

## Reusable DataStore Pattern

For apps with multiple data types, use a generic store:

```typescript
// main/services/data-store.ts
import { app } from "@glaze/core/backend";
import fs from "fs/promises";
import path from "path";

export class DataStore<T> {
  private cache: T | null = null;
  private filePath: string | null = null;

  constructor(
    private filename: string,
    private defaultValue: T,
  ) {}

  private async getFilePath(): Promise<string> {
    if (!this.filePath) {
      const userDataPath = await app.getPath("userData");
      await fs.mkdir(userDataPath, { recursive: true });
      this.filePath = path.join(userDataPath, this.filename);
    }
    return this.filePath;
  }

  async load(): Promise<T> {
    if (this.cache !== null) return this.cache;
    try {
      const filePath = await this.getFilePath();
      const data = await fs.readFile(filePath, "utf-8");
      this.cache = JSON.parse(data);
      return this.cache!;
    } catch {
      this.cache = this.defaultValue;
      return this.cache;
    }
  }

  async save(data: T): Promise<void> {
    this.cache = data;
    const filePath = await this.getFilePath();
    await fs.writeFile(filePath, JSON.stringify(data, null, 2));
  }
}

// Usage examples
export const settingsStore = new DataStore("settings.json", {});
export const notesStore = new DataStore<Note[]>("notes.json", []);
export const historyStore = new DataStore<HistoryItem[]>("history.json", []);
```

---

## SQLite - When Needed

**Consider SQLite only when:**

- App has relational data with complex queries (joins, aggregations)
- Data could grow to 10,000+ records
- Need full-text search across large datasets
- Multiple data types with relationships (projects → tasks → comments)

**Stick with JSON when:**

- Simple key-value settings
- Linear lists (todos, notes, history items)
- Data under a few thousand records
- No complex querying needs

**Note:** SQLite requires bundling native bindings with `copyNativeBindings` plugin.

---

## Data Categories Summary

| Data Type                   | Storage            | Location                 |
| --------------------------- | ------------------ | ------------------------ |
| Panel sizes, UI layout      | localStorage       | Browser                  |
| Selected tabs, filters      | localStorage       | Browser                  |
| User settings/config        | JSON file          | `userData/settings.json` |
| User content (notes, todos) | JSON file          | `userData/data.json`     |
| History, favorites          | JSON file          | `userData/history.json`  |
| Secrets (API keys, tokens)  | safeStorage + file | `userData/secrets.bin`   |
| Large relational data       | SQLite             | `userData/app.db`        |

---

## File Organization

```
~/Library/Application Support/<BUNDLE_ID>/
├── settings.json      # App configuration
├── data.json          # Primary app data
├── history.json       # User history/activity
└── cache/             # Optional: cached API responses
    └── api-cache.json
```

---

## Quick Checklist

Before implementing data storage:

- [ ] Using `app.getPath("userData")` for all persistent data
- [ ] Creating directory with `mkdir({ recursive: true })` before writes
- [ ] Handling missing files gracefully with defaults
- [ ] Using localStorage only for UI state (panel sizes, tabs, filters)
- [ ] Using JSON files for app data (settings, content, history)
- [ ] Using safeStorage for any secrets/API keys
- [ ] NOT storing anything in the repository directory

**When stuck:** Refer to the Storage Decision Tree above.
