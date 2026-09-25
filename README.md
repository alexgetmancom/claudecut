# claudecut

Run **Claude Code** with almost everything cut away.

Same CLI, same account, same login. But a session starts with one tool instead
of twenty, a 36-token system prompt instead of the default one, and a context
window capped so it compacts early instead of quietly growing into your limits.

Built for a $20 Claude Pro plan, where the thing you are actually spending is
context.

![Half the cost on real coding tasks](bench/screens/pab.png)

On two real tasks against a live TypeScript repo, a cut session cost about half
what stock Claude Code cost, at comparable answer quality. On a long session it
keeps roughly twice as much working room after every compaction. Startup context
drops from 17,625 tokens to 953.

**How much to trust each of those**, because they are not equally solid:

| result | evidence |
|---|---|
| The floor after compaction — ~14k cut vs ~36k stock | **Solid.** Two long transcripts, plus four unrelated sessions read back the same way. The gap is far outside run-to-run noise. |
| Compaction fires at the window minus ~35k, a fixed reserve | **Solid.** Same reserve measured at both a 100k and a 200k window. |
| Disabling tool search doubles your prompt | **Solid.** Two runs per condition, effect is ~2x against ~9% noise. |
| ~Half the cost on real tasks | **A trend, not statistics.** Three runs per task, ~9% spread between identical runs, and the stock arm inherited local settings in those runs. |
| Comparable quality | **Read, not scored.** All twelve short-task answers were compared by hand. Nobody graded the long runs at all. |

The last two are where outside data points would help most — see
[contributing a data point](docs/limits.md#contributing-a-data-point).

<details>
<summary>What a cut session looks like from the inside</summary>

![A cut session, as /context reports it](docs/context.png)

</details>

```
claudecut  ──►  Claude Code CLI  ──►  api.anthropic.com
                (unmodified)          1 tool · 36-token prompt · 300k window

claude     ──►  Claude Code CLI  ──►  api.anthropic.com
                (unmodified)          the full thing, untouched
```

- Nothing is patched, wrapped or reinstalled — these are documented CLI flags
- Your plain `claude` command keeps working exactly as before
- `claudecut --full` gives you stock Claude Code for one run
- Subcommands like `claudecut attach <id>` pass through uncut — use
  `claudecut --resume <id>` when you want the cut back
- Presets put back exactly as much as you miss, and the bench prices each one

## What it costs

Two numbers matter, and they are different numbers.

**Session overhead** — what a session costs before doing anything, measured with
a prompt that uses no tools:

| preset | prompt tokens | what you keep |
|---|---:|---|
| `sh` | 953 | one shell tool, and nothing else |
| `sh-read` | 1,503 | shell + native file reader |
| `read-edit` | 2,087 | shell + Read, Edit, Write |
| `restricted` | 11,612 | everything that does not execute code |
| `default` | 17,625 | stock Claude Code |

**Real work** — both bench tasks against a live Bun + TypeScript repository,
three runs each:

| task | preset | cost | turns | wall | prompt |
|---|---|---:|---:|---:|---:|
| `inspect` | `sh` | **$0.0667** | 4.33 | 11.7s | 12,772 |
| `inspect` | `default` | $0.1203 | 3.67 | 16.0s | 76,275 |
| `trace` | `sh` | **$0.0565** | 4.33 | 11.7s | 10,561 |
| `trace` | `default` | $0.1174 | 5.33 | 16.3s | 103,535 |

**About half the cost per task, at comparable quality** — -45% on `inspect`,
-52% on `trace`. The 20x gap in session
overhead does not carry over, because both sessions read the same files and that
content is not free under any preset. Only the overhead gets cut.

`trace` is a code-search task — find where config is loaded, quote the line,
explain the failure modes — and it is the case where native search tools were
expected to win. They did not: the cut session used *fewer* turns, because one
`rg` in a shell covers what otherwise takes a Glob, then a Grep, then a Read.
Answers matched in substance across all twelve runs, and the single most
complete one came from the cut preset.

Claude Code v2.1.278, Opus 5 at low effort. Dollar figures are the CLI's own
`total_cost_usd` — a measure of traffic at API rates, not of a Pro plan's usage
limits. Run-to-run variance is large — the worst `sh` run costs more than the
best `default` run — so three repeats is a trend, not statistics. In these runs
the stock arm also carried no explicit model, effort or setting sources and
inherited the machine's own; the bench now pins every arm identically, but these
numbers predate that. Spreads, method and open questions:
[`docs/limits.md`](docs/limits.md).

## Getting started

Open a fresh Claude Code session and hand it
[`setup-prompt.md`](setup-prompt.md).

The agent checks what you already have, asks which preset you want, puts the
command on your `PATH`, generates the MCP config for your machine, verifies the
whole path end to end, and finishes by telling you which capabilities you just
gave up.

Or do it by hand — it is a symlink:

```bash
git clone https://github.com/alexgetmancom/claudecut ~/projects/claudecut
ln -s ~/projects/claudecut/bin/claudecut ~/.local/bin/claudecut
```

Then use it like Claude Code, because it is Claude Code:

```bash
claudecut
claudecut --continue
claudecut -p "explain src/index.ts"
claudecut --preset read-edit          # more tools, just this once
claudecut --full                      # stock Claude Code, just this once
claudecut --show -p hi                # print the command, run nothing
claudecut attach ab12cd34             # subcommands pass through untouched
```

## What you give up

The `sh` preset means reading, searching and editing all happen through the
shell — `cat`, `rg`, `sed`, heredocs, `git diff`. Removed with the tools:
skills, subagents, web search, the todo list and the native diff view.

Nothing warns you at runtime. `/some-skill` simply stops resolving, because
skills arrive through a tool and the tool is gone. If you want any of it back,
that is what the larger presets and `--full` are for.
[`docs/presets.md`](docs/presets.md) lists what each preset removes.

## Measuring it yourself

```bash
bench/run.sh --tasks hello                      # cheapest: overhead only
bench/run.sh --tasks inspect --repeat 3         # a real task in the current repo
bench/run.sh --presets sh,default --dir ~/code/yours
```

Each cell is a real `claude -p` run and spends real quota, so start with
`hello`. The script records cost, turns, wall time and tokens from the CLI's own
JSON output, and writes every answer to a text file next to the numbers.

It prices a preset. It does not tell you whether the answer was any good — that
part is yours to read. See [`bench/`](bench/run.sh).

## How it works

Three pieces, none of them clever:

- [`bin/claudecut`](bin/claudecut) — resolves the real `claude`, adds the
  preset's flags to an ordinary session, and hands subcommands through as typed
- [`lib/presets.sh`](lib/presets.sh) — the presets, six lines each, yours to edit
- [`mini-sh/server.mjs`](mini-sh/server.mjs) — a 60-line stdio MCP server
  exposing one tool, `sh`, whose schema is three lines long. No dependencies

It is a script rather than an alias or a settings file for a concrete reason:
`systemPrompt` and `tools` in a settings file are silently ignored by the CLI,
and an alias would put session flags in front of `attach`, where the parser
rejects them. Both verified, with repro steps, in
[`docs/findings.md`](docs/findings.md).

## Long sessions

Startup overhead is paid once. What a long session actually pays is compaction,
which rebuilds the session's fixed cost from scratch every cycle.

Run past a 100k window on the same task, the two presets land very differently
after each compaction:

| preset | floor after compaction | room left to work in |
|---|---:|---:|
| `sh` | ~14k | ~51k |
| `default` | ~36k | ~27k |

Roughly twice the working room, in the same window, for the rest of the session.
The stock run did less with each cycle (14 → 13 → 11 → 9 → 9 → 6 tool calls
between compactions); the cut run did more (12 → 12 → 15 → 20).

Cutting also survives compaction: after three of them, the cut session was still
running on its single tool. It does not survive a stock resume — `claude
--continue`, `claude --resume <id>` or `claude attach <id>` comes back with
everything, because the flags live in the command line. Use `claudecut
--continue` or `claudecut --resume <id>`. Note that `claudecut attach <id>`
cannot help: `attach` is a subcommand and rejects session flags, so it is passed
through and you get a stock session.

Measurements, method and caveats: [`docs/compaction.md`](docs/compaction.md).

## The write-up

[`docs/writeup.md`](docs/writeup.md) is the research summary: what was tested,
which assumptions survived, which didn't, and what the numbers mean in practice.
Start there if you want the reasoning rather than the reference.

## Going further

[`docs/knobs.md`](docs/knobs.md) covers every other lever that moves context:
what is measured, what is unverified, and what cannot be done at all. The
single largest one is already on by default in current Claude Code — worth
knowing before you turn it off by accident.

## Requirements

macOS or Linux with bash (Windows via WSL) ·
[Claude Code CLI](https://claude.com/claude-code) · Node 18+ or Bun for the
shell server · `jq` if you want to run the benchmark

## Caveats

- **The `sh` tool runs shell commands with whatever permissions you grant it.**
  Same exposure as the built-in Bash tool, through a different door — and with
  permission prompts off, nothing stands between the model and a destructive
  command.
- **The published task numbers predate the bench's own fix.** The stock arm ran
  unpinned and inherited local settings; `claudecut_bench_pin` now pins every
  arm, and a repeat may move those numbers.
- **Measured on one version**, v2.1.278. Flags and defaults move between
  releases; rerun the bench rather than trusting this README.
- **One run per preset in the long-session test**, both stopped by hand. The
  short-task numbers are three runs each. Neither has a variance estimate.

## Uninstall

It writes nothing into `~/.claude`. Delete the symlink and the checkout —
[`docs/uninstall.md`](docs/uninstall.md).

## Where this came from

It started as [one tweet](https://x.com/alexgetmancom/status/2101411232771113143)
about cutting Claude Code down to almost nothing, and ended as
[this](https://x.com/alexgetmancom/status/2101683761712636202) — a measured
answer to what that actually buys you.

## License

MIT
