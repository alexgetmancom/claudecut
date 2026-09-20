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

**Open questions** — the honest list, none of them answered yet:

1. Does a cut session need more turns to finish the same task? Every saved
   token is wasted if the model has to grope around with `cat` and `rg` where a
   native tool would have gone straight there.
2. Does output quality hold? `bench/` measures cost, not correctness. Judging
   that still means reading the answers.
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
