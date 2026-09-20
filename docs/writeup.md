# What we actually learned

An informal write-up of the whole experiment: what we set out to test, what held
up, what didn't, and what I think it means. The hard numbers live in
[`limits.md`](limits.md) and [`compaction.md`](compaction.md) — this page is the
reasoning around them.

Everything below is Claude Code v2.1.278, Opus 5 at low effort, Claude Pro, on a
Bun + TypeScript repo. One machine, one codebase. Treat it accordingly.

## The setup

Strip Claude Code down to a single shell tool, a 36-token system prompt, and a
capped context window. Then ask the obvious question: does it still work, and
what does it actually buy you?

The honest answer turned out to be three different numbers, and conflating them
is how people end up disappointed.

## Number one: 20x, and it's the least interesting

A session with one tool starts at 895 prompt tokens. Stock starts at 17,625.

That's a real 20x, and it's almost entirely **tool schemas**. The system prompt
is 36 tokens — a rounding error. If you're hand-tuning your CLAUDE.md to save
context, you're optimizing the wrong thing by two orders of magnitude.

But this is fixed overhead. It's the ceiling on what cutting tools can save you,
not the saving itself.

## Number two: ~2x on real work, and that's the number to quote

We ran two real tasks against a live repo, three times each, twelve runs total.
`inspect` came out 1.80x cheaper, `trace` 2.08x.

The gap collapses from 20x to 2x for a boring reason: both sessions end up
reading the same files, and file contents cost the same under every preset. You
cut the overhead. You don't cut the work.

I want to be blunt about this because it's the number people will check first.
If you publish 20x, the first person who runs the benchmark gets 2x and
(correctly) calls it out. 2x on real work is a genuinely good result. It doesn't
need inflating.

**Quality held.** All six `trace` runs under both presets landed on the same
line of the same file and described the same failure modes. The single most
complete answer came from the cut preset.

## The thing I expected to lose, and didn't

`trace` is a code-search task: find where config is loaded, quote the line,
explain the failure modes. Native Glob + Grep + Read should beat a bare shell at
this. That was the whole reason the task existed — to find where cutting hurts.

The cut session used **fewer** turns. 4.33 against 5.33.

In hindsight it's obvious. One `rg` with a decent pattern is one round trip. In
our runs the stock agent tended to reach for several native calls — Glob, then
Grep, then Read — where one composed shell command would have done, and each of
those round trips drags its result into context. That's what the stock agent did
on these two tasks, not a law about the native tools. A shell isn't a degraded
version of them for search; it's a composable one. `rg -n 'loadConfig' src | head -20` has no
native equivalent that costs one call.

I'd now say the "you lose search quality" intuition is backwards for anyone
comfortable in a shell. What you actually lose is skills, subagents and web
search — real losses, just not the ones people predict.

## Number three: the one that changed my mind

Here's where I was wrong in a way that mattered.

My assumption — written into the README at one point — was that the advantage
**shrinks** on a long session. Overhead is paid once, work accumulates, so the
ratio should decay toward 1. Reasonable. Wrong.

We ran both presets past their context window with a 100k cap until they
compacted repeatedly. The number that matters is the **floor**: what the prompt
costs on the first turn *after* a compaction.

```
sh:       13,440 → 21,532 → 8,416           floor ~14k
default:  35,628 → 32,190 → 37,476 → 38,082 → 36,363   floor ~36k
```

The floor is the session's fixed cost — system prompt plus tool schemas —
**rebuilt from scratch after every compaction**. It isn't paid once. It's rent.

With a 100k window and a ~35k trigger reserve, that leaves roughly 51k of
working room for the cut session and 27k for stock. Same window. Nearly double
the usable space, and it comes back every cycle for the rest of the session.

So the correct mental model is the opposite of mine: **the longer the session,
the more cutting tools is worth.** Startup overhead is the advertisement;
compaction floor is the product.

You can watch it happen. Tool calls per cycle went 12 → 12 → 15 → 20 for the cut
session and 14 → 13 → 11 → 9 → 9 → 6 for stock. Less room per cycle, less work
per cycle. (Coarse proxy — one `sh` call isn't one `Bash` call — but the
directions are opposite and that's hard to explain away.)

## Two hypotheses that died

Worth recording, because both were plausible and both were wrong.

**"Compaction accumulates sediment."** Summarizing a summary of a summary should
get dirtier each round, so the floor should ratchet upward. It doesn't. Both
presets oscillate around a level set by the preset with no trend. The `sh`
summaries actually *shrank* across the run (5,666 → 4,992 → 4,659). The floor is
a property of your configuration, not of how long you've been going.

**"Compaction resets your toolset."** This one felt very plausible — compaction
rewrites the conversation, so maybe it re-initializes the session. It doesn't.
Three compactions deep, the cut session was still running exclusively on its one
MCP tool, zero stock tools, ever. Confirmed again in a separate 692-call session.

What *does* restore the full toolset is resuming without the flags: `claude
--continue`, `claude --resume <id>`, `claude attach <id>`. Tools are set by the
command line at launch and live nowhere else. If you've ever felt your cut
session "go back to normal", that's almost certainly what happened — and it's
the same root cause as why an alias can't do this job at all.

## The undocumented bit

Auto-compaction does not trigger at a percentage of your window. It triggers at
**window minus roughly 35,000 tokens**, flat:

| window | fires at | reserve |
|---:|---|---:|
| 200,000 | 162k–167k | ~33k–38k |
| 100,000 | 60k–67k | ~33k–40k |

Which explains, neatly, why `--autocompact` refuses values under 100k: at a 50k
window the trigger would land near 15k — below where a stock session lands after
compacting — and you'd compact in an infinite loop.

This also means your effective working window is always `window − 35k − floor`.
For stock at 100k that's 27k. People set a 100k cap thinking they've bought
100k. They've bought a quarter of it.

## The trap

One finding runs backwards from everything else here: **do not disable tool
search.**

```
default (tool search on)       17,026 / 18,586
ENABLE_TOOL_SEARCH=false       36,345 / 39,403
```

Claude Code ships tool *names* in the prompt and loads full schemas on demand.
Turning that off doubles your context. Some proxy configs set it by default —
for third-party models that handle deferred schemas badly — and if you copied an
alias from one of those, you've been paying double. Check your alias before you
optimize anything else.

## What we can't say

Stated plainly, because the temptation to round up is real:

- **The long-session test is one run per preset**, both stopped by hand (3
  compactions for `sh`, 5 for stock). The floor gap is far larger than the ~9%
  run-to-run variance we measured elsewhere, but there's no variance estimate
  for it specifically.
- **The third `sh` compaction happened after a `--resume`**, so the lowest floor
  we recorded (8,416) may be an artifact of the process restarting. It's the
  weakest number in the set.
- **The two long runs used slightly different prompts.** The cut arm carried an
  extra "don't ask clarifying questions" instruction, added after a first attempt
  stopped to ask one. It changes what the model did, not what the floor costs.
- **We measured cost and context, not correctness, on the long runs.** Nobody
  graded the audit those sessions produced.
- One version, one repo, one model, one machine.

## Where I'd dig next

1. **Window sizing.** Smaller window = more compaction cycles, but each one
   summarizes less history. There's probably an optimum and we have no idea
   where it is. This is the highest-value open question.
2. **Fresh session vs compaction.** Compaction bills for the history it
   summarizes. At some point starting clean with a short hand-written brief must
   beat compacting — where?
3. **Tool output size.** `MAX_MCP_OUTPUT_TOKENS` exists in the binary. Session
   overhead is paid once per cycle; a single `cat` of a large file is paid
   forever. This may matter more than preset choice on real work.
4. **What cutting actually costs.** We found where it doesn't hurt. We never
   built a task wide enough to need subagents, which is the most likely place it
   does.

## The one-line version

Cutting tools isn't about a cheaper startup. It's about how much of your context
window you still own after the session has been running for an hour.

---

Reproduce any of it: [`bench/run.sh`](../bench/run.sh) for the short tasks,
[`bench/longrun.sh`](../bench/longrun.sh) for compaction behaviour. If you run it
on your own repo, the numbers are worth more than ours — see the contributing
note in [`limits.md`](limits.md).
