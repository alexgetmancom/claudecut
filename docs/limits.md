# Measurements

What a cut session actually costs, measured rather than asserted. Every number
here comes from `bench/run.sh`, which reads cost and tokens out of the CLI's own
`--output-format json` — no parsing of terminal output, nothing estimated.

**Setup:** Claude Code v2.1.278 · Opus 5 at low effort · Claude Pro ($20/mo) ·
200k auto-compact window · test repository
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

1. **Long sessions.** Every measurement above is a single-shot `-p` run.
   Overhead is paid once per session, so the advantage should shrink as a
   session grows — and long sessions are what real work looks like.
2. **Subagents.** Neither bench task is wide enough to need them. A task
   spanning many unrelated files would be.
3. **Compaction economics.** No run here was long enough to compact even once.
   Compaction bills for the history it summarizes, so whether an early 200k
   window pays for itself is unmeasured. See [`knobs.md`](knobs.md).

## Contributing a data point

Run the bench against a repository you actually work in, and open a PR adding a
dated entry with the summary table:

```bash
bench/run.sh --tasks inspect,trace --repeat 3 --dir ~/code/your-repo
```

Include your Claude Code version, model, effort level and plan. Numbers without
that context are not comparable to anything.
