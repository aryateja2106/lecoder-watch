// Command builder for meshd's agentOutput path. Factored out of server.ts so
// the arg list is unit-testable without booting the daemon (server.ts binds a
// port at import). The critical flag is `-S -`: it starts the capture at the
// very beginning of the pane's history instead of the visible viewport, so
// GET /agents/:name/output?lines=N can return real scrollback. The caller
// still slices to the last N lines as the size cap, keeping responses bounded.
// `-p` prints to stdout; `target` is expected to be already shell-quoted.
export function captureCmd(mux: string, target: string): string {
  return `${mux} capture-pane -p -S - -t ${target} 2>/dev/null`;
}
