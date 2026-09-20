#!/usr/bin/env node
// Reads session transcripts saved by longrun.sh and reports what compaction
// actually did: where it triggered, what it left behind, how the floor moved,
// and which tools the session used after each compaction.
//
// Usage: node bench/compaction.mjs <results-dir>
import { createInterface } from "node:readline";
import { createReadStream, readdirSync } from "node:fs";
import { join } from "node:path";

const dir = process.argv[2];
if (!dir) {
  console.error("usage: compaction.mjs <results-dir>");
  process.exit(2);
}

const promptTokens = (u) =>
  (u.input_tokens || 0) +
  (u.cache_creation_input_tokens || 0) +
  (u.cache_read_input_tokens || 0);

async function analyse(file) {
  const rl = createInterface({
    input: createReadStream(file),
    crlfDelay: Infinity,
  });

  const segments = [{ tools: {}, prompts: [] }];
  const compactions = [];
  let line = 0;

  for await (const raw of rl) {
    line++;
    let o;
    try {
      o = JSON.parse(raw);
    } catch {
      continue;
    }

    if (o.isCompactSummary === true) {
      const c = o.message?.content;
      const text =
        typeof c === "string" ? c : (c || []).map((x) => x.text || "").join("");
      compactions.push({ line, chars: text.length });
      segments.push({ tools: {}, prompts: [] });
      continue;
    }

    const seg = segments[segments.length - 1];
    const u = o.message?.usage;
    if (u) {
      const p = promptTokens(u);
      // Sub-500 prompts are bookkeeping calls, not conversation turns.
      if (p > 500) seg.prompts.push(p);
    }
    for (const c of o.message?.content || []) {
      if (c.type === "tool_use") seg.tools[c.name] = (seg.tools[c.name] || 0) + 1;
    }
  }

  return { segments, compactions };
}

const fmt = (n) => n.toLocaleString("en-US");
const toolList = (m) => {
  const e = Object.entries(m).sort((a, b) => b[1] - a[1]);
  return e.length ? e.map(([k, v]) => `${k}:${v}`).join(" ") : "(none)";
};

const files = readdirSync(dir).filter((f) => f.endsWith(".transcript.jsonl"));
if (!files.length) {
  console.log("No transcripts found in " + dir);
  process.exit(0);
}

console.log("# Long-session compaction report\n");

for (const f of files.sort()) {
  const preset = f.replace(".transcript.jsonl", "");
  const { segments, compactions } = await analyse(join(dir, f));
  const all = segments.flatMap((s) => s.prompts);

  console.log(`## ${preset}\n`);
  if (!all.length) {
    console.log("No usage recorded.\n");
    continue;
  }

  console.log(
    `Compactions: **${compactions.length}** · ` +
      `peak prompt ${fmt(Math.max(...all))} · ` +
      `total prompt tokens billed ${fmt(all.reduce((a, b) => a + b, 0))}\n`,
  );

  if (compactions.length) {
    console.log("| # | triggered at | floor after | est. summary tokens | floor rise |");
    console.log("|---|---:|---:|---:|---:|");
    let prevFloor = null;
    compactions.forEach((c, i) => {
      const before = segments[i].prompts;
      const after = segments[i + 1].prompts;
      const trigger = before.length ? Math.max(...before) : 0;
      const floor = after.length ? after[0] : 0;
      const summary = Math.round(c.chars / 3.7);
      const rise =
        prevFloor === null
          ? "—"
          : (floor - prevFloor >= 0 ? "+" : "") + fmt(floor - prevFloor);
      prevFloor = floor;
      console.log(
        `| ${i + 1} | ${fmt(trigger)} | ${fmt(floor)} | ~${fmt(summary)} | ${rise} |`,
      );
    });
    console.log("");
  }

  console.log("Tools used, per segment between compactions:\n");
  segments.forEach((s, i) => {
    const label = i === 0 ? "before any compaction" : `after compaction ${i}`;
    console.log(`- **${label}:** ${toolList(s.tools)}`);
  });
  console.log("");
}
