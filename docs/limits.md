# Measurements

What a cut session actually costs, measured rather than asserted. Every number
here comes from `bench/run.sh` and `bench/longrun.sh`, which read cost and
tokens out of the CLI's own `--output-format json` and out of saved session
transcripts — no parsing of terminal output, nothing estimated.

**Setup:** Claude Code v2.1.278 · Opus 5 at low effort · Claude Pro ($20/mo) ·
200k auto-compact window for the short tasks, 100k for the long-session test ·
test repository
[signal-forge](https://github.com/alexgetmancom/signal-forge), Bun + TypeScript.

## Session overhead

The `hello` task sends `Reply with exactly: ok`, which needs no tools. The
number is purely what a session costs before doing anything.

| preset | prompt tokens | cost of one trivial turn |
|---|---:|---:|
| `sh` | 895 | $0.0090 |
| `default` | 17,625 | $0.0990 |

Twenty times smaller on the wire. Almost all of the difference is tool schemas,
not instructions: the cut session's system prompt is 36 tokens.

Overhead is paid once per session. It is the ceiling on what cutting tools can
save, not the saving itself.

## Real tasks

Two bench tasks, three repeats each, twelve runs total.

`inspect` asks the model to describe the repository, name its entry point and
pick two files to read first. `trace` asks where configuration is loaded from
disk, to quote the line, and to explain what happens when the file is missing or
malformed.

| task | preset | cost | turns | wall | prompt | out |
|---|---|---:|---:|---:|---:|---:|
| `inspect` | `sh` | **$0.0667** | 4.33 | 11.7s | 12,772 | 628 |
| `inspect` | `default` | $0.1203 | 3.67 | 16.0s | 76,275 | 723 |
| `trace` | `sh` | **$0.0565** | 4.33 | 11.7s | 10,561 | 736 |
| `trace` | `default` | $0.1174 | 5.33 | 16.3s | 103,535 | 871 |

**1.80x cheaper on `inspect`, 2.08x on `trace`.** Both presets read the same
files, and that content costs the same either way. Overhead is what gets cut;
the work does not.

The context gap is wider than the cost gap — 10x on `trace` — because the stock
session was carrying 103k tokens per turn by the end of the task while the cut
one carried 10k. Cost lags behind because most of those tokens are cache reads.

## Turns and search

A shell is not obviously worse at code search than native tools, and on these
tasks it was better. `trace` is the search-heavy one, and the cut session used
*fewer* turns — 4.33 against 5.33. One `rg` appears to cover what otherwise
takes a Glob, then a Grep, then a Read: one round trip instead of three.

On `inspect` the cut session used one turn more (4.33 vs 3.67) and was still
cheaper, because an extra turn is inexpensive when every turn carries 13k
tokens instead of 76k.

Wall time favoured the cut session on both tasks, by roughly 4 seconds.

## Quality

All twelve answers were read.

Every `trace` run under both presets landed on `src/config.ts:176`, quoted the
same line, and described the same failure modes — `ENOENT`, `SyntaxError`,
`ZodError`, no try/catch anywhere. The most complete answer came from `sh`: it
also listed all three callers of `loadConfig` with line numbers and noted that
they call it at module top level, so the process dies at startup. No `default`
run did that.

`inspect` answers matched on the entry point, the CLI surface and the two files
to read first, differing only on an optional third suggestion.

Parity on these tasks. Not a claim about every task.

## Long sessions

Everything above is a single-shot run. The behaviour that decides a long working
session is compaction, and it favours the cut preset more strongly than startup
overhead does.

Both presets were run past their context window on the same file-by-file audit
task, with `--autocompact 100000`:

| preset | floor after compaction | usable room per cycle |
|---|---|---:|
| `sh` | 13,440 · 21,532 · 8,416 | ~51k |
| `default` | 35,628 · 32,190 · 37,476 · 38,082 · 36,363 | ~27k |

The floor is what the session costs at the start of every cycle, rebuilt from
scratch after each compaction. It does not drift upward with repeated
compaction — both presets oscillate around a level set by the preset itself.

Work done between compactions moved in opposite directions: `sh` went
12 → 12 → 15 → 20 tool calls per segment, `default` went 14 → 13 → 11 → 9 → 9 → 6.

Full tables, method and caveats: [`compaction.md`](compaction.md).

## How much to trust this

Three repeats is a trend, not statistics. The per-run spread:

```
inspect  default  [0.0748, 0.1835, 0.1027]
inspect  sh       [0.0639, 0.0862, 0.0501]
trace    default  [0.1620, 0.1022, 0.0881]
trace    sh       [0.0450, 0.0886, 0.0358]
```

The worst `sh` run ($0.0886) costs more than the best `default` run ($0.0748).
The mean favours `sh` in all four cells, but there is no confidence interval
here and it would be dishonest to imply one. Run-to-run variance on identical
conditions is about 9%.

## Open questions

1. **Repeats on the long-session test.** One run per preset, both stopped by
   hand. The floor gap is far too large to be noise, but there is no variance
   estimate for it yet.
2. **Subagents.** Neither bench task is wide enough to need them. A task
   spanning many unrelated files would be.
3. **Window size.** Whether a smaller window beats a larger one over a whole
   session — more compaction cycles, but a smaller history summarized each time
   — is still unmeasured.
4. **Quality across compaction.** Both long runs were measured by cost and
   context, not by whether the audit they produced was correct.

## Contributing a data point

Run the bench against a repository you actually work in, and open a PR adding a
dated entry with the summary table:

```bash
bench/run.sh --tasks inspect,trace --repeat 3 --dir ~/code/your-repo
```

Long-session data points are just as welcome, and rarer:

```bash
bench/longrun.sh --dir ~/code/your-repo --window 100000
```

Include your Claude Code version, model, effort level and plan. Numbers without
that context are not comparable to anything.
