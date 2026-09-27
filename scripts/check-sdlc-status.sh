#!/bin/sh
# check-sdlc-status.sh — every status line on the lifecycle site under docs/sdlc/ carries a proof, and its Done / In progress / Not started word agrees with what the repo holds.
#
# The site (docs/sdlc/*.html) tells Arya where each stage stands. That is only worth anything
# while it is true, so every status item carries a `data-proof` from a closed grammar
# (docs/sdlc site spec, section 6.2): file:<path>, text:<path>|<literal>, any:<glob>,
# any:<glob>|<literal>, live:<name>, each optionally negated with a leading `!`.
# This check evaluates each proof against the repo's file set
# (git ls-files --cached --others --exclude-standard) and fails when a chip says done without
# a true proof, or not-started / in-progress while the proof is true. It also checks: the
# item markup (state word, owner, `you` tag, block id), relative links resolve to files,
# data-anchor literals are still in their files, page#id fragments exist, blocks.html ids
# match BLOCKS.md, the <header class="top"> nav is identical on every page, and no images,
# scripts, inline styles or private screenshots slip in.
#
# Reads the tree only; no network unless SDLC_LIVE=1 (then the three fixed `live:` queries
# run through `gh`; page text never chooses a command). Under two seconds.
#   sh scripts/check-sdlc-status.sh           # verdict
#   sh scripts/check-sdlc-status.sh --board   # one line per status item, then per-page counts
set -eu
cd "$(dirname "$0")/.."
SITE=docs/sdlc
[ -d "$SITE" ] || { echo "check-sdlc-status: SKIP ($SITE missing)"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "check-sdlc-status: SKIP (no python3)"; exit 0; }
python3 - "$SITE" "$@" <<'PYEOF'
import datetime, fnmatch, glob, os, re, subprocess, sys
from html.parser import HTMLParser

site, board = sys.argv[1], "--board" in sys.argv[2:]
live_on = os.environ.get("SDLC_LIVE") == "1"
today = datetime.date.today()
fails, warns = [], []
def fail(msg): fails.append("check-sdlc-status: " + msg)
def warn(msg): warns.append("check-sdlc-status: warn: " + msg)

try:
    out = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                         capture_output=True, check=True).stdout.decode()
except (OSError, subprocess.CalledProcessError):
    print("check-sdlc-status: SKIP (not a git checkout)"); sys.exit(0)
fileset = {p for p in out.split("\0") if p and os.path.lexists(p)}  # drop tracked-but-deleted
dirs = {os.path.dirname(p) for p in fileset}
_text = {}
def text_of(path):
    if path not in _text:
        _text[path] = open(path, encoding="utf-8", errors="replace").read()
    return _text[path]

# ---- proof grammar (closed) ----------------------------------------------------------
LIVE = {  # name -> (argv, predicate on stdout). Page text only ever picks a name.
    "main-protected": (["gh", "api", "repos/aryateja2106/lecoder-watch/rules/branches/main", "--jq", "length"],
                       lambda s: s.isdigit() and int(s) > 0),
    "review-queue-ok": (["gh", "pr", "list", "-R", "aryateja2106/lecoder-watch", "--state", "open",
                         "--limit", "300", "--json", "number", "--jq", "length"],
                        lambda s: s.isdigit() and int(s) <= 3),
    "ci-latest-green": (["gh", "run", "list", "-R", "aryateja2106/lecoder-watch", "--workflow", "ci.yml",
                         "--limit", "1", "--json", "conclusion", "--jq", ".[0].conclusion"],
                        lambda s: s == "success"),
}
GRAMMAR = re.compile(r"^!?(file:[^|]+|text:[^|]+\|.+|any:[^|]+(\|.+)?|live:[a-z0-9-]+)$", re.S)
_live = {}
def evaluate(proof):
    """-> True / False / 'skip'. Caller has validated the grammar."""
    neg = proof.startswith("!")
    kind, _, rest = proof.lstrip("!").partition(":")
    if kind == "live":
        if not live_on: return "skip"
        if rest not in _live:
            argv, ok = LIVE[rest]
            try:
                r = subprocess.run(argv, capture_output=True, text=True, timeout=30)
                _live[rest] = ok(r.stdout.strip()) if r.returncode == 0 else "skip"
            except (OSError, subprocess.TimeoutExpired):
                _live[rest] = "skip"  # gh missing / offline
        v = _live[rest]
        return v if v == "skip" else v != neg
    target, bar, lit = rest.partition("|")
    if kind == "file":
        v = target in fileset
    elif kind == "text":
        v = target in fileset and lit in text_of(target)
    else:  # any
        v = any(fnmatch.fnmatchcase(p, target) and (not bar or lit in text_of(p)) for p in fileset)
    return v != neg

# ---- a small DOM ---------------------------------------------------------------------
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
class Node:
    def __init__(s, tag, attrs, parent):
        s.tag, s.a, s.parent, s.kids = tag, dict(attrs), parent, []
    def cls(s): return (s.a.get("class") or "").split()
    def text(s): return " ".join("".join(k if isinstance(k, str) else k.text() for k in s.kids).split())
    def walk(s):
        for k in s.kids:
            if isinstance(k, Node):
                yield k; yield from k.walk()
class Tree(HTMLParser):
    def __init__(s):
        super().__init__(convert_charrefs=True); s.root = Node("#root", {}, None); s.cur = s.root
    def handle_starttag(s, tag, attrs):
        n = Node(tag, attrs, s.cur); s.cur.kids.append(n)
        if tag not in VOID: s.cur = n
    def handle_startendtag(s, tag, attrs): s.cur.kids.append(Node(tag, attrs, s.cur))
    def handle_endtag(s, tag):
        n = s.cur
        while n is not s.root and n.tag != tag: n = n.parent
        if n is not s.root: s.cur = n.parent
    def handle_data(s, d): s.cur.kids.append(d)

def asof_date(v):
    try: return datetime.date.fromisoformat(v) if re.fullmatch(r"\d{4}-\d{2}-\d{2}", v or "") else None
    except ValueError: return None

# ---- per page ------------------------------------------------------------------------
pages = sorted(glob.glob(os.path.join(site, "*.html")))
if not pages:
    print("check-sdlc-status: ok (no pages yet)"); sys.exit(0)
for req in ("sdlc.css", "AGENTS.md"):
    if not os.path.isfile(os.path.join(site, req)):
        fail(f"{site}/{req} is missing (required by the site)")
doms, ids = {}, {}
for page in pages:
    t = Tree(); t.feed(text_of(page)); t.close()
    name = os.path.basename(page)
    doms[name] = t.root
    ids[name] = [n.a["id"] for n in t.root.walk() if n.a.get("id")]

block_ids = set(ids.get("blocks.html", []))
navs, n_items, n_skip, board_lines, counts = {}, 0, 0, [], {}
for page in pages:
    name, raw, root = os.path.basename(page), text_of(page), doms[os.path.basename(page)]
    nodes = list(root.walk())
    c = counts.setdefault(name, {"done": 0, "in-progress": 0, "not-started": 0})

    # 1-3. status items
    for it in (n for n in nodes if "data-state" in n.a):
        n_items += 1
        st, proof, owner = it.a.get("data-state"), it.a.get("data-proof") or "", it.a.get("data-owner")
        lab = next((n.text() for n in it.walk() if "label" in n.cls()), "") or it.text()[:60]
        where = f'{name}: "{lab}"'
        if st not in c:
            fail(f'{where}: data-state="{st}" is not done / in-progress / not-started'); continue
        c[st] += 1
        word = {"done": "Done", "in-progress": "In progress", "not-started": "Not started"}[st]
        sw = [k.text() for k in it.kids if isinstance(k, Node) and "state" in k.cls()]
        if sw != [word]:
            fail(f'{where}: data-state="{st}" needs one direct <span class="state">{word}</span> (found {sw})')
        if owner not in ("arya", "agent", "verifier"):
            fail(f'{where}: data-owner="{owner}" must be arya, agent or verifier')
        has_you = any("you" in n.cls() and n.text() == "you" for n in it.walk())
        if (owner == "arya") != has_you:
            fail(f'{where}: data-owner="arya" if and only if the item has <span class="you">you</span>')
        blk = it.a.get("data-block")
        if blk is not None:
            if not re.fullmatch(r"B-\d{2}", blk):
                fail(f'{where}: data-block="{blk}" is not B-nn')
            elif blk not in block_ids:
                fail(f'{where}: data-block="{blk}" has no id="{blk}" on blocks.html')
            bids = [n.a.get("href", "") for n in it.walk() if "bid" in n.cls()]
            if bids and bids != [f"blocks.html#{blk}"]:
                fail(f'{where}: the .bid link {bids} must point to blocks.html#{blk}')
        asof = it.a.get("data-asof")
        needs_asof = st == "in-progress" or proof.lstrip("!").startswith("live:")
        if asof is not None or needs_asof:
            d = asof_date(asof)
            if d is None:
                fail(f'{where}: needs data-asof="YYYY-MM-DD" (in-progress and live: items)');
            else:
                if not any("asof" in n.cls() and n.text() == f"checked {asof}" for n in it.walk()):
                    fail(f'{where}: needs a visible <span class="asof">checked {asof}</span>')
                age = (today - d).days
                if st == "in-progress" and age > 45: warn(f"{where}: in-progress since {asof} ({age} days)")
                if proof.lstrip("!").startswith("live:") and age > 30: warn(f"{where}: live check dated {asof} ({age} days)")
        if not GRAMMAR.match(proof):
            fail(f'{where}: data-proof="{proof}" is not in the grammar (file: text:path|lit any:glob[|lit] live:name, optional !)')
            board_lines.append(f"{name}  {blk or '-'}  {st}  {owner}  {proof}  -> invalid  MISMATCH"); continue
        if proof.lstrip("!").startswith("live:") and proof.lstrip("!")[5:] not in LIVE:
            fail(f'{where}: unknown live: name in "{proof}" (allowed: {", ".join(sorted(LIVE))})')
            board_lines.append(f"{name}  {blk or '-'}  {st}  {owner}  {proof}  -> invalid  MISMATCH"); continue
        v = evaluate(proof)
        verdict = "ok"
        if v == "skip":
            n_skip += 1
        elif v and st != "done":
            verdict = "MISMATCH"
            fail(f'{where} says {st} but {proof} is now true; set data-state="done" and the state word to Done')
        elif not v and st == "done":
            verdict = "MISMATCH"
            fail(f'{where} says done but {proof} is false; set data-state="not-started" (or in-progress with data-asof) and the state word to match')
        board_lines.append(f"{name}  {blk or '-'}  {st}  {owner}  {proof}  -> {str(v).lower()}  {verdict}")

    # 4-6. links, anchors, fragments
    for n in nodes:
        for attr in ("href", "src"):
            u = n.a.get(attr)
            if u is None: continue
            if "Reference-images/" in u or "iphone-settings.png" in u:
                fail(f"{name}: banned target {u} (private screenshots)")
            if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", u) or u.startswith("//"):
                if not (n.tag == "a" and attr == "href" and re.match(r"^(https?|mailto):", u)):
                    fail(f"{name}: external {n.tag} {attr}={u} (only <a href> may leave the repo)")
                continue
            path, _, frag = u.partition("#")
            path = path.partition("?")[0]
            if not path:
                if frag and frag not in ids[name]: fail(f"{name}: #{frag} has no matching id on this page")
                continue
            rel = os.path.normpath(os.path.join(site, path))
            if os.path.isdir(rel) or rel in dirs:
                fail(f"{name}: {u} is a folder; link a file, for example its AGENTS.md"); continue
            if rel not in fileset:
                fail(f"{name}: broken link -> {u}"); continue
            if frag and os.path.dirname(rel) == site and rel.endswith(".html"):
                tgt = os.path.basename(rel)
                if frag not in ids.get(tgt, []): fail(f"{name}: {u} -> no id=\"{frag}\" on {tgt}")
        if "data-anchor" in n.a:
            lit, href = n.a["data-anchor"], n.a.get("href", "")
            rel = os.path.normpath(os.path.join(site, href.partition("#")[0].partition("?")[0])) if href else ""
            if not href or rel not in fileset:
                fail(f'{name}: data-anchor="{lit}" sits on an element without a resolvable href')
            elif lit not in text_of(rel):
                fail(f'{name}: {rel} no longer contains "{lit}" (data-anchor)')

    # 8. navigation
    heads = re.findall(r'<header class="top">.*?</header>', raw, re.S)
    if len(heads) != 1:
        fail(f'{name}: needs exactly one <header class="top"> (found {len(heads)})')
    else:
        h = heads[0]
        cur = re.findall(r'<a[^>]*aria-current="page"[^>]*>', h)
        if len(cur) != 1 or f'href="{name}"' not in cur[0]:
            fail(f'{name}: the nav needs exactly one aria-current="page", on the link to {name}')
        navs[name] = " ".join(h.replace(' aria-current="page"', "").split())

    # 9-10. banned content, stylesheet
    for pat, what in ((r"<img\b", "<img"), (r"<script\b", "<script"), (r"<style\b", "<style")):
        if re.search(pat, raw, re.I): fail(f"{name}: contains {what} (not allowed on the site)")
    if not any(n.tag == "link" and n.a.get("href") == "sdlc.css" and "stylesheet" in (n.a.get("rel") or "") for n in nodes):
        fail(f'{name}: does not link sdlc.css')

    # 11. freshness warnings
    for n in nodes:
        if n.tag == "time" and "data-verified" in n.a:
            d = asof_date(n.a.get("datetime"))
            if d and (today - d).days > 30: warn(f"{name}: last verified {d} ({(today - d).days} days)")
        if n.a.get("id") == "this-week":
            a = n.a.get("data-asof") or (n.parent.a.get("data-asof") if n.parent else None)
            d = asof_date(a)
            if d is None: warn(f"{name}: #this-week has no data-asof")
            elif (today - d).days > 14: warn(f"{name}: #this-week dated {d} ({(today - d).days} days)")

if len(set(navs.values())) > 1:
    base = max(set(navs.values()), key=list(navs.values()).count)
    for p, h in navs.items():
        if h != base: fail(f'{p}: <header class="top"> differs from the other pages (copy it verbatim)')

# 7. blocks.html vs BLOCKS.md
bm = os.path.join(site, "BLOCKS.md")
if os.path.isfile(bm) and "blocks.html" in ids:
    want = set(re.findall(r"\bB-\d{2}\b", text_of(bm)))
    have = [i for i in ids["blocks.html"] if re.fullmatch(r"B-\d{2}", i)]
    for b in sorted(want):
        if have.count(b) != 1: fail(f'blocks.html: id="{b}" appears {have.count(b)} times (BLOCKS.md needs exactly one)')
    for b in sorted(set(have) - want): fail(f'blocks.html: id="{b}" is not in BLOCKS.md')

if board:
    for l in board_lines: print(l)
    for p, c in counts.items():
        print(f"{p:16} done={c['done']:<3} in-progress={c['in-progress']:<3} not-started={c['not-started']}")
for w in warns: print(w)
for f in fails: print(f)
if fails:
    print("check-sdlc-status: FAIL"); sys.exit(1)
print(f"check-sdlc-status: ok ({len(pages)} pages, {n_items} status lines, {n_skip} live skipped)")
PYEOF
