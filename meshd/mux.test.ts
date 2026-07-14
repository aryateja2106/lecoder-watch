// Guards the meshd agentOutput capture command. Before the fix it was
// `capture-pane -p -t <target>`, which only ever returns the visible viewport,
// so ?lines=N could never reach real scrollback. `-S -` is the fix: capture
// from the start of history. These tests lock in the flag and its arg order
// (`-S`'s value must be `-`, not the target) without booting the daemon.
import { describe, expect, test } from "bun:test";
import { captureCmd } from "./mux";

describe("captureCmd (meshd agentOutput)", () => {
  test("captures from the start of history with -S -", () => {
    expect(captureCmd("rmux", "'agent-1'")).toContain("-S -");
  });

  test("-S takes `-` as its value, then targets the pane (order preserved)", () => {
    // If -S consumed the target instead of `-`, this substring would not match.
    expect(captureCmd("tmux", "'agent-1'")).toContain("-S - -t 'agent-1'");
  });

  test("keeps -p and prefixes the configured multiplexer", () => {
    const cmd = captureCmd("tmux", "'sess'");
    expect(cmd.startsWith("tmux capture-pane -p ")).toBe(true);
  });
});
