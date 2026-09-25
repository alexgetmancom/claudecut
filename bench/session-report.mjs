#!/usr/bin/env node
// What a session actually spent, read back from the transcript Claude Code
// already writes. No logging is added anywhere: ~/.claude/projects/<slug>/
// <session-id>.jsonl records every command, its output, its exit note and its
// timestamp, plus the token usage of every request — which is the one thing a
// shell-side log could never see.
//
//   bench/session-report.mjs <transcript.jsonl>
//   bench/session-report.mjs --latest ~/projects/some-repo
//
// The number that matters here is not how big an output was but how many times
// it was re-read afterwards: everything in the context is re-sent with every
// later request until the next compaction.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const args = process.argv.slice(2);
let file = args[0];
if (args[0] === "--latest") {
  const slug = (args[1] ?? process.cwd()).replace(/\//g, "-");
  const dir = join(homedir(), ".claude", "projects", slug);
  const newest = readdirSync(dir)
    .filter((f) => f.endsWith(".jsonl"))
    .map((f) => ({ f, t: statSync(join(dir, f)).mtimeMs }))
    .sort((a, b) => b.t - a.t)[0];
  if (!newest) { console.error(`no transcript in ${dir}`); process.exit(1); }
  file = join(dir, newest.f);
}
if (!file) { console.error("usage: session-report.mjs <transcript.jsonl> | --latest [dir]"); process.exit(2); }

const recs = [];
for (const line of readFileSync(file, "utf8").split("\n")) {
  if (!line.startsWith("{")) continue;
  try { recs.push(JSON.parse(line)); } catch {}
}
const tok = (s) => Math.floor(s.length / 4);
const cuts = recs.map((d, i) => (d.isCompactSummary ? i : -1)).filter((i) => i >= 0).concat(recs.length);
const callIdx = recs.map((d, i) => (d.type === "assistant" && d.message?.usage ? i : -1)).filter((i) => i >= 0);
// How many later requests re-read something introduced at record i.
const rereads = (i) => {
  const end = cuts.find((c) => c > i);
  return callIdx.filter((c) => c > i && c < end).length;
};

const calls = [];      // one per shell command
const usage = [];
const byKind = new Map();
const add = (kind, t, r) => {
  const e = byKind.get(kind) ?? { tok: 0, integrated: 0 };
  e.tok += t; e.integrated += t * r; byKind.set(kind, e);
};
const pending = new Map();
for (const [i, d] of recs.entries()) {
  const r = rereads(i);
  if (d.type === "assistant") {
    if (d.message?.usage) usage.push(d.message.usage);
    for (const c of d.message?.content ?? []) {
      if (c.type === "text") add("assistant text", tok(c.text), r);
      else if (c.type === "tool_use") {
        const cmd = c.input?.cmd ?? c.input?.command ?? "";
        add("commands sent", tok(JSON.stringify(c.input ?? {})), r);
        pending.set(c.id, { cmd, at: d.timestamp, i });
      }
    }
  } else if (d.type === "user") {
    if (d.isCompactSummary) { add("compaction summary", tok(JSON.stringify(d.message?.content ?? "")), r); continue; }
    const content = d.message?.content;
    for (const c of Array.isArray(content) ? content : [{ type: "text", text: String(content ?? "") }]) {
      if (c.type === "tool_result") {
        const p = pending.get(c.tool_use_id);
        if (!p) continue;
        const text = typeof c.content === "string" ? c.content
          : (c.content ?? []).map((x) => x.text ?? "").join("");
        add("tool output", tok(text), r);
        calls.push({ ...p, text, rereads: r,
          secs: p.at && d.timestamp ? (Date.parse(d.timestamp) - Date.parse(p.at)) / 1000 : null });
      } else if (c.type === "text") add("user turns", tok(c.text), r);
    }
  }
}

const reads = usage.reduce((a, u) => a + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0) + (u.input_tokens ?? 0), 0);
const out = usage.reduce((a, u) => a + (u.output_tokens ?? 0), 0);
const fmt = (n) => n.toLocaleString("en-US");
console.log(`transcript      ${file}`);
console.log(`model calls     ${fmt(usage.length)}   shell calls ${fmt(calls.length)}   compactions ${cuts.length - 1}`);
console.log(`context reads   ${fmt(reads)}   output ${fmt(out)}`);

console.log(`\nwhere the context reads went`);
const total = [...byKind.values()].reduce((a, e) => a + e.integrated, 0) || 1;
for (const [k, e] of [...byKind].sort((a, b) => b[1].integrated - a[1].integrated))
  console.log(`  ${k.padEnd(20)} ${String(fmt(e.tok)).padStart(9)} tok  ${String(fmt(e.integrated)).padStart(12)} reads  ${((100 * e.integrated) / total).toFixed(1)}%`);

// Friction: things that failed for reasons unrelated to the task.
const friction = {
  "zsh: unmatched glob": /no matches found/,
  "zsh: leading = expansion": /zsh:\d+: =\S* not found/,
  "command not found": /command not found: (\w+)/,
  "output was clipped": /characters truncated/,
  "moved to the background": /still running after \d+s/,
  "timed out": /\[timed out after/,
};
const hits = Object.entries(friction)
  .map(([k, re]) => [k, calls.filter((c) => re.test(c.text)).length])
  .filter(([, n]) => n);
console.log(`\nfriction  (${hits.reduce((a, [, n]) => a + n, 0)} of ${calls.length} calls)`);
for (const [k, n] of hits.sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(4)}  ${k}`);

console.log(`\nmost expensive single outputs`);
for (const c of [...calls].sort((a, b) => tok(b.text) * b.rereads - tok(a.text) * a.rereads).slice(0, 5))
  console.log(`  ${String(fmt(tok(c.text) * c.rereads)).padStart(11)} = ${String(fmt(tok(c.text))).padStart(6)} tok x ${String(c.rereads).padStart(4)} re-reads  ${c.cmd.replace(/\s+/g, " ").slice(0, 60)}`);

const slow = calls.filter((c) => c.secs > 30).sort((a, b) => b.secs - a.secs);
if (slow.length) {
  console.log(`\nslowest calls`);
  for (const c of slow.slice(0, 5)) console.log(`  ${c.secs.toFixed(1).padStart(7)}s  ${c.cmd.replace(/\s+/g, " ").slice(0, 60)}`);
}
