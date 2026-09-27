#!/bin/sh
# check-sdlc-site.sh — the lifecycle teaching site under docs/sdlc/ points only at files that
# exist, and every block in docs/sdlc/BLOCKS.md is shown on the blocks page.
#
# The site's whole value is that each page says "the playbook asks for X; in OUR repo that is
# file Y". A link to a file that was renamed or deleted turns a lesson into a lie, silently.
# So: every relative href/src in every docs/sdlc/*.html must resolve on disk, and every
# `B-nn` id in BLOCKS.md must appear in an HTML page. Reads the tree only; under a second.
set -eu
cd "$(dirname "$0")/.."
SITE=docs/sdlc
[ -d "$SITE" ] || { echo "check-sdlc-site: SKIP ($SITE missing)"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "check-sdlc-site: SKIP (no python3)"; exit 0; }
python3 - "$SITE" <<'PYEOF'
import os, re, sys, glob
site = sys.argv[1]
fail = 0
pages = sorted(glob.glob(os.path.join(site, "*.html")))
if not pages:
    print("check-sdlc-site: ok (no pages yet)"); sys.exit(0)
link = re.compile(r"""(?:href|src)\s*=\s*["']([^"'#?]+)""")
html_text = ""
for page in pages:
    text = open(page, encoding="utf-8", errors="replace").read()
    html_text += text
    for target in link.findall(text):
        if re.match(r"^[a-z]+:", target) or target.startswith("//"):
            continue  # http(s):, mailto:, data:
        path = os.path.normpath(os.path.join(os.path.dirname(page), target))
        if not os.path.exists(path):
            print(f"check-sdlc-site: {page}: broken link -> {target}"); fail = 1
blocks = os.path.join(site, "BLOCKS.md")
if os.path.exists(blocks):
    ids = sorted(set(re.findall(r"\bB-\d{2}\b", open(blocks, encoding="utf-8").read())))
    for bid in ids:
        if bid not in html_text:
            print(f"check-sdlc-site: {bid} is in BLOCKS.md but on no page"); fail = 1
    if not ids:
        print("check-sdlc-site: BLOCKS.md has no B-nn ids"); fail = 1
print("check-sdlc-site: ok (%d pages)" % len(pages) if not fail else "check-sdlc-site: FAIL")
sys.exit(fail)
PYEOF
