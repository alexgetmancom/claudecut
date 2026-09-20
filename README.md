# claudecut

Run **Claude Code** with almost everything cut away.

Same CLI, same account, same auth — but the session starts with one tool instead
of twenty, a 36-token system prompt instead of the default one, and a context
window capped so it compacts early instead of quietly growing into your limits.

A trivial turn costs **$0.0090 instead of $0.0990**, and the prompt on the wire
is **895 tokens instead of 17,625**.

![A cut session, as /context reports it](docs/context.png)

```
claudecut  ──►  Claude Code CLI  ──►  api.anthropic.com
                (unmodified)          1 tool · 36-token prompt · 200k window

claude     ──►  Claude Code CLI  ──►  api.anthropic.com
                (unmodified)          the full thing, untouched
```

- Nothing is patched, wrapped or reinstalled — these are documented CLI flags
- Your plain `claude` command keeps working exactly as before
- `claudecut --full` gives you stock Claude Code for one run
- Subcommands like `claudecut attach <id>` pass through uncut, which is the one
  thing an alias cannot do
- Presets let you put back exactly as much as you miss, and measure the cost

## What gets cut

| preset | prompt tokens | one trivial turn | what you keep |
|---|---:|---:|---|
| `sh` | 895 | $0.0090 | one shell tool, and nothing else |
| `sh-read` | 1,503 | $0.0151 | shell + native file reader |
| `read-edit` | 2,087 | $0.0210 | shell + Read, Edit, Write |
| `restricted` | 11,612 | $0.0465 | everything that does not execute code |
| `default` | 17,625 | $0.0990 | stock Claude Code |

Measured on Claude Code v2.1.278, Opus 5 at low effort, one run each, with a
prompt that uses no tools. Reproduce them yourself in about ten seconds:
`bench/run.sh --tasks hello`. Details and trade-offs in
[`docs/presets.md`](docs/presets.md).

The `sh` preset means reading, searching and editing all happen through the
shell — `cat`, `rg`, `sed`, heredocs, `git diff`. In exchange you lose skills,
subagents, web search and the native diff view. That is a real trade, and
[`docs/presets.md`](docs/presets.md) spells out which features each cut removes.

## Getting started

Open a fresh Claude Code session and hand it
[`setup-prompt.md`](setup-prompt.md).

The agent takes it from there: it checks what you already have, asks which
preset you want, puts the command on your `PATH`, generates the MCP config for
your machine, verifies the whole path end to end, and finishes by telling you
plainly which capabilities you just gave up.

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

## Measuring it yourself

```bash
bench/run.sh --tasks hello                      # cheapest: fixed overhead only
bench/run.sh --tasks inspect --repeat 3         # a real task in the current repo
bench/run.sh --presets sh,default --dir ~/code/yours
```

Each cell is a real `claude -p` run and spends real quota, so start with
`hello`. The script records cost, turns, wall time and tokens from the CLI's own
JSON output, and writes every answer to a text file next to the numbers —
because it measures what a preset **costs**, never whether the answer was any
good. That part is still yours to read. See [`bench/`](bench/run.sh) and the
running log in [`docs/limits.md`](docs/limits.md).

## How it works

Three pieces, none of them clever:

- [`bin/claudecut`](bin/claudecut) — resolves the real `claude`, adds the
  preset's flags to an ordinary session, and hands subcommands through as typed
- [`lib/presets.sh`](lib/presets.sh) — the presets, six lines each, yours to edit
- [`mini-sh/server.mjs`](mini-sh/server.mjs) — a 60-line stdio MCP server
  exposing one tool, `sh`, whose schema is three lines long. No dependencies

Why a script and not an alias, and why not a settings file: both were tried and
both fail, for reasons documented with repro steps in
[`docs/findings.md`](docs/findings.md). Short version — `systemPrompt` and
`tools` in a settings file are silently ignored, and an alias puts session flags
in front of `attach`, where the parser rejects them.

## Requirements

macOS or Linux with bash (Windows via WSL) ·
[Claude Code CLI](https://claude.com/claude-code) · Node 18+ or Bun for the
shell server · `jq` if you want to run the benchmark

## Caveats

- **The `sh` tool runs shell commands with whatever permissions you grant it.**
  It is the same exposure as the built-in Bash tool, through a different door —
  and if you run with permission prompts off, nothing stands between the model
  and a destructive command. That is a choice you make, not one this repo makes
  for you.
- **Cutting tools cuts features silently.** Nothing warns you at runtime that
  `/some-skill` no longer resolves, because the `Skill` tool is gone.
- **Measured on one version.** v2.1.278. Flags and defaults move between
  releases; rerun the bench rather than trusting this README.
- **Cheaper per turn is not cheaper per task** if the model needs more turns to
  get there. That is the open question, and it is logged as open in
  [`docs/limits.md`](docs/limits.md).

## Uninstall

It writes nothing into `~/.claude`. Delete the symlink and the checkout —
[`docs/uninstall.md`](docs/uninstall.md).

## License

MIT
