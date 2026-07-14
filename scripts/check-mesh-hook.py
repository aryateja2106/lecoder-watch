#!/usr/bin/env python3
import json
import os
import subprocess

# Resolve payload paths from this file's location, not the caller's cwd, so the
# check runs from anywhere (repo root, /tmp, a CI checkout dir, ...).
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAYLOAD = os.path.join(REPO_ROOT, "install", "payload")


def bin_path(name):
    return os.path.join(PAYLOAD, "bin", name)


def run(source, payload):
    proc = subprocess.run(
        ["python3", bin_path("mesh-hook"), "--source", source, "--dry-run"],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(proc.stdout)


def run_event(*args, env=None):
    env = env or os.environ.copy()
    env["MESH_HOME"] = PAYLOAD
    proc = subprocess.run(
        ["sh", bin_path("mesh-event"), "--dry-run", *args],
        text=True,
        capture_output=True,
        check=True,
        env=env,
    )
    return json.loads(proc.stdout)


def run_shell(*args):
    env = os.environ.copy()
    env["MESH_HOME"] = PAYLOAD
    proc = subprocess.run(
        list(args),
        text=True,
        capture_output=True,
        check=True,
        env=env,
    )
    return [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]


claude_notification = run("claude", {"hook_event_name": "Notification", "message": "needs input"})
assert claude_notification["title"] == "Claude needs attention"
assert claude_notification["level"] == "warning"
assert run("claude", {"hook_event_name": "Stop", "message": "done"})["title"] == "Claude stopped"
assert run("codex", {"event": "turn-ended", "title": "Codex waiting"})["title"] == "Codex waiting"
assert run("pi", {"event": "thermal", "body": "hot"})["title"] == "Pi: thermal"
assert run("codex", {"title": "Codex waiting for approval"})["level"] == "warning"
assert run("pi", {"event": "thermal", "body": "hot"})["level"] == "warning"
assert run("codex", {"title": "Failed", "body": "command failed"})["level"] == "error"

direct_event = run_event("pi", "Thermal warning", "hot")
assert direct_event["source"] == "pi"
assert direct_event["title"] == "Thermal warning"
assert direct_event["body"] == "hot"
assert direct_event["level"] == "info"

codex_notify = run_shell("sh", bin_path("mesh-codex-notify"), "--dry-run", "turn-ended")
assert codex_notify[0]["source"] == "codex"
assert codex_notify[0]["title"] == "Codex turn ended"

agent_run = run_shell("sh", bin_path("mesh-agent-run"), "--dry-run", "claude", "claude")
assert agent_run[0]["title"] == "Started"
assert agent_run[1]["title"] == "Completed"
