# Presets — what each cut costs, and what it breaks

A preset is a set of stock Claude Code flags. Pick one with `--preset`, or set
`CLAUDECUT_PRESET` in `~/.config/claudecut/config.sh`. The definitions live in
[`lib/presets.sh`](../lib/presets.sh) — six lines each, edit them freely.

## The numbers

This table is **session overhead**: what a session costs before it has done any
work. A real task adds file contents and command output, which cost the same
under every preset, so measured end to end a cut session comes out about 2x
cheaper per task — see [`docs/limits.md`](limits.md).

Measured with `bench/run.sh --tasks hello`, which sends a prompt that needs no
tools at all (`Reply with exactly: ok`). It isolates what a session costs before
it has done anything: the system prompt plus every tool schema.

| preset | prompt tokens | cost of one trivial turn | vs. stock |
|---|---:|---:|---:|
| `sh` | 953 | $0.0096 | 18x smaller |
| `bash` | 2,079 | $0.0209 | 8.5x |
| `sh-read` | 1,503 | $0.0151 | 12x |
| `read-edit` | 2,087 | $0.0210 | 8x |
| `restricted` | 11,612 | $0.0465 | 1.5x |
| `default` | 17,625 | $0.0990 | — |

`bash` is now measured, and it is the more expensive of the two one-shell
presets: Claude Code's own Bash schema costs about **1,200 tokens more per
request** than mini-sh's three lines, and that difference is paid on every single
request for the life of the session. On the `inspect` task, two runs per arm,
`sh` averaged 7.2k prompt tokens against 10.9k for `bash` at equal answer
quality — directionally 20–50% more, though the spread between identical runs is
wide enough that only the fixed 1.2k above should be treated as solid.

Claude Code v2.1.278, Opus 5 at low effort, one run each. Reproduce with
`bench/run.sh --tasks hello --repeat 5`, and expect your own numbers to differ:
model, effort, plugins, MCP servers and `CLAUDE.md` all move them.

A live interactive session is leaner than these headless figures — the `/context`
readout for `sh` shows ~1.8k total, of which 36 tokens are the system prompt.
Headless `-p` adds machinery of its own. Compare presets to presets, not to a
screenshot.

## What each preset is

### `sh` — one tool

```
--tools= --strict-mcp-config --mcp-config mini-sh/mcp.json
```

`--tools=` removes every built-in tool. The only thing left is `sh` from the
MCP server in [`mini-sh/`](../mini-sh/server.mjs), whose schema is three lines.
Reading, searching, editing and running tests all go through the shell:
`cat`, `rg`, `sed`, `git`, your test runner.

**Gone:** Read, Edit, Write, Bash, Grep, Glob, WebFetch, WebSearch, Task/Agent
(no subagents), Skill (no skills, no `/skill-name`), TodoWrite, NotebookEdit.

**Costs you:** no parallel subagents, no skills or plugins, no web access, no
native diff view on edits. The model writes files with heredocs, and you review
them with `git diff` like any other change.

**Suits:** work in one repo where you already know your way around, and where
the shell is the interface you would have reached for anyway.

### `bash` — the native shell instead of ours

```
--tools=Bash
```

The same bet as `sh` — one tool, and it is a shell — but Claude Code's own Bash
tool rather than [`mini-sh`](../mini-sh/server.mjs), so there is no MCP server
to launch and no `--mcp-config`. What you give up is everything mini-sh does on
top of a bare shell: the zsh prelude that stops an unquoted glob or a leading
`=` from killing a command, the `timeout` shim macOS otherwise lacks, and
output clipped head-and-tail instead of from one end. Those exist because a
measured session lost 4% of its calls to their absence — see
[`docs/knobs.md`](knobs.md#the-shell-the-one-tool-runs-in).

Against that, the native tool is better integrated: the permission prompts are
the ones you know, and its schema is Anthropic's rather than our three lines.
That schema is also the whole cost difference — 2,079 prompt tokens against 953,
measured on `hello`.

**Suits:** wanting one shell and no MCP process at all, or checking how much of
`sh`'s cost is the MCP boundary.

### `sh-read` — one tool plus the reader

```
--tools=Read
```

Adds back the native reader: line-numbered output, images and PDFs, and the
harness tracking which files have been read. Costs about 600 tokens over `sh`.

**Suits:** anything where you read far more than you run.

### `read-edit` — native file tools

```
--tools=Read,Edit,Write
```

Proper edits: exact-match replacement, a rendered diff, the permission prompt
you expect on a write. The shell is still there for everything else.

**Suits:** normal editing sessions where you want the diff UI back but still
refuse to pay for search, web and subagent tooling.

### `restricted` — everything except execution

```
--restricted
```

A stock Claude Code flag, not ours: it keeps every built-in tool but removes the
ones that run commands or code. Here that pairs oddly with an MCP shell — the
shell comes back in through MCP — so treat this preset as the honest baseline it
is: it shows that most of the context cost is not Bash. At 11.6k tokens it is
still two thirds of stock.

**Suits:** measuring. Rarely what you actually want to run.

### `default` — stock Claude Code

No flags. The baseline every other row is compared against. Reach it any time
with `claudecut --full`.

## Rolling your own

Add a case to `claudecut_preset_flags` in [`lib/presets.sh`](../lib/presets.sh):

```bash
review) printf '%s\n' "${common[@]}" --tools=Read,Grep,Glob ;;
```

Tool names are the ones Claude Code uses internally — ask a stock session to
list its tools and you get the current set for your version. Then measure it:

```bash
bench/run.sh --presets review,sh,default --tasks hello --repeat 3
```

Two things worth knowing before you cut further:

- **`--tools=` is a whitelist, not a blacklist.** There is no way to subtract
  one tool from the default set; you name what you keep.
- **Some capabilities are tools.** Skills arrive through `Skill`, subagents
  through `Agent`, todo lists through `TodoWrite`. Cutting the tool cuts the
  feature, silently — nothing warns you that `/some-skill` no longer resolves.
