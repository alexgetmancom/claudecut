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

**Open questions** — partly answered now:

1. ~~Does a cut session need more turns?~~ Yes — one extra on `inspect`, and it
   cost less than it saved. Whether that holds on longer tasks is unknown.
2. ~~Does output quality hold?~~ On one task, yes. On one task.
3. How much does losing subagents hurt on wide, search-heavy tasks? That is the
   case where stock Claude Code should win outright.
4. Does earlier compaction cost more than it saves? Each compaction is itself a
   model call over the whole transcript.

---

## Contributing a data point

Run the bench against a repository you actually work in, and open a PR adding a
dated entry with the summary table:

```bash
bench/run.sh --tasks inspect,trace --repeat 3 --dir ~/code/your-repo
```

Include your Claude Code version, model, effort level and plan. Numbers without
that context are not comparable to anything.
