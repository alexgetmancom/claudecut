#!/usr/bin/env node
// Renders the panels from screens.sh as PNGs, one file per panel, so they can
// be picked over and dropped into a post without retaking terminal shots.
//
// Usage: node bench/screenshots.mjs [outdir]
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outDir = resolve(process.argv[2] || join(root, "bench", "screens"));
const tmp = join(outDir, ".html");
mkdirSync(tmp, { recursive: true });

const CHROME =
  process.env.CHROME ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

// A dark terminal palette, warmer than pure black so the PNG survives being
// posted on a white background.
const THEME = {
  bg: "#12131a",
  chrome: "#1b1d26",
  fg: "#d7dae3",
  dim: "#767c8f",
  green: "#5ec888",
  yellow: "#e0b44b",
};

const esc = (s) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// The panels use only bold, dim, green, yellow and reset.
function ansiToHtml(text) {
  const open = [];
  let out = "";
  const re = /\u001b\[([0-9;]*)m/g;
  let last = 0;
  let m;
  const push = (chunk) => (out += esc(chunk));
  while ((m = re.exec(text))) {
    push(text.slice(last, m.index));
    last = re.lastIndex;
    for (const code of m[1].split(";")) {
      if (code === "0" || code === "") {
        out += "</span>".repeat(open.length);
        open.length = 0;
      } else {
        const cls = { 1: "b", 2: "d", 32: "g", 33: "y" }[code];
        if (cls) {
          out += `<span class="${cls}">`;
          open.push(cls);
        }
      }
    }
  }
  push(text.slice(last));
  out += "</span>".repeat(open.length);
  return out;
}

const page = (body, title) => `<!doctype html>
<meta charset="utf-8">
<title>${esc(title)}</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 40px; background: transparent;
    font: 15px/1.55 ui-monospace, "SF Mono", Menlo, monospace;
  }
  .win {
    background: ${THEME.bg}; color: ${THEME.fg};
    border-radius: 12px; overflow: hidden; width: max-content; min-width: 640px;
    box-shadow: 0 18px 50px rgba(0,0,0,.45);
  }
  .bar {
    background: ${THEME.chrome}; padding: 10px 14px;
    display: flex; align-items: center; gap: 8px;
  }
  .dot { width: 11px; height: 11px; border-radius: 50%; }
  .t { font-size: 12px; color: ${THEME.dim}; margin-left: 8px; }
  pre { margin: 0; padding: 14px 26px 22px; white-space: pre; }
  .b { font-weight: 700; color: #fff; }
  .d { color: ${THEME.dim}; }
  .g { color: ${THEME.green}; }
  .y { color: ${THEME.yellow}; }
</style>
<div class="win">
  <div class="bar">
    <div class="dot" style="background:#ff5f57"></div>
    <div class="dot" style="background:#febc2e"></div>
    <div class="dot" style="background:#28c840"></div>
    <div class="t">${esc(title)}</div>
  </div>
  <pre>${body}</pre>
</div>`;

const TITLES = {
  1: "claudecut — startup overhead",
  2: "claudecut — same task, both presets",
  3: "claudecut — after compaction",
  4: "claudecut — work per cycle",
  5: "claudecut — tools after 3 compactions",
  6: "claudecut — the tool search trap",
};

for (const n of [1, 2, 3, 4, 5, 6]) {
  const ansi = execFileSync(join(root, "bench", "screens.sh"), [String(n)], {
    encoding: "utf8",
  });
  const html = page(ansiToHtml(ansi.replace(/^\n|\n$/g, "")), TITLES[n]);
  const htmlPath = join(tmp, `p${n}.html`);
  writeFileSync(htmlPath, html);

  // Chrome sizes the shot to the window, so the window is sized to the panel.
  // Monospace at 15px measures ~9.0px per column and 23.4px per line.
  const lines = ansi.replace(/^\n|\n$/g, "").split("\n");
  const cols = Math.max(...lines.map((l) => l.replace(/\u001b\[[0-9;]*m/g, "").length));
  const width = Math.round(Math.max(640, cols * 9.0 + 52) + 80);
  const height = Math.round(lines.length * 23.4 + 36 + 36 + 80);

  const png = join(outDir, `p${n}.png`);
  execFileSync(CHROME, [
    "--headless",
    "--disable-gpu",
    "--hide-scrollbars",
    "--default-background-color=00000000",
    "--force-device-scale-factor=2",
    `--window-size=${width},${height}`,
    `--screenshot=${png}`,
    `file://${htmlPath}`,
  ]);
  console.log(`wrote ${png}`);
}

rmSync(tmp, { recursive: true, force: true });
console.log(`\nPanels in ${outDir} — p1..p6, one per tweet.`);
