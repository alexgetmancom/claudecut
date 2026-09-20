# Compaction — what happens when a session outlives its window

Session overhead is paid once. Compaction is paid again and again, and it is
what decides whether a long session stays useful. This page is what a cut
session and a stock session actually did when both were run past their context
window on the same task.

Measured on Claude Code **v2.1.278**, Opus 5 at low effort, Claude Pro, with
`--autocompact 100000` on both sides. Reproduce with
[`bench/longrun.sh`](../bench/longrun.sh).

## Compaction triggers at the window minus a fixed reserve

Not at a percentage of it. Across two window sizes:

| window | observed triggers | reserve left unused |
|---:|---|---:|
| 200,000 | 162,285 · 164,117 · 167,044 · 167,410 | ~33k–38k |
| 100,000 | 60,071 · 62,579 · 65,326 · 65,521 · 66,721 · 67,255 | ~33k–40k |

The gap between the configured window and the actual trigger stays at roughly
35,000 tokens whether the window is 100k or 200k. It is a reserve, not a ratio.

This explains why `--autocompact` refuses values below 100k: at a 50k window the
trigger would land near 15k, below where a session lands *after* compacting, and
the session would compact in a loop.

## What compaction leaves behind

The number that matters is the **floor**: the prompt size of the first turn
after compaction. It is what every subsequent turn is built on top of, and it
comes back after every compaction for the rest of the session.

**`sh` preset** — 3 compactions:

| # | triggered at | floor after | summary |
|---|---:|---:|---:|
| 1 | 64,972 | 13,440 | ~5,666 |
| 2 | 60,071 | 21,532 | ~4,992 |
| 3 | 65,521 | 8,416 | ~4,659 |

**`default` preset** — 5 compactions:

| # | triggered at | floor after | summary |
|---|---:|---:|---:|
| 1 | 62,579 | 35,628 | ~5,455 |
| 2 | 67,255 | 32,190 | ~7,244 |
| 3 | 65,326 | 37,476 | ~9,446 |
| 4 | 67,281 | 38,082 | ~11,761 |
| 5 | 66,721 | 36,363 | ~9,708 |

The summary itself is small — 5k to 12k tokens. It is not what makes the floor.
The floor is the session's fixed cost, rebuilt from scratch every time: system
prompt, tool schemas, and whatever else loads at startup. Cutting tools cuts the
floor, and the floor is charged on every turn of every cycle.

## The floor does not drift upward

A reasonable worry is that compacting a summary of a summary accumulates
sediment, so each cycle starts dirtier than the last. It did not happen:

```
sh:       13,440 → 21,532 → 8,416
default:  35,628 → 32,190 → 37,476 → 38,082 → 36,363
```

Both oscillate around a level set by the preset — about 14k for `sh`, about 36k
for `default` — with no trend in either. `sh` summaries even shrank across the
run (5,666 → 4,992 → 4,659).

## Why this matters more than startup overhead

With a 100k window, the reserve takes ~35k off the top and the floor takes
whatever the preset costs. What is left is the room the session has to do work
in, and it is reclaimed after every compaction:

| preset | floor | usable room per cycle |
|---|---:|---:|
| `sh` | ~14k | ~51k |
| `default` | ~36k | ~27k |

Roughly twice the working room, in the same window, permanently — not once at
startup.

The effect is visible in how much each session got done between compactions:

| preset | tool calls per segment |
|---|---|
| `sh` | 12 → 12 → 15 → 20 |
| `default` | 14 → 13 → 11 → 9 → 9 → 6 |

The stock session did less and less with each cycle; the cut session did more.
Per tool call over the whole run: `sh` ~60k prompt tokens, `default` ~94k.

Treat tool-call counts as a coarse proxy. One `sh` call running `rg` can replace
several native calls, so the two columns are not the same unit of work.

## Cutting survives compaction

Tools are set by command-line flags at launch, and compaction does not touch
them. After three compactions the cut session was still running on its single
tool, with no stock tool appearing:

```
before any compaction:  mcp__sh__sh:12
after compaction 1:     mcp__sh__sh:12
after compaction 2:     mcp__sh__sh:15
after compaction 3:     mcp__sh__sh:20
```

Confirmed independently in a separate 692-call session that compacted once and
continued using only `mcp__sh__sh`.

`--resume` also preserved the cut, because it is a flag on the ordinary session
command and the preset flags go with it.

**What does restore the stock toolset** is resuming without those flags — plain
`claude --continue`, `claude --resume <id>` or `claude attach <id>`. The flags
live in the command line, not in the session, so a resume started any other way
comes back stock. Resume with `claudecut --continue` or
`claudecut --resume <id>`, which are flags on the session command and so carry
the preset. `claudecut attach <id>` does **not** help: `attach` is a subcommand
and rejects `--tools`/`--system-prompt` (finding 4), so claudecut passes it
straight through and you get a stock session.

## Caveats

- **One run per preset.** No repeats, so there is no variance estimate here.
- **Both runs were stopped by hand** — `sh` after 3 compactions, `default` after
  5 — not run to completion.
- **The third `sh` compaction happened after a `--resume`.** The process had
  restarted, so the lowest floor of the run (8,416) may be an artifact of that
  rather than a property of the preset. It is the weakest number on this page.
- **The two arms ran slightly different prompts.** The `sh` task carried an
  extra instruction not to ask clarifying questions, added after a first attempt
  stopped to ask one. It affects what the model did, not the floor.
- Measured on one version, one repository, one model.

## Reproducing

```bash
bench/longrun.sh --dir ~/code/your-repo --window 100000 --presets sh,default
```

It runs one context-growing task per preset, copies each session transcript into
the results directory, and reports the tables above via
[`bench/compaction.mjs`](../bench/compaction.mjs). The analysis reads saved
transcripts, so it can be re-run on any session:

```bash
node bench/compaction.mjs bench/results/<stamp>
```

Compaction cycles are expensive — this test billed 3.6M prompt tokens for the
cut arm and 5.8M for the stock one. Start with a small repository.
