// Typed client for the meshd routes the coding agent needs. Dependency-free, like the
// rest of the payload. Everything the agent does to a machine goes through here, so the
// work stays visible from the phone and the watch instead of happening in a hidden
// subprocess.

export type MeshdConfig = {
  base: string;
  token: string;
  timeoutMs: number;
};

export function configFromEnv(overrides: Partial<MeshdConfig> = {}): MeshdConfig {
  const host = process.env.MESHD_HOST_URL ?? "http://127.0.0.1:8899";
  return {
    base: (overrides.base ?? host).replace(/\/$/, ""),
    token: overrides.token ?? process.env.MESHD_TOKEN ?? "",
    timeoutMs: overrides.timeoutMs ?? 20000,
  };
}

export class MeshdError extends Error {
  constructor(
    message: string,
    readonly status: number | null,
  ) {
    super(message);
    this.name = "MeshdError";
  }
}

export class Meshd {
  constructor(private cfg: MeshdConfig) {}

  private headers(): Record<string, string> {
    const h: Record<string, string> = { "content-type": "application/json" };
    // Loopback is exempt daemon-side, but sending the token anyway means the same
    // client works unchanged against another machine in the mesh.
    if (this.cfg.token) h.authorization = `Bearer ${this.cfg.token}`;
    return h;
  }

  private async request(path: string, init?: RequestInit, timeoutMs?: number): Promise<any> {
    let res: Response;
    try {
      res = await fetch(`${this.cfg.base}${path}`, {
        ...init,
        headers: { ...this.headers(), ...(init?.headers as Record<string, string> | undefined) },
        signal: AbortSignal.timeout(timeoutMs ?? this.cfg.timeoutMs),
      });
    } catch (err) {
      throw new MeshdError(
        `cannot reach meshd at ${this.cfg.base}: ${err instanceof Error ? err.message : String(err)}`,
        null,
      );
    }
    const text = await res.text();
    if (!res.ok) throw new MeshdError(`${path} -> HTTP ${res.status}: ${text.slice(0, 200)}`, res.status);
    try {
      return JSON.parse(text);
    } catch {
      return text;
    }
  }

  health(): Promise<any> {
    return this.request("/health");
  }

  /** Capability strings gate every new behaviour — never the version. See AGENTS.md rule 6. */
  async capabilities(): Promise<string[]> {
    const h = await this.health();
    return Array.isArray(h?.capabilities) ? h.capabilities : [];
  }

  brain(query = ""): Promise<any> {
    return this.request(`/brain${query}`);
  }

  agents(): Promise<any> {
    return this.request("/agents");
  }

  newSession(opts: { name: string; cwd?: string; cmd?: string; initialText?: string }): Promise<any> {
    return this.request("/agents/new", { method: "POST", body: JSON.stringify(opts) });
  }

  killSession(name: string): Promise<any> {
    return this.request(`/agents/${encodeURIComponent(name)}`, { method: "DELETE" });
  }

  /** Pane text only — the VISIBLE pane. Never use this to collect command output. */
  async output(name: string, lines = 60): Promise<string[]> {
    const r = await this.request(`/agents/${encodeURIComponent(name)}/output?lines=${lines}`);
    if (Array.isArray(r?.lines)) return r.lines;
    return typeof r?.lines === "string" ? r.lines.split("\n") : [];
  }

  /** Types text WITHOUT running it. A second call with key "enter" runs it. */
  sendText(name: string, text: string): Promise<any> {
    return this.request(`/agents/${encodeURIComponent(name)}/send`, {
      method: "POST",
      body: JSON.stringify({ text }),
    });
  }

  sendKey(name: string, key: string): Promise<any> {
    return this.request(`/agents/${encodeURIComponent(name)}/send`, {
      method: "POST",
      body: JSON.stringify({ key }),
    });
  }

  /** Truncates at 64KB keeping the HEAD, so callers must bound the file themselves. */
  async readFile(path: string): Promise<{ text: string; truncated: boolean }> {
    const r = await this.request(`/fs/read?path=${encodeURIComponent(path)}`);
    return { text: String(r?.text ?? ""), truncated: Boolean(r?.truncated) };
  }
}
