#!/usr/bin/env bash
# Turn a bench run's rows.jsonl into a markdown table, averaged over repeats.
#
#   bench/summarize.sh bench/results/20260920-120000

set -euo pipefail
dir="${1:?usage: summarize.sh <results-dir>}"
rows="$dir/rows.jsonl"
[ -f "$rows" ] || { echo "summarize: no rows.jsonl in $dir" >&2; exit 2; }

# "prompt" is everything sent up front: fresh cache writes plus cache reads.
# It is the closest headless proxy for what /context shows in a live session.
echo "| task | preset | runs | ok | cost USD | turns | wall s | prompt | out |"
echo "|---|---|---:|---:|---:|---:|---:|---:|---:|"

jq -s -r '
  def avg(f): (map(f // 0) | add) / length;
  def r2(x): (x * 100 | round) / 100;
  def r4(x): (x * 10000 | round) / 10000;
  group_by([.task, .preset])
  | sort_by(.[0].task, .[0].preset)
  | .[]
  | "| \(.[0].task) | \(.[0].preset) | \(length) | \(map(select(.ok)) | length) " +
    "| \(r4(avg(.cost_usd))) | \(r2(avg(.turns))) | \(r2(avg(.wall_s))) " +
    "| \(avg(.input + .cache_write + .cache_read) | round) | \(avg(.output) | round) |"
' "$rows"
