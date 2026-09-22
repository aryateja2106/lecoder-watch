// build-web-docs.ts — renders docs/getting-started.md into web/getting-started.html so lesearch.ai serves the same page the repo carries; one source, no renderer dependency.
//
//   bun scripts/build-web-docs.ts            # write web/getting-started.html
//   bun scripts/build-web-docs.ts --check    # exit 1 when the committed HTML is stale
//
// Supports exactly the Markdown the docs use: #/##/### headings, paragraphs, - lists,
// ``` code blocks, `inline code`, **bold**, *italic*, [links](url), ![images](path) and
// > quotes. Image paths under docs/product/shots/ are rewritten to /shots/… and the
// files are copied into web/shots/, so the page and the repo show the same pictures.
// ponytail: a 60-line converter is the whole renderer; reach for a library only when a
// doc needs a table or nested list this one cannot draw.
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from "node:fs";
import { dirname, join, basename } from "node:path";

const ROOT = join(dirname(new URL(import.meta.url).pathname), "..");
const SRC = join(ROOT, "docs", "getting-started.md");
const OUT = join(ROOT, "web", "getting-started.html");
const CHECK = process.argv.includes("--check");

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
function inline(s: string): string {
  return esc(s)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (_m, alt, src) => `<img src="${src.replace(/^product\/shots\//, "/shots/")}" alt="${alt}">`)
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_m, text, href) => `<a href="${href.replace(/^product\/(.*)\.md$/, "https://github.com/LeSearch-AI/mesh/blob/main/docs/product/$1.md")}">${text}</a>`)
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[^*])\*([^*]+)\*/g, "$1<em>$2</em>");
}

export function render(md: string): string {
  const out: string[] = [];
  const lines = md.split("\n");
  let i = 0;
  const shots: string[] = [];
  while (i < lines.length) {
    const l = lines[i];
    if (l.startsWith("```")) {
      const buf: string[] = []; i++;
      while (i < lines.length && !lines[i].startsWith("```")) buf.push(lines[i++]);
      i++; out.push(`<pre><code>${esc(buf.join("\n"))}</code></pre>`); continue;
    }
    const h = l.match(/^(#{1,3}) (.*)$/);
    if (h) {
      const id = h[2].toLowerCase().replace(/[^a-z0-9 ]+/g, "").trim().replace(/\s+/g, "-");
      out.push(`<h${h[1].length} id="${id}">${inline(h[2])}</h${h[1].length}>`); i++; continue;
    }
    if (l.startsWith("- ")) {
      const items: string[] = [];
      while (i < lines.length && (lines[i].startsWith("- ") || lines[i].startsWith("  "))) {
        if (lines[i].startsWith("- ")) items.push(lines[i].slice(2)); else items[items.length - 1] += " " + lines[i].trim();
        i++;
      }
      out.push(`<ul>${items.map((t) => `<li>${inline(t)}</li>`).join("")}</ul>`); continue;
    }
    if (l.startsWith("> ")) {
      const buf: string[] = [];
      while (i < lines.length && lines[i].startsWith("> ")) buf.push(lines[i++].slice(2));
      out.push(`<blockquote><p>${inline(buf.join(" "))}</p></blockquote>`); continue;
    }
    if (l.trim() === "") { i++; continue; }
    const img = l.match(/^!\[([^\]]*)\]\(([^)]+)\)$/);
    if (img) { shots.push(img[2]); out.push(`<figure>${inline(l)}<figcaption>${esc(img[1])}</figcaption></figure>`); i++; continue; }
    const buf: string[] = [];
    while (i < lines.length && lines[i].trim() !== "" && !/^(#|- |> |```|!\[)/.test(lines[i])) buf.push(lines[i++]);
    out.push(`<p>${inline(buf.join(" "))}</p>`);
  }
  const title = (md.match(/^# (.*)$/m)?.[1] ?? "Getting started").replace(/`/g, "");
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} — LeSearch AI</title>
<meta name="description" content="From nothing to the first buzz on your wrist: install the app, install the daemon, pair, run an agent, report a problem.">
<link rel="icon" href="/logo.svg" type="image/svg+xml">
<style>
:root{--bg:#0b0b0c;--ink:#f2f2f0;--ink-2:#b8b8b3;--ink-3:#7a7a75;--line:#242426;--accent:#ff7a1a;--mono:ui-monospace,SFMono-Regular,Menlo,monospace}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 -apple-system,BlinkMacSystemFont,"Inter",system-ui,sans-serif}
header{border-bottom:1px solid var(--line)}.nav{max-width:760px;margin:0 auto;padding:14px 20px;display:flex;gap:18px;align-items:center}
.nav a{color:var(--ink-2);text-decoration:none;font-size:14px}.nav .brand{color:var(--ink);font-weight:700;display:flex;gap:8px;align-items:center}.nav img{width:20px;height:20px}.nav .spacer{flex:1}
main{max-width:760px;margin:0 auto;padding:36px 20px 80px}h1{font-size:34px;line-height:1.15;letter-spacing:-.02em;margin:0 0 20px}h2{font-size:22px;margin:44px 0 12px;letter-spacing:-.01em}h3{font-size:17px;margin:28px 0 8px}
p,li{color:var(--ink-2)}strong{color:var(--ink)}a{color:var(--accent)}code{font-family:var(--mono);font-size:.92em;background:#151517;border:1px solid var(--line);border-radius:5px;padding:1px 5px}
pre{background:#151517;border:1px solid var(--line);border-radius:10px;padding:14px 16px;overflow:auto}pre code{border:0;background:none;padding:0}
figure{margin:22px 0}figure img{max-width:320px;width:100%;border:1px solid var(--line);border-radius:22px;display:block}figcaption{color:var(--ink-3);font-size:13px;margin-top:8px}
blockquote{border-left:3px solid var(--line);margin:16px 0;padding:2px 16px;color:var(--ink-3)}ul{padding-left:22px}
</style></head><body>
<header><div class="nav"><a class="brand" href="/"><img src="/logo.svg" alt=""> LeSearch AI</a><span class="spacer"></span><a href="/">Home</a><a href="/install.sh">install.sh</a><a href="/privacy">Privacy</a><a href="https://github.com/LeSearch-AI/mesh">GitHub</a></div></header>
<main>
${out.join("\n")}
</main></body></html>
`;
}

if (import.meta.main) {
  const html = render(readFileSync(SRC, "utf8"));
  if (CHECK) {
    const cur = existsSync(OUT) ? readFileSync(OUT, "utf8") : "";
    if (cur !== html) { console.log(`FAIL: ${OUT} is stale — run: bun scripts/build-web-docs.ts`); process.exit(1); }
    console.log("build-web-docs: web/getting-started.html matches docs/getting-started.md");
  } else {
    writeFileSync(OUT, html);
    mkdirSync(join(ROOT, "web", "shots"), { recursive: true });
    for (const m of readFileSync(SRC, "utf8").matchAll(/!\[[^\]]*\]\(product\/shots\/([^)]+)\)/g)) {
      const src = join(ROOT, "docs", "product", "shots", m[1]);
      if (existsSync(src)) copyFileSync(src, join(ROOT, "web", "shots", basename(m[1])));
    }
    console.log(`wrote ${OUT}`);
  }
}
