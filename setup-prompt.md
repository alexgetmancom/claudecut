# claudecut — setup and management

Give this file to a fresh Claude Code session, whether you are installing for
the first time or changing an existing setup. The agent works out which case it
is on its own.

---

Set up a `claudecut` command on my machine that runs the stock Claude Code CLI
with most of its tool surface removed, so a session starts at roughly 1k tokens
instead of roughly 18k. Do not patch, wrap, or reinstall Claude Code itself, and
do not change how my plain `claude` command behaves.

## Step 0 — inspect, then ask

**Establish what already exists.** Do not assume a fresh install, and do not
assume an existing one:

- Where does `claude` resolve to, and what does `claude --version` print?
- Is there a checkout of this repository on the machine already, and is
  `claudecut` on `PATH` or defined in my shell startup files?
- Does `~/.config/claudecut/config.sh` exist, and what does it set?
- Do I have `node` (18+) or `bun`? Do I have `jq`, which the benchmark needs?
- Does `~/.claude/settings.json` already set `autoCompactWindow` or
  `modelSettings`? Report the values, never the whole file.
- Which name do I want for the command, if `claudecut` is taken? Check with
  `command -v` and by grepping my startup files before claiming a name is free.

Show me the current state as a short table. If nothing exists, say so in a line.

**Then ask me what I want,** and wait:

- **Install** the command for the first time
- **Change the default preset**, or add a preset of my own
- **Retune** — system prompt, auto-compact window, effort level
- **Remove** it

For an install or a preset change, also ask which preset should be the default,
and state the trade-off for each in one sentence. Do not editorialise beyond
that; [`docs/presets.md`](docs/presets.md) has the detail and the measured
numbers. The options are `sh`, `sh-read`, `read-edit`, `restricted`, `default`.

Make clear which capabilities a preset removes — skills, subagents, web access
and the todo list are tools, so cutting the tool cuts the feature with no
warning at runtime.

## Step 1 — get the files in place

Clone this repository somewhere permanent, or use the existing checkout if one
is already there. Do not copy the scripts into `~/.claude`: they are a launcher
that sits beside Claude Code, not part of it.

Verify the tree has `bin/claudecut`, `lib/presets.sh`, `mini-sh/server.mjs` and
`bench/`. Make the three scripts executable.

## Step 2 — put the command on PATH

Prefer a symlink into a directory already on my `PATH`:

```bash
ln -s /abs/path/to/claudecut/bin/claudecut ~/.local/bin/claudecut
```

If no suitable directory exists, add the repository's `bin/` to `PATH` in the
correct zsh startup file, matching the style of what is already there.

Do **not** create an alias. An alias can only prepend text, so `claudecut attach
<id>` would put session flags in front of a subcommand and fail — this is the
specific bug the script exists to avoid. See
[`docs/findings.md`](docs/findings.md) §5.

Do **not** name it `claude`, and do not shadow the real binary, unless I
explicitly ask for that and confirm I understand it would capture every script,
cron job and editor integration that calls `claude`.

## Step 3 — configure, if I asked for anything non-default

Write `~/.config/claudecut/config.sh` only if I chose something other than the
defaults. It is sourced by the launcher, so it holds shell variable assignments
and nothing else:

```bash
CLAUDECUT_PRESET=sh
CLAUDECUT_EFFORT=low
CLAUDECUT_AUTOCOMPACT=200000
CLAUDECUT_SYSTEM_PROMPT="Coding agent in a git repo. Be concise. Never run destructive git or rm without asking."
```

Never put these in `~/.claude/settings.json`. That scope captures the plain
`claude` command too, which is exactly the isolation this setup preserves. Note
also that `systemPrompt` and `tools` in a settings file are silently ignored by
the CLI — verified, see findings §1 and §2 — so a settings file could not do
this job even if the scope were acceptable.

If I want a preset of my own, add a case to `claudecut_preset_flags` in
`lib/presets.sh`, then measure it (step 5) rather than asserting it is cheaper.

## Step 4 — the one-tool MCP server

`bin/claudecut` generates `mini-sh/mcp.json` on first run, pointing at the
`node` or `bun` it finds and at `mini-sh/server.mjs` by absolute path. Let it.
Do not hand-write that file, and do not commit it.

Confirm the server runs at all before involving Claude Code:

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
  | node mini-sh/server.mjs
```

It must answer with a JSON-RPC result naming `serverInfo.name` as `sh`.

## Step 5 — verify, with commands you actually ran

Every claim must come from output you saw. Do not report success from reasoning:

- `claudecut --show -p hi` prints a command line carrying `--tools=`,
  `--system-prompt`, `--autocompact` and `--mcp-config`
- `claudecut --show attach ab12cd34` prints the bare binary with **no** session
  flags — this is the regression that matters most
- `claudecut --show --full -p hi` prints the bare binary too
- `claudecut -p "List the exact names of every tool you have, comma separated."`
  returns the one shell tool and nothing else
- `claude --version` and plain `claude -p "say ok"` still work exactly as before
- Any other command I already had still resolves where it did

Then run the cheapest benchmark cell and show me the table:

```bash
bench/run.sh --tasks hello --presets sh,default
```

Tell me what one trivial turn costs under each, from that run — not from the
numbers in this repository, which came from someone else's machine.

## Step 6 — tell me what I lost

Close by listing, in plain terms, the capabilities the chosen preset removed and
how to get each back for one session (`claudecut --full`, or `--preset` with a
larger preset). Do not oversell the setup. If I picked `sh`, say outright that
skills, subagents and web search are gone until I ask for them back.

## Changing an existing setup

- **Change preset:** edit `CLAUDECUT_PRESET` in the config file. One line.
- **Retune:** adjust `CLAUDECUT_*` variables. Add no new variable without a
  reason you can state. [`docs/knobs.md`](docs/knobs.md) lists every other lever
  that moves context, and which ones are measured.
- **Remove:** follow [`docs/uninstall.md`](docs/uninstall.md) — drop the PATH
  entry or symlink, delete the checkout, delete `~/.config/claudecut`. Ask
  before touching anything in `~/.claude`, since none of it belongs to this
  project.

Finish in one move: no TODOs, no stubs, no half-installed command.

## Constraints

- Never modify, patch, repackage or reinstall the Claude Code binary.
- Never write to `~/.claude/settings.json` unless I ask for it by name.
- Never print or log credentials, tokens, or the contents of settings files.
- Do not weaken permissions or sandbox settings to make something work. If a
  step needs a permission I have not granted, stop and tell me.
- Ask me only for genuine product choices. Verify every discoverable machine
  detail yourself instead of reasoning about it.
