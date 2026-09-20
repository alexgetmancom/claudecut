# The $20 experiment

An open log of how far a Claude Pro subscription stretches when every session
runs cut. Entries are appended, never rewritten. If something works worse this
way, it gets written down here too.

**Setup:** Claude Code v2.1.278 · Opus 5 at low effort · Claude Pro ($20/mo) ·
`sh` preset · 200k auto-compact window.

---

## 2026-09-20 — baseline

First measurements, on the `hello` task that uses no tools, so the number is
purely what a session costs before doing anything:

| preset | prompt tokens | cost of one trivial turn |
|---|---:|---:|
| `sh` | 895 | $0.0090 |
| `default` | 17,625 | $0.0990 |

Eleven times cheaper per turn, twenty times smaller on the wire. The saving is
almost entirely tool schemas, not instructions.

Worth stating plainly: this ratio applies to the *fixed overhead* of a session.
Real work adds file contents, command output and reasoning, which cost the same
under either preset. The advantage shrinks as a session gets longer — and the
200k window exists to stop sessions from getting that long in the first place.

---

## 2026-09-20 — first real task

The table above is fixed overhead. This is the same comparison on actual work:
the `inspect` task, run against [signal-forge](https://github.com/alexgetmancom/signal-forge),
a Bun + TypeScript repository. One run each.

| preset | prompt | out | turns | wall | cost |
|---|---:|---:|---:|---:|---:|
| `sh` | 15,072 | 803 | 5 | 13s | $0.0826 |
| `default` | 81,688 | 676 | 4 | 14s | $0.1700 |

**The advantage drops from 11x to 2.06x.** Both presets end up reading the same
files, and that content costs the same either way. The fixed overhead is what
gets cut; the work does not.

**The cut session did need an extra turn** — 5 against 4 — searching through the
shell where a native tool would have gone straight there. It did not erase the
saving, because an extra turn is cheap when every turn carries 15k instead of
82k. Wall time came out even.

**Quality held, on this task.** Both named the same entry point, the same CLI
surface, and the same two files to read first. They differed only on an optional
third suggestion: `sh` pointed at the poller and source registry, `default` at
the runbook. Both defensible, different angles.

**Do not over-read this.** One run, one task, one repository. Run-to-run
variance was not measured. Treat 2.06x as a first data point, not a result.

---

## 2026-09-20 — two tasks, three runs each

Same repository, both bench tasks, three repeats per cell. Twelve real runs.

| task | preset | cost | turns | wall | prompt | out |
|---|---|---:|---:|---:|---:|---:|
| `inspect` | `sh` | **$0.0667** | 4.33 | 11.7s | 12,772 | 628 |
| `inspect` | `default` | $0.1203 | 3.67 | 16.0s | 76,275 | 723 |
| `trace` | `sh` | **$0.0565** | 4.33 | 11.7s | 10,561 | 736 |
| `trace` | `default` | $0.1174 | 5.33 | 16.3s | 103,535 | 871 |

1.80x on `inspect`, 2.08x on `trace`. The single-run 2.06x held up.

**`trace` was supposed to be where the cut preset lost.** It is a code-search
task — find where configuration is loaded, quote the line, explain the failure
modes — and native search tools should have won it. They did not. The cut
session used *fewer* turns, 4.33 against 5.33. One `rg` in a shell appears to
cover what otherwise takes a Glob, then a Grep, then a Read: one round trip
instead of three.

The context gap widened to 10x on this task, because the stock session was
carrying 103k tokens per turn by the end of it.

**Quality: parity, checked by reading all six answers.** Every run of `trace`,
under both presets, landed on `src/config.ts:176`, quoted the same line, and
described the same failure modes — `ENOENT`, `SyntaxError`, `ZodError`, no
try/catch anywhere. The most complete answer came from `sh`, which also listed
all three callers of `loadConfig` with line numbers and noted they all call it
at module top level, so the process dies at startup. No `default` run did that.

**Variance is large and partly swallows the effect:**

```
inspect  default  [0.0748, 0.1835, 0.1027]
inspect  sh       [0.0639, 0.0862, 0.0501]
trace    default  [0.1620, 0.1022, 0.0881]
trace    sh       [0.0450, 0.0886, 0.0358]
```

The worst `sh` run ($0.0886) costs more than the best `default` run ($0.0748).
The mean favours `sh` in all four cells, but three repeats is a trend, not
statistics. There is no confidence interval here and it would be dishonest to
imply one.

**Open questions** — partly answered now:

1. ~~Does a cut session need more turns?~~ Mixed, and not in the expected
   direction: more on `inspect` (4.33 vs 3.67), fewer on the search-heavy
   `trace` (4.33 vs 5.33). Cheaper on both.
2. ~~Does output quality hold?~~ On two tasks, across six runs each, yes — with
   the best single answer coming from the cut preset.
3. How much does losing subagents hurt? Still open. Neither bench task is wide
   enough to need them; a task spanning many unrelated files would be.
4. Does earlier compaction cost more than it saves? Still open. No bench run
   here was long enough to compact even once.
5. New: how does this hold on a *long* session? Every measurement so far is a
   single-shot `-p` run. The overhead advantage is paid once per session, so it
   should decay as a session grows — and that is the shape of real work.

---

## Contributing a data point

Run the bench against a repository you actually work in, and open a PR adding a
dated entry with the summary table:

```bash
bench/run.sh --tasks inspect,trace --repeat 3 --dir ~/code/your-repo
```

Include your Claude Code version, model, effort level and plan. Numbers without
that context are not comparable to anything.
