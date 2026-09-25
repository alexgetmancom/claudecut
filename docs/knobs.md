# Knobs — everything that moves context

Ways to make a Claude Code session cheaper, sorted by how much they actually do.
Each entry says how it was checked.

Measured on Claude Code **v2.1.278**, macOS, Opus 5 at low effort. Numbers are
prompt tokens for a one-turn run that uses no tools: `input + cache_write +
cache_read` from `--output-format json`.

> **Run-to-run variance is about 9%.** Identical baseline runs came out at
> 17,026 and 18,586 tokens. Anything below roughly 2k tokens cannot be resolved
> with single runs, which is why several entries below say "not resolved"
> rather than "no effect".

## Tier 1 — the large ones

### Tool search is already saving you half the context

Claude Code defers tool schemas: the prompt carries tool *names*, and the full
schema loads on demand. It is on by default in this version.

| setting | prompt tokens |
|---|---:|
| default (tool search on) | 17,026 / 18,586 |
| `ENABLE_TOOL_SEARCH=false` | 36,345 / 39,403 |

**Turning it off doubles your context.** Measured twice each, and the effect is
far outside the noise floor.

The practical advice is the inverse of the rest of this page: do not set this
variable. If you copied an alias from somewhere that sets
`ENABLE_TOOL_SEARCH=false` — some proxy setups do, for models that handle
deferred schemas poorly — that alias is paying double.

### Cutting tools

`--tools=` and its variants, which is what the presets do. 17,625 → 953 tokens
for the `sh` preset. See [`presets.md`](presets.md).

Note `--tools` is a **whitelist**. There is no syntax for removing one tool from
the default set; you name the ones you keep.

### Capping the context window

`--autocompact 300000`, or `"autoCompactWindow"` in settings. This does not
shrink the prompt — it decides when the session compacts instead of growing
further. **If both are set, the setting wins and the flag is ignored**, which is
worth knowing before you conclude a cap did nothing.

claudecut passes 300k (`CLAUDECUT_AUTOCOMPACT` in
[`lib/presets.sh`](../lib/presets.sh)). A smaller window caps what any single
turn can cost; a larger one compacts less often, and each compaction is what
forces the model to re-establish where it was. The measurements below were taken
at 100k and 200k — the reserve is the same at any window.

Compaction fires at **the window minus roughly 35,000 tokens**, a fixed reserve
rather than a percentage, which is why values under 100k are rejected.

**The window is the largest single lever there is, and it cuts the other way
from what "bigger is better" suggests.** A token that lands in the context is
re-read by every later request until the next compaction, so a wider window does
not just delay compaction — it multiplies the price of everything already in
there. Read back from one 1,467-call session (`363cfbcf`, `sh` preset, 300k
window, four cycles):

| | measured |
|---|---|
| floor after compaction | 15,177 tokens |
| context growth | 712 tokens per call |
| total context reads | 213,112,488 |

Those three numbers predict the session at any window (`N·floor +
N·growth·L/2`, with cycle length `L = (W − 35k reserve − floor) / growth`); at
300k the model lands on 205M against the 213M actually paid, so it is worth
trusting for the shape if not the last digit:

| window | calls per cycle | compactions | predicted context reads |
|---:|---:|---:|---:|
| 150k | 140 | 10.5 | 95M |
| 200k | 211 | 7.0 | 132M |
| 250k | 281 | 5.2 | 169M |
| 300k | 351 | 4.2 | 206M |
| 400k | 492 | 3.0 | 279M |

Going from 300k to 200k is about a third off the whole session; the extra
compactions cost one summarising pass each (~8k of output over a full window)
plus whatever re-discovery follows, which in that session was 0–8 calls. What a
small window actually costs is not tokens but continuity: everything the model
knew and did not write down is re-derived, and no measurement here scores that.
claudecut ships 300k because losing the thread is worse than paying for it; the
table is here so the choice is yours and priced.

What survives compaction is the session's fixed cost — system prompt and tool
schemas — and it is rebuilt after every single compaction. Measured floors:
about 14k for the `sh` preset against about 36k for stock. In a 100k window that
is ~51k of usable room per cycle against ~27k.

This is where cutting tools pays off most: startup overhead is paid once, but
the floor comes back for the rest of the session. See
[`compaction.md`](compaction.md).

## Tier 2 — measured, small

| knob | effect |
|---|---|
| `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1` | −1.5k to −2k, at the edge of noise |
| `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` | not resolved; the test repo has no `CLAUDE.md`. In a repo with a large one, this is worth its size |
| `ENABLE_LSP_TOOL=false` | not resolved |
| `CLAUDE_CODE_ENABLE_TODO_TOOLS=false` | not resolved |

A large `CLAUDE.md` is loaded into every session in that project, so its cost is
simply its length. Measure your own with `wc -c` before deciding.

## Surveying a file without paying for it 300 times

The most expensive thing a long session does is read a large file early and
carry it to the next compaction. In the measured session one 1,201-line module
was read in four chunks near the start of a cycle; those four results were
re-read 270–340 times each, for about **3.5M context reads** — more than the
entire session's compaction summaries put together.

The shell can avoid that without restoring the `Agent` tool, because
`claude -p` is just a command:

```bash
claude --tools= --strict-mcp-config --mcp-config mini-sh/mcp.json \
  --allowedTools mcp__sh__sh --system-prompt "$CLAUDECUT_SYSTEM_PROMPT" \
  -p 'Survey src/events/render/discord.ts: in at most 10 lines, say what it
      does, name its exported functions and where they are called from.'
```

The file lands in the child session's context. The parent gets the answer.
Measured on the same module (now 423 lines), one run:

| | tokens the parent carries | what it cost |
|---|---:|---|
| reading the file in the parent | ~4,000, re-read to the next compaction | the whole point of this page |
| the child's answer instead | **242** | 2 turns, 12.4s, $0.12 of the child's own traffic |

Two honest limits. A summary is thinner than the source, so if the work later
turns on a detail the summary dropped, the file gets read anyway and the survey
was pure overhead — this suits *"what is in this module and who calls it"*, not
*"change this function"*. And the child pays its own startup, 953 tokens, on
every invocation, so surveying three small files in three child sessions is
worse than one `cat` of all three.

Nothing in claudecut enables or requires this; the shell already allows it. It
is written down because it is the one lever left that changes the shape of a
session rather than its settings.

## What the project itself costs you

Nothing in this section is a claudecut setting. It is the other half of the
bill, and on a long session it is the larger half: **57% of all context reads in
the measured session were command output, and 31% were the commands themselves.**
A repository that prints densely is cheaper to work in than one that prints
prettily, and the difference is paid on every request until the next compaction.

Read back from the same session (`363cfbcf`, 870 calls, 908 commands), with the
integrated cost — output size times the number of later requests that re-read
it:

| what | in that session | fix, generically |
|---|---:|---|
| pretty-printed JSON, one field per line | 2.46M reads | a compact or TSV output mode for anything an agent calls |
| timestamped log lines inside test runs | 1.45M reads | quiet the logger under the test runner |
| the runner echoing each step (`$ bun …`, `$ tsc …`) | 568k reads | the runner's own quiet flag (`bun run --silent`, `npm --silent`) |
| an absolute repo path written into every command | 3.1M reads | nothing to fix in the project — see `CWD` below |
| per-test tick lines, banners, blank lines | 196k reads | leave them, they are cheap and they help |

That is ~4.7M reads of pure noise, about 2.2% of the session, and every line of
it was avoidable without losing a single fact. The rule of thumb that falls out:
**a human reader wants whitespace, an agent wants one line per record.**

What is *not* worth optimising, measured in the same session: whole-file writes
(88 of them, but 84 were a file's first version — the text has to be sent once,
and re-sending an existing file happened 4 times) and the choice between a
targeted patch and a rewrite (11.9M against 10.4M reads — what costs is the
payload, not the method).

## The shell the one tool runs in

Not a context knob — a round-trip knob. A failed command costs a full pass over
the context window and a retry, so a shell quirk is paid at the same rate as a
tool schema, over and over.

Read back from one 870-call session in a Bun + TypeScript repo (session
`363cfbcf`, `sh` preset, Opus 5, three compactions), **36 calls — 4% — failed
for reasons that had nothing to do with the task**:

| failures | cause |
|---:|---|
| 14 | `zsh:1: === not found` — zsh expands a leading `=` as a filename, so `echo === x ===` dies |
| 12 | `no matches found: --include=*.ts` — zsh aborts a command when an unquoted glob matches nothing |
| 8 | `command not found: timeout` — macOS ships no `timeout` |
| 2 | `command not found: compgen` — a bash builtin, absent in zsh |

`mini-sh/server.mjs` now prefixes every command with a prelude that disables the
two zsh misfeatures (`setopt NO_NOMATCH NO_EQUALS`, silently ignored by other
shells) and defines a `timeout` shim over `perl -e 'alarm shift; exec @ARGV'`
when the real one is missing. The shim exits 142 on expiry where GNU `timeout`
exits 124; the limit itself is real.

Switching the default shell to bash instead would be worse on macOS: `/bin/bash`
is 3.2.57, with no associative arrays, no `${var,,}` and no `mapfile`, and it
reads none of a zsh user's rc files — in a clean environment `bash -lc` resolves
`python3` to `/usr/bin/python3` where `zsh -lc` resolves the Homebrew one.

| knob | default |
|---|---|
| `CLAUDECUT_CWD` | where claudecut was launched; every command starts there, and the tool description says so, which is what stops the model writing `cd /absolute/path &&` in front of 894 commands out of 908 |
| `CLAUDECUT_SHELL` | `zsh` |
| `CLAUDECUT_SH_PRELUDE` | the prelude above; set it empty to run commands verbatim |
| `CLAUDECUT_SH_TIMEOUT_MS` | `600000` |
| `CLAUDECUT_SH_MAX_OUTPUT` | `60000` characters, clipped head and tail |

## Tier 3 — present in the binary, unverified

These strings exist in the v2.1.278 binary but were not tested here. They are
**undocumented internals**: they can be renamed or removed in any release, and
nothing warns you when one stops working.

```
DISABLE_PLUGIN_AUTOLOAD
CLAUDE_CODE_SKIP_PLUGIN_MCP_SERVERS
CLAUDE_CODE_DISABLE_AUTO_MEMORY
CLAUDE_CODE_DISABLE_ORG_MEMORY
CLAUDE_CODE_DISABLE_CLAUDE_CODE_SKILL
CLAUDE_CODE_DISABLE_CLAUDE_API_SKILL
CLAUDE_CODE_DISABLE_POLICY_SKILLS
CLAUDE_CODE_MAX_CONTEXT_TOKENS
CLAUDE_CODE_AUTO_COMPACT_WINDOW
MAX_MCP_OUTPUT_TOKENS
DISABLE_AUTO_COMPACT
DISABLE_COMPACT
```

`MAX_MCP_OUTPUT_TOKENS` is the interesting one for long sessions: it caps how
much a tool result can add to the transcript. Session overhead is a one-time
cost; a single `cat` of a large file is not.

The twelve above are a hand-picked subset. The binary carries roughly 150 more
environment names that touch context, tools, memory, skills, caching and
thinking; regenerate the current list for your own version with:

```bash
strings -a "$(readlink -f "$(command -v claude)")" \
  | grep -oE '\b(CLAUDE_CODE|MAX|DISABLE|ENABLE)[A-Z0-9_]{3,45}\b' | sort -u \
  | grep -iE 'CONTEXT|COMPACT|REMIND|OUTPUT|MCP|TOOL|SKILL|PROMPT|THINK|CACHE|SUMMAR'
```

Names worth knowing about, all unverified unless noted:

| name | what it looks like it does |
|---|---|
| `CLAUDE_CODE_TOTAL_TOKENS_REMINDER` | the `<total_tokens>N tokens left</total_tokens>` line injected through a session — 951 of them in a measured 1,579-call session, ~12 tokens each. **Tested once**: `=0` changed nothing, `=false` halved the count in a single run. One run is not evidence, and the ceiling is ~1% either way |
| `CLAUDE_CODE_SILENT_TURN_REMINDER` (+ `_TEXT`, `_TURNS`) | another injected reminder, with its text and cadence |
| `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS` | the `Read` tool's ceiling, the native counterpart of `MAX_MCP_OUTPUT_TOKENS` |
| `CLAUDE_CODE_MAX_MCP_DESCRIPTION_LENGTH` | how much of an MCP tool's description survives into the schema |
| `MAX_THINKING_TOKENS`, `CLAUDE_CODE_DISABLE_THINKING`, `DISABLE_INTERLEAVED_THINKING` | thinking budget. Worth knowing that in the measured session **thinking cost 407k output tokens and zero context**: it is not carried into later requests, so it is paid once and never re-read |
| `CLAUDE_CODE_PROMPT_CACHE_TTL`, `ENABLE_PROMPT_CACHING_1H` | cache lifetime. In the measured session three breaks outlived the cache and forced 452k tokens of prefix to be re-created at the 1.25x rate — about 2% of the weighted bill, and the only fix is not taking breaks |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, `CLAUDE_CODE_POST_TURN_MEMORY` | the memory features, which inject context of their own |

Supported flags in the same area, which are documented in `claude --help` and
safe to rely on:

- `--restricted` — keeps every tool except those that execute code
- `--setting-sources` — chooses which settings files load at all
- `--bare` — skips hooks, LSP, plugin sync, auto-memory and `CLAUDE.md`
  discovery. **Not usable on a subscription:** under `--bare` authentication is
  strictly `ANTHROPIC_API_KEY` or `apiKeyHelper`, and OAuth is never read

## Tier 4 — things you cannot do from the CLI

### Server-side compaction

The Claude API has server-side compaction: the `compact-2026-01-12` beta header
with a `compact_20260112` strategy in `context_management.edits`, which
summarizes the conversation on the server past a configurable threshold.

The page lists its platforms as the Claude API, Claude Platform on AWS, Amazon
Bedrock, Google Cloud and Microsoft Foundry — no CLI, and it says nothing either
way about subscription plans (checked 2026-09-20). The reason it does not reach
claudecut is simpler and does not depend on the docs: the flag does not exist in
the CLI, and the beta header is not in the binary.

Worth knowing regardless, because the billing is documented and it confirms what
compaction costs in general: it "requires an additional sampling step, which
contributes to rate limits and billing", and the total for a request is summed
across `usage.iterations`. The page's own usage example shows the compaction
iteration billing 180,000 input and 3,500 output tokens alongside a 23,000-input
message — the whole history being summarized, charged as input, on top of the
message that follows. Re-applying an existing compaction block is free;
producing a new one is not.

Since 2026-09-04 there is also a second beta header, `compact-2026-09-04`, which
asks for a summary on demand instead of at a threshold: the request is separate
from the conversation, returns only a signed compaction block, and can run in
the background. Same story for claudecut — it is a Messages API parameter, and
the CLI has no flag for it.

Claude Code compacts client-side instead — the binary carries
`compactionCacheCreationTokens` and `compactionCacheReadTokens` counters, and no
`context-management` or `clear_tool_uses` beta headers appear in it at all.

The consequence for a $20 plan: **compaction is not free, so triggering it
often is a real cost.** A measured run billed 3.6M prompt tokens for three
compaction cycles on a cut session and 5.8M for five on a stock one — see
[`compaction.md`](compaction.md).

### Context editing (`clear_tool_uses`)

The other API-side feature: `context-management-2025-06-27` with
`clear_tool_uses_20250919` drops old tool *results* from the context while
keeping the conversation, with knobs for how many recent ones to keep and which
tools to exclude.

This is precisely what bloats a long agentic session, and it is also API-only.
The closest local equivalent is keeping tool output small in the first place —
one `rg` with a narrow pattern instead of `cat` on a whole file.

## Measuring a knob yourself

```bash
env VAR=value claude --output-format json -p "Reply with exactly: ok" \
  | jq '.usage | .input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens'
```

Run it at least three times per condition. A single pair of numbers cannot tell
a 2k difference from noise.

## Sources

- [Compaction — Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/compaction)
- [Context editing — Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/context-editing)
