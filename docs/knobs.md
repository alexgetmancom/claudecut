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

`--tools=` and its variants, which is what the presets do. 17,625 → 895 tokens
for the `sh` preset. See [`presets.md`](presets.md).

Note `--tools` is a **whitelist**. There is no syntax for removing one tool from
the default set; you name the ones you keep.

### Capping the context window

`--autocompact 100000`, or `"autoCompactWindow"` in settings. This does not
shrink the prompt — it decides when the session compacts instead of growing
further.

Compaction fires at **the window minus roughly 35,000 tokens**, a fixed reserve
rather than a percentage, which is why values under 100k are rejected.

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
