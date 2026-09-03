---
name: glaze-external-api
description: Patterns and best practices for integrating external APIs in Glaze apps.
---

# Glaze External API Integration

This skill guides you in integrating external APIs in Glaze apps.

---

## Core Rules

1. **Never hardcode IDs** — Make them configurable via settings
2. **Test endpoints first** — Use curl before wiring up UI
3. **Transform at the boundary** — Don't pass raw API responses to components
4. **Show specific errors** — Include status codes in error messages
5. **Match IPC shapes exactly** — Parameter types must align between frontend and backend

---

## API Integration Pattern

### Backend: Create a Service

```typescript
// main/services/github-service.ts
import { settingsService } from "./settings";

interface GitHubRepo {
  id: number;
  name: string;
  full_name: string;
  description: string | null;
}

// Internal API response shape
interface GitHubRepoResponse {
  id: number;
  name: string;
  full_name: string;
  description: string | null;
  // ... many other fields we don't need
}

class GitHubService {
  private async getToken(): Promise<string> {
    const token = await settingsService.get<string>("github_token");
    if (!token) throw new Error("GitHub token not configured");
    return token;
  }

  async listRepos(): Promise<GitHubRepo[]> {
    const token = await this.getToken();

    const response = await fetch("https://api.github.com/user/repos", {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github.v3+json",
      },
    });

    if (!response.ok) {
      throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
    }

    const data: GitHubRepoResponse[] = await response.json();

    // ✅ Transform at the boundary - only return what UI needs
    return data.map((repo) => ({
      id: repo.id,
      name: repo.name,
      full_name: repo.full_name,
      description: repo.description,
    }));
  }
}

export const githubService = new GitHubService();
```

### Backend: Register IPC Handler

```typescript
// main/handlers/github.ts
import { ipcMain } from "@glaze/core/backend";
import { githubService } from "../services/github-service";

ipcMain.handle("github:listRepos", async () => {
  return githubService.listRepos();
});
```

### Frontend: Call via IPC

```typescript
// renderer/main/repos-view.tsx
const { data, isLoading, error } = useQuery({
  queryKey: ["github", "repos"],
  queryFn: () => window.glazeAPI.glaze.ipc.invoke("github:listRepos"),
});

if (error) {
  // ✅ Show specific error message
  return <ErrorView message={error.message} />;
}
```

---

## Configuration Pattern

Never hardcode API keys, IDs, or endpoints:

```typescript
// ❌ Bad: Hardcoded values
const POSTHOG_KEY = "phc_abc123";
const API_URL = "https://api.myservice.com";

// ✅ Good: Configurable via settings
const posthogKey = await settingsService.get<string>("posthog_key");
const apiUrl = await settingsService.get<string>("api_url", "https://api.myservice.com");
```

For secrets (API keys, tokens), use safeStorage:

```typescript
import { safeStorage } from "@glaze/core/backend";

// Store encrypted
const encrypted = await safeStorage.encryptString(apiKey);
await fs.writeFile(secretsPath, encrypted);

// Retrieve decrypted
const decrypted = await safeStorage.decryptString(await fs.readFile(secretsPath));
```

---

## Error Handling Pattern

Always include status codes and meaningful messages:

```typescript
// main/services/api-service.ts
async function apiRequest<T>(url: string, options?: RequestInit): Promise<T> {
  const response = await fetch(url, options);

  if (!response.ok) {
    // ✅ Include status code in error
    const errorBody = await response.text().catch(() => "");
    throw new Error(
      `API request failed: ${response.status} ${response.statusText}${errorBody ? ` - ${errorBody}` : ""}`,
    );
  }

  return response.json();
}
```

---

## Testing API Endpoints

Before wiring up UI, test with curl:

```bash
# Test endpoint works
curl -X GET "https://api.github.com/user/repos" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/vnd.github.v3+json"

# Check response shape matches your types
curl ... | jq 'keys'  # See available fields
```

---

## Data Transformation

Transform API responses at the service boundary:

```typescript
// ❌ Bad: Passing raw API response to frontend
ipcMain.handle("api:getData", async () => {
  const response = await fetch(url);
  return response.json(); // Raw, untyped, potentially huge
});

// ✅ Good: Transform and type at the boundary
ipcMain.handle("api:getData", async () => {
  const response = await fetch(url);
  const raw = await response.json();

  // Return only what the UI needs, properly typed
  return {
    id: raw.id,
    title: raw.title,
    createdAt: new Date(raw.created_at).toISOString(),
  };
});
```

---

## Quick Checklist

Before integrating an external API:

- [ ] API keys/IDs are configurable via settings (not hardcoded)
- [ ] Secrets stored using safeStorage
- [ ] Tested endpoint with curl first
- [ ] Service transforms data at the boundary
- [ ] Error messages include status codes
- [ ] IPC parameter shapes match between frontend and backend
- [ ] Only returning data the UI actually needs

**When stuck:** Test the API with curl first, then implement the service.

---

## AI / LLM Integrations

When a user requests AI/LLM functionality, use the [Vercel AI SDK](https://ai-sdk.dev/) (`npm install --include=dev ai`) instead of provider-specific SDKs. It provides a unified `generateText` / `streamText` API across OpenAI, Anthropic, Google, and others — switching providers is a one-line import change. Only use provider-specific SDKs if the user explicitly asks for it.

Provider packages: `@ai-sdk/openai`, `@ai-sdk/anthropic`, `@ai-sdk/google`.
