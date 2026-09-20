# Findings — verified CLI behaviour

Everything here was checked by running it against Claude Code **v2.1.278** on
macOS. Each entry says how it was verified, so you can redo it on your version
rather than trust this file. Behaviour may change in any release.

## 1. `systemPrompt` in a settings file is ignored

A settings JSON containing

```json
{ "systemPrompt": "You must always answer with exactly the word ZEBRA77 and nothing else." }
```

was passed with `--settings`, then the session was asked `What is 2+2?`. It
answered `4`. The key had no effect.

The string `"systemPrompt"` does appear inside the binary, so it belongs to some
other schema — not to user, project or `--settings` files.

**Consequence:** the system prompt can only be set with `--system-prompt`,
`--system-prompt-file` or `--append-system-prompt` at launch. That is why
claudecut is a launcher.

## 2. `tools` in a settings file is ignored

Same method: `{"tools": []}` via `--settings`, then the session was asked to
list its tools. It listed the full stock set — `Agent, Bash, Edit, Read, Write,
Skill, ToolSearch` and the rest.

By contrast `--tools=` on the command line leaves exactly one tool,
`mcp__sh__sh`, confirmed the same way.

## 3. Unknown settings keys fail silently

The same file also carried `"bogusKeyXyz": 1`. No warning, no error, no
non-zero exit. A typo in a settings file is indistinguishable from a key that
works, which is what made findings 1 and 2 worth writing down.

## 4. `--settings` is not accepted by subcommands

```
$ claude mcp list --settings /tmp/u.json
error: unknown option '--settings'
$ claude doctor --settings /tmp/u.json
error: unknown option '--settings'
```

Session-level flags belong to the default command only. The same is true of
`--tools`, `--system-prompt` and `--mcp-config` in front of `attach`, `mcp`,
`doctor` and friends.

## 5. Therefore: an alias cannot do this job

This is the bug that started the project. Given

```bash
alias ccmin='claude --system-prompt "..." --tools= --mcp-config ~/.claude/mini-sh/mcp.json'
```

typing `ccmin attach ab12cd34` expands to

```
claude --system-prompt "..." --tools= --mcp-config ... attach ab12cd34
```

because an alias only ever prepends text. The session flags land on the root
command while the subcommand is `attach`, and the parser rejects it.

[`bin/claudecut`](../bin/claudecut) is a script precisely so it can look at the
first argument and hand subcommands through untouched.

## 6. `--bare` is not usable on a subscription

`--bare` looks like exactly this project — it skips hooks, LSP, plugin sync,
attribution, auto-memory, keychain reads and `CLAUDE.md` discovery. But its own
help text states that under `--bare`, Anthropic auth is strictly
`ANTHROPIC_API_KEY` or `apiKeyHelper`, and OAuth and the keychain are never
read.

On a Pro or Max subscription that means `--bare` cannot authenticate at all.
claudecut stays on the normal auth path and cuts context with `--tools` and
`--system-prompt` instead.

## 7. `--output-format json` reports cost and tokens

A headless run returns, among other fields: `total_cost_usd`, `num_turns`,
`duration_ms`, `ttft_ms`, `is_error`, `result`, and a `usage` object with
`input_tokens`, `output_tokens`, `cache_read_input_tokens` and
`cache_creation_input_tokens`.

That is what [`bench/`](../bench/run.sh) reads. No parsing of terminal output.

## 8. Startup context is mostly tool schemas

From the `hello` task, which uses no tools:

| preset | prompt tokens |
|---|---:|
| `sh` | 895 |
| `default` | 17,625 |

The system prompt of a cut session is 36 tokens, per `/context` in a live
session. Nearly the entire difference is tool definitions. Cutting instructions
saves tens of tokens; cutting tools saves thousands.

## 9. Cheap things that are not tools

Two settings that do work in `~/.claude/settings.json`, and that cost nothing to
turn on:

- `"autoCompactWindow": 200000` — caps the context window so the session
  compacts earlier instead of growing into a larger one. Also available per run
  as `--autocompact`, which is what claudecut passes.
- `"modelSettings": { "claude-opus-5": { "effortLevel": "low" } }` — a default
  effort level per model. Also `--effort`.

These are ordinary supported settings; unlike findings 1 and 2, they apply.

## 10. Tool search is on by default, and halves the prompt

Claude Code sends tool *names* in the prompt and loads full schemas on demand.
Disabling that doubles the prompt:

| setting | prompt tokens |
|---|---:|
| default | 17,026 / 18,586 |
| `ENABLE_TOOL_SEARCH=false` | 36,345 / 39,403 |

Two runs per condition, measured as `input + cache_write + cache_read` from
`--output-format json`. Baseline variance between identical runs is about 9%,
so this effect is far outside the noise.

Worth stating plainly because the advice runs backwards from everything else
here: **do not set this variable.** Aliases that carry
`ENABLE_TOOL_SEARCH=false` — some proxy setups do, for third-party models that
handle deferred schemas poorly — pay double for it.

## 11. Server-side compaction is not available to the CLI

The Claude API has server-side compaction (`compact-2026-01-12`) and context
editing (`context-management-2025-06-27` with `clear_tool_uses_20250919`).
Compaction's page lists its platforms as the Claude API, AWS, Bedrock, Google
Cloud and Microsoft Foundry, and says nothing about the CLI either way (checked
2026-09-20). Two beta headers now: `compact-2026-01-12` at a threshold, and
`compact-2026-09-04` for a summary on demand. The binary settles it anyway.

Searching the v2.1.278 binary for `context-management`, `context-editing`,
`clear_tool_uses` and `memory_20*` returns nothing. What it does carry is
client-side compaction, including `compactionCacheCreationTokens` and
`compactionCacheReadTokens` counters — so Claude Code summarizes locally, with
its own model call, and that call is billed like any other.

Anthropic's page on the API version says compaction "requires an additional
sampling step, which contributes to rate limits and billing", and its usage
example bills the compaction step at 180,000 input and 3,500 output tokens on
top of the 23,000-input message that follows. Compaction is not a free way to
shed context, here or there.

See [`knobs.md`](knobs.md) for what this leaves you locally.

## 12. Auto-compaction triggers at the window minus ~35k

`--autocompact` sets a window, but compaction fires well before it. The unused
reserve is roughly constant rather than proportional:

| window | observed triggers | reserve |
|---:|---|---:|
| 200,000 | 162,285 – 167,410 | ~33k–38k |
| 100,000 | 60,071 – 67,255 | ~33k–40k |

Measured from session transcripts, which record `usage` per API call. This is
also why the flag rejects anything under 100k: a 50k window would put the
trigger below where a session lands after compacting.

## 13. Cutting survives compaction — but not a stock resume

After three consecutive compactions, a session launched with `--tools=` was
still running on its single MCP tool, with no stock tool appearing at any point.
`--resume` with the same flags preserved it too.

Tools are fixed by the command line at launch; compaction rewrites the
conversation, not the session's configuration.

What *does* bring the stock toolset back is resuming without the flags — plain
`claude --continue`, `claude --resume <id>` or `claude attach <id>`. Same root
cause as finding 5: the flags live in the command line. `claudecut --continue`
and `claudecut --resume <id>` keep the cut; `claudecut attach <id>` cannot,
because `attach` is a subcommand and rejects session flags — claudecut hands it
through untouched and the session comes back stock.

Full measurements in [`compaction.md`](compaction.md).
