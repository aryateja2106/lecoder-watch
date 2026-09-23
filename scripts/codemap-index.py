#!/usr/bin/env python3
"""codemap-index.py — generate the committed codebase map from the tree itself.

Writes three files under docs/agents/ that an agent reads INSTEAD of opening source:

  CODEMAP.md    every code file with its purpose (the file's own header comment), a
                size bucket, and the self-checks that name it. "Which file?"
  CONTRACTS.md  the daemon route table, the capability strings and where each is
                gated, and the watch->phone relay command set. "What talks to what?"
  CHECKS.md     what every scripts/ file proves, one line each. "What does check-x pin?"
  SYMBOLS.md    every top-level declaration -> file:line, sorted. Grep it, never read it.

Deterministic on purpose: no dates, no commit SHAs, sizes are buckets. The output only
changes when a file, a header line, a declaration, a route or a capability changes, so
`scripts/check-codemap.sh` can diff it and go red exactly when the map is stale.

Purpose lines come from the first comment at the top of each file — the same convention
the daemon and the shell scripts already follow (`// pair.ts — bring a phone onto the
mesh…`). A code file without one is reported and, under --check, fails: the file itself
is the single source of truth for what it is.

Usage:  python3 scripts/codemap-index.py          # rewrite docs/agents/{CODEMAP,CONTRACTS,CHECKS,SYMBOLS}.md
        python3 scripts/codemap-index.py --check  # exit 1 if committed files differ or a purpose is missing

Stdlib only; no graphify or codegraph needed, so CI and a fresh clone can run it.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "agents")

# Area order and the one-line description that does not change with the code.
AREAS = [
    ("Shared", "Wire types and pure logic both apps compile; the self-checks link against these"),
    ("iOS", "iPhone app: machine list, terminal, remote screen, pairing, relay to the watch"),
    ("Watch", "Watch app: attention list, terminal, remote control; talks to meshd or via the phone"),
    ("MeshDesktop", "Mac menu-bar app: daemon status, permissions window, pairing QR. Copies its wire types"),
    ("MeshWatchWidgets", "iOS Live Activity: Lock Screen, Dynamic Island, Smart Stack"),
    ("WatchWidgets", "Watch complication reading the shared App Group glance"),
    ("install/payload/meshd", "The daemon (bun + TypeScript). The ONE shipping copy; server.ts is the route table"),
    ("install/payload/bin", "The mesh CLI and the helper binaries installed to ~/.mesh/bin"),
    ("install/payload/hooks", "Agent hook scripts registered into Claude Code / Codex"),
    ("install/payload/rmux-bridge", "Second daemon on :7820 serving the phone's xterm.js terminal"),
    ("install", "The installer the one-liner fetches; runs on macOS and Linux"),
    ("web", "Landing page (mesh.lesearch.ai) and the privacy page"),
    ("scripts", "Self-checks (check-*), gates (gate-*), release and map tooling"),
]

# Policy from AGENTS.md: these are edited by one agent at a time.
SERIALIZED = {
    "Shared/Models.swift": "serialized — every wire type incl. WatchCommand",
    "Shared/MeshClient.swift": "serialized — every endpoint call",
    "install/payload/meshd/server.ts": "serialized — the route table",
    "install/payload/meshd/auth.ts": "serialized — auth",
    "install/payload/meshd/pair.ts": "serialized — pairing and tokens",
    "project.yml": "serialized",
}

CODE_EXT = (".swift", ".ts", ".sh", ".py", ".js", ".html")
NAMED_CHECK = re.compile(r"scripts/(check-[a-z0-9-]+)\.(sh|swift|py)$")


def git_files():
    out = subprocess.check_output(["git", "-C", ROOT, "ls-files"], text=True)
    return [p for p in out.splitlines() if p]


def area_of(path):
    best = None
    for name, _ in AREAS:
        if path.startswith(name + "/") and (best is None or len(name) > len(best)):
            best = name
    return best


def is_code(path):
    if path.endswith(CODE_EXT):
        return True
    # bun-run scripts without an extension (install/payload/bin/mesh, mesh-kb, …)
    return path.startswith("install/payload/bin/") and "." not in os.path.basename(path)


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8", errors="replace") as f:
        return f.read()


def purpose_of(path, text):
    """The file's first comment paragraph, minus the marker and a leading 'name — ', cut to
    one sentence. Language-aware: `#` is not a comment in Swift, `//` is not one in sh."""
    name = os.path.basename(path)
    if path.endswith((".swift", ".ts", ".js")) or text.startswith("#!/usr/bin/env bun"):
        marker = r"(///|//|/\*\*?|\*)"
    elif path.endswith(".py") or text.startswith("#!/usr/bin/env python"):
        marker = r"(#|\"\"\")"
    elif path.endswith(".html"):
        marker = r"(<!--)"
    else:
        marker = r"(#)"
    rx = re.compile(r"^" + marker + r"\s?(.*)$")
    para = []
    for raw in text.splitlines()[:40]:
        line = raw.strip()
        if not para:
            if not line or line.startswith("#!") or line.startswith("import ") or line.startswith("@testable"):
                continue
            if line.startswith("// MARK:"):
                return ""
        m = rx.match(line)
        if not m:
            break  # code (or a blank line) ends the header paragraph
        body = m.group(2).strip()
        if body.endswith("*/") or body.endswith("-->"):
            body = body[:-2].rstrip("-").strip()
        if not body:
            if para:
                break
            continue
        para.append(body)
        if len(" ".join(para)) > 400:
            break
    if not para:
        return ""
    body = " ".join(para)
    body = re.sub(r"^" + re.escape(name) + r"\s*(—|-|:)\s*", "", body)
    body = re.sub(r"^" + re.escape(name.split(".")[0]) + r"\s*(—|-|:)\s*", "", body)
    body = body.strip('"').strip()
    cut = re.search(r"[.;!?](\s|$)", body)
    if cut and cut.start() > 30:
        body = body[: cut.start()]
    if len(body) > 160:
        body = body[:160].rsplit(" ", 1)[0] + "…"
    return body


def bucket(lines):
    return "S" if lines < 200 else "M" if lines < 600 else "L" if lines < 1200 else "XL"


SWIFT_DECL = re.compile(
    r"^(?:@main\s+)?(?:(?:public|private|fileprivate|internal|final|indirect|open)\s+)*"
    r"(struct|class|enum|actor|protocol|extension|func)\s+([A-Za-z_][A-Za-z0-9_]*)"
)
TS_DECL = re.compile(
    r"^export\s+(?:default\s+)?(?:(async)\s+)?(function|const|let|type|interface|class|enum)\s+([A-Za-z_$][A-Za-z0-9_$]*)"
)
TS_BARE_FN = re.compile(r"^(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)")


def symbols_of(path, text):
    syms = []
    is_bun = text.startswith("#!/usr/bin/env bun")
    for n, line in enumerate(text.splitlines(), 1):
        if path.endswith(".swift"):
            m = SWIFT_DECL.match(line)
            if m:
                syms.append((m.group(2), m.group(1), n))
        elif path.endswith(".ts") or is_bun:
            m = TS_DECL.match(line)
            if m:
                kind = m.group(2)
                if kind in ("const", "let"):
                    kind = "export"
                syms.append((m.group(3), kind, n))
            elif is_bun:
                m = TS_BARE_FN.match(line)
                if m:
                    syms.append((m.group(1), "function", n))
    return syms


# --- routes -------------------------------------------------------------------------
ROUTE_EQ = re.compile(r"""(?:path|url\.pathname)\s*===\s*"([^"]+)"[^;{]*?req\.method\s*===\s*"([A-Z]+)"(?:\s*\|\|\s*req\.method\s*===\s*"([A-Z]+)")?""")
ROUTE_EQ_MULTI = re.compile(r"""(?:path|url\.pathname)\s*===\s*"([^"]+)"\s*&&\s*\((?:req\.method\s*===\s*"([A-Z]+)"\s*\|\|\s*)+req\.method\s*===\s*"([A-Z]+)"\)""")
ROUTE_ANY = re.compile(r"""if\s*\(\s*(?:path|url\.pathname)\s*===\s*"([^"]+)"\s*\)""")
ROUTE_PREFIX = re.compile(r"""(?:path|url\.pathname)\.startsWith\("([^"]+)"\)[^;{]*?req\.method\s*===\s*"([A-Z]+)\"""")
MATCH_VAR = re.compile(r"""const\s+([A-Za-z_]+)\s*=\s*(?:path|url\.pathname)\.match\((/.*/)\)""")
MATCH_USE = re.compile(r"""\b([A-Za-z_]+)\s*&&\s*req\.method\s*===\s*"([A-Z]+)\"""")
INLINE_MATCH = re.compile(r"""(?:path|url\.pathname)\.match\((/.*/)\)""")
METHOD_NEAR = re.compile(r"""req\.method\s*===\s*"([A-Z]+)\"""")


def regex_to_path(rx):
    r"""Turn /^\/agents\/([^/]+)\/panes$/ into /agents/:name/panes for humans."""
    s = rx.strip("/").lstrip("^").rstrip("$")
    s = s.replace("\\/", "/")
    s = re.sub(r"\([^)]*\)\?", "…", s)
    s = re.sub(r"\([^)]*\)", ":x", s)
    return s


def routes_of(path, text):
    lines = text.splitlines()
    routes = []
    match_vars = {}
    for n, line in enumerate(lines, 1):
        m = MATCH_VAR.search(line)
        if m:
            match_vars[m.group(1)] = regex_to_path(m.group(2))
            continue
        m = ROUTE_EQ_MULTI.search(line)
        if m:
            methods = re.findall(r'req\.method\s*===\s*"([A-Z]+)"', line)
            for meth in methods:
                routes.append((meth, m.group(1), n))
            continue
        m = ROUTE_EQ.search(line)
        if m:
            routes.append((m.group(2), m.group(1), n))
            if m.group(3):
                routes.append((m.group(3), m.group(1), n))
            continue
        m = ROUTE_PREFIX.search(line)
        if m:
            routes.append((m.group(2), m.group(1) + "*", n))
            continue
        m = ROUTE_ANY.search(line)
        if m:
            routes.append(("ANY", m.group(1), n))
            continue
        m = MATCH_USE.search(line)
        if m and m.group(1) in match_vars:
            routes.append((m.group(2), match_vars[m.group(1)], n))
            continue
        m = INLINE_MATCH.search(line)
        if m and "const" in line:
            # `const p = url.pathname.match(...)` followed by `if (p && req.method === "X")`
            for k in range(n, min(n + 3, len(lines))):
                mm = METHOD_NEAR.search(lines[k])
                if mm:
                    routes.append((mm.group(1), regex_to_path(m.group(1)), n))
                    break
    return routes


def auth_tier(server_text, line_no):
    """Routes dispatched before the request handler's auth gate need no token."""
    gate = None
    for n, line in enumerate(server_text.splitlines(), 1):
        if re.search(r"if\s*\(\s*!authed\(", line):
            gate = n
            break
    if gate is None:
        return "?"
    return "none" if line_no < gate else "token"


def capabilities(server_text):
    m = re.search(r"const CAPABILITIES\s*=\s*\[([^\]]*)\]", server_text, re.S)
    return re.findall(r'"([A-Za-z]+)"', m.group(1)) if m else []


def watch_commands(models_text):
    """Cases of `enum WatchCommandKind` in Shared/Models.swift."""
    out = []
    inside = False
    depth = 0
    for line in models_text.splitlines():
        if re.match(r"^\s*(?:indirect\s+)?enum WatchCommandKind\b", line):
            inside = True
        if inside:
            depth += line.count("{") - line.count("}")
            m = re.match(r"^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)", line)
            if m:
                out.append(m.group(1))
            if depth <= 0 and "}" in line and inside and out:
                break
    return out


def check_map(files, texts):
    """check name -> set of repo files it names; inverted to file -> checks."""
    exists = set(files)
    path_rx = re.compile(
        r"(?:\$ROOT/|\./|\$PAYLOAD/|\$P/)?((?:Shared|iOS|Watch|MeshDesktop|MeshWatchWidgets|WatchWidgets|"
        r"install/payload/(?:meshd|bin|hooks|rmux-bridge)|install|web|scripts|meshd|bin|hooks|rmux-bridge)/"
        r"[A-Za-z0-9_./-]+)"
    )
    by_file = {}
    for path in files:
        m = NAMED_CHECK.match(path)
        if not m or path == "scripts/check-all.sh":
            continue
        name = m.group(1)
        for ref in path_rx.findall(texts.get(path, "")):
            ref = ref.rstrip(".")
            cands = [ref, "install/payload/" + ref]
            for c in cands:
                if c in exists and c != path:
                    by_file.setdefault(c, set()).add(name)
                    break
    return by_file


def md_escape(s):
    return s.replace("|", "\\|")


def build():
    files = git_files()
    texts = {}
    code_files = []
    for p in files:
        if area_of(p) and is_code(p) and not p.endswith(".html") or p in ("project.yml",):
            pass
        if area_of(p) and is_code(p):
            code_files.append(p)
            texts[p] = read(p)
        elif p.startswith("scripts/") and is_code(p):
            texts[p] = read(p)
    checks = check_map(files, texts)
    missing = []

    # ---------------- CODEMAP.md ----------------
    cm = []
    cm.append("# Codebase map")
    cm.append("")
    cm.append("*Generated by `python3 scripts/codemap-index.py` from the tree; do not edit. `scripts/check-codemap.sh` fails when this is stale.*")
    cm.append("")
    cm.append("Read this first, then open ONE file. Sizes: S <200 lines, M <600, L <1200, XL ≥1200.")
    cm.append("A file's purpose is its own first comment line; a missing one is a defect in the file, not here.")
    cm.append("")
    cm.append("- **Which symbol?** `grep -n '^| Name ' docs/agents/SYMBOLS.md` (or `codegraph explore <name>` for source + callers).")
    cm.append("- **Which route / capability / relay command?** [CONTRACTS.md](CONTRACTS.md).")
    cm.append("- **What proves my change?** the *checks* column: `sh scripts/<check>.sh`; what each check pins: [CHECKS.md](CHECKS.md); the whole gate: `./.claude/scripts/gates.sh fast`.")
    cm.append("- **Which tree is current?** `sh scripts/repo-status.sh`. **Why is it shaped this way?** [../../CONTEXT.md](../../CONTEXT.md), [../../MEMORY.md](../../MEMORY.md).")
    cm.append("")
    cm.append("## Areas")
    cm.append("")
    cm.append("| area | files | lines | what it is |")
    cm.append("|---|---|---|---|")
    per_area = {}
    for p in code_files:
        per_area.setdefault(area_of(p), []).append(p)
    for name, desc in AREAS:
        fl = per_area.get(name, [])
        if not fl:
            continue
        total = sum(texts[p].count("\n") + 1 for p in fl)
        approx = f"~{round(total, -2):,}"  # rounded so an ordinary edit does not stale the map
        link = " — see [CHECKS.md](CHECKS.md)" if name == "scripts" else ""
        cm.append(f"| `{name}/` | {len(fl)} | {approx} | {desc}{link} |")
    cm.append("")
    cm.append("Serialized files (one agent at a time, per AGENTS.md): " + ", ".join(f"`{p}`" for p in SERIALIZED) + ".")
    cm.append("")
    for name, desc in AREAS:
        fl = per_area.get(name, [])
        if not fl or name == "scripts":
            continue
        cm.append(f"## `{name}/`")
        cm.append("")
        cm.append("| file | size | purpose | checks |")
        cm.append("|---|---|---|---|")
        for p in sorted(fl):
            text = texts[p]
            n = text.count("\n") + 1
            purpose = purpose_of(p, text)
            if not purpose:
                if p.endswith((".html", ".js")) or "/vendor/" in p:
                    purpose = "—"
                else:
                    missing.append(p)
                    purpose = "**(no header comment — add one)**"
            tag = SERIALIZED.get(p)
            if tag:
                purpose = f"{purpose} *[{tag}]*"
            chk = ", ".join(sorted(checks.get(p, ()))) or "—"
            rel = p[len(name) + 1:]
            cm.append(f"| `{rel}` | {bucket(n)} | {md_escape(purpose)} | {chk} |")
        cm.append("")

    # ---------------- CONTRACTS.md ----------------
    server = "install/payload/meshd/server.ts"
    server_text = texts.get(server, "")
    ct = []
    ct.append("# Contracts")
    ct.append("")
    ct.append("*Generated by `python3 scripts/codemap-index.py`; do not edit. The three boundaries that two sides must agree on.*")
    ct.append("")
    ct.append("## Daemon routes")
    ct.append("")
    ct.append("`auth = none` is dispatched before the bearer gate in `server.ts`. Everything else needs `Authorization: Bearer` "
              "(or loopback). Route regexes are shown as `/agents/:x/panes`.")
    ct.append("")
    listeners = {"meshd": []}
    for p in sorted(texts):
        if not p.endswith(".ts") or not (p.startswith("install/payload/meshd/") or p.startswith("install/payload/rmux-bridge/")):
            continue
        if p == server:
            listeners["meshd"].insert(0, p)
        elif re.search(r"\bserve\s*(?:<[^>]*>)?\s*\(", texts[p]):
            listeners[p.replace("install/payload/", "")] = [p]
        else:
            listeners["meshd"].append(p)
    for lname, members in listeners.items():
        if lname != "meshd":
            ct.append(f"### `{lname}` (its own listener)")
            ct.append("")
        ct.append("| method | path | auth | where |")
        ct.append("|---|---|---|---|")
        all_routes = []
        for p in members:
            for meth, rpath, line in routes_of(p, texts[p]):
                if lname != "meshd":
                    tier = "see file"
                elif p == server:
                    tier = auth_tier(server_text, line)
                else:
                    tier = "none" if p.endswith("pair.ts") else "token"
                where = os.path.basename(p) if lname == "meshd" else p.replace("install/payload/", "")
                all_routes.append((rpath, meth, tier, f"{where}:{line}"))
        seen = set()
        for rpath, meth, tier, where in sorted(all_routes, key=lambda r: (r[0], r[1])):
            key = (meth, rpath)
            if key in seen:
                continue
            seen.add(key)
            ct.append(f"| {meth} | `{rpath}` | {tier} | {where} |")
        ct.append("")
    ct.append("## Capabilities")
    ct.append("")
    ct.append("The daemon advertises these strings on `/health`; the phone and watch gate features on `supports(\"x\")`. "
              "A capability that is advertised but never gated is dead on the client; one gated but not in "
              "`DaemonCapabilities.expected` hides silently when the daemon is old.")
    ct.append("")
    ct.append("| capability | gated at | in `expected` |")
    ct.append("|---|---|---|")
    swift_texts = {p: t for p, t in texts.items() if p.endswith(".swift") and not p.startswith("scripts/")}
    dc = texts.get("Shared/DaemonCapabilities.swift", "")
    exp_block = re.search(r"expected[^=]*=\s*\[(.*?)\n\s*\]", dc, re.S)
    expected = set(re.findall(r'"([A-Za-z]+)"', exp_block.group(1))) if exp_block else set()
    for cap in capabilities(server_text):
        sites = []
        for p, t in sorted(swift_texts.items()):
            gate = re.compile(r'supports\("' + cap + r'"\)|capabilities\??\.contains\("' + cap + r'"\)')
            for n, line in enumerate(t.splitlines(), 1):
                if gate.search(line):
                    sites.append(f"{os.path.basename(p)}:{n}")
        ct.append(f"| `{cap}` | {', '.join(sites) or '— (nothing gates it)'} | {'yes' if cap in expected else 'no'} |")
    ct.append("")
    ct.append("## Watch → phone relay commands")
    ct.append("")
    ct.append("`enum WatchCommandKind` in `Shared/Models.swift`: every command the watch can send through the phone. "
              "Each case must be handled in `iOS/MeshStore.swift` `handle(_:)`; an unhandled case is delivered as a silent tick.")
    ct.append("")
    cmds = watch_commands(texts.get("Shared/Models.swift", ""))
    ms = texts.get("iOS/MeshStore.swift", "")
    ct.append("| command | handled in MeshStore |")
    ct.append("|---|---|")
    for c in cmds:
        m = re.search(r"case \." + re.escape(c) + r"\b", ms)
        line = ms[: m.start()].count("\n") + 1 if m else None
        ct.append(f"| `.{c}` | {'MeshStore.swift:' + str(line) if line else '**no case**'} |")
    ct.append("")

    # ---------------- CHECKS.md ----------------
    ck = []
    ck.append("# Checks and scripts")
    ck.append("")
    ck.append("*Generated by `python3 scripts/codemap-index.py`; do not edit. What each `scripts/` file proves, "
              "in its own words (first sentence of its header). `sh scripts/check-all.sh` runs every `check-*`; "
              "Swift checks compile with `-Onone` so `assert` is live.*")
    ck.append("")
    ck.append("| script | proves / does |")
    ck.append("|---|---|")
    for p in sorted(per_area.get("scripts", [])):
        purpose = purpose_of(p, texts[p]) or "**(no header comment — add one)**"
        if len(purpose) > 110:
            purpose = purpose[:110].rsplit(" ", 1)[0] + "…"
        ck.append(f"| `{os.path.basename(p)}` | {md_escape(purpose)} |")
    ck.append("")

    # ---------------- SYMBOLS.md ----------------
    sy = []
    sy.append("# Symbols")
    sy.append("")
    sy.append("*Generated by `python3 scripts/codemap-index.py`; do not edit and do not read top to bottom. "
              "Grep it: `grep -n '^| sessionsNeedingAttention ' docs/agents/SYMBOLS.md`.*")
    sy.append("")
    sy.append("Top-level declarations only (Swift column-0 types and funcs; TS exports; CLI functions). "
              "For members, callers and blast radius use `codegraph explore <name>`.")
    sy.append("")
    sy.append("| symbol | kind | where |")
    sy.append("|---|---|---|")
    rows = []
    for p in code_files:
        for name, kind, line in symbols_of(p, texts[p]):
            rows.append((name, kind, f"{p}:{line}"))
    for name, kind, where in sorted(rows, key=lambda r: (r[0].lower(), r[2])):
        sy.append(f"| {name} | {kind} | {where} |")
    sy.append("")

    return {
        "CODEMAP.md": "\n".join(cm),
        "CONTRACTS.md": "\n".join(ct),
        "CHECKS.md": "\n".join(ck),
        "SYMBOLS.md": "\n".join(sy),
    }, missing


def main():
    check = "--check" in sys.argv
    outputs, missing = build()
    rc = 0
    if check:
        for name, body in outputs.items():
            target = os.path.join(OUT, name)
            current = read(os.path.relpath(target, ROOT)) if os.path.exists(target) else ""
            if current != body:
                rc = 1
                with tempfile.NamedTemporaryFile("w", suffix=name, delete=False) as tmp:
                    tmp.write(body)
                diff = subprocess.run(["diff", "-u", target, tmp.name], capture_output=True, text=True).stdout
                print(f"FAIL: check-codemap: docs/agents/{name} is stale — run: python3 scripts/codemap-index.py")
                print("\n".join(diff.splitlines()[:40]))
                os.unlink(tmp.name)
        if missing:
            rc = 1
            print("FAIL: check-codemap: code files with no header comment (first line must say what the file is):")
            for p in missing:
                print(f"  {p}")
        if rc == 0:
            print(f"check-codemap: OK ({len(outputs)} generated files match the tree; every code file names its purpose)")
        return rc
    os.makedirs(OUT, exist_ok=True)
    for name, body in outputs.items():
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
            f.write(body)
        print(f"wrote docs/agents/{name} ({len(body)} bytes, ~{len(body)//4} tokens)")
    if missing:
        print(f"{len(missing)} code file(s) have no header comment; check-codemap.sh will fail until they do:")
        for p in missing:
            print(f"  {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
