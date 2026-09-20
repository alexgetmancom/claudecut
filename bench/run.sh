#!/usr/bin/env bash
# claudecut bench — run one task under several presets and compare the cost.
#
#   bench/run.sh                                  every preset, every task
#   bench/run.sh --presets sh,default             pick presets
#   bench/run.sh --tasks hello                    pick tasks (bench/tasks/*.md)
#   bench/run.sh --repeat 3                       repeat each cell
#   bench/run.sh --dir ~/projects/some-repo       run against a real codebase
#
# Every run is a real `claude -p` call and spends real quota. Start with the
# `hello` task to see what a run costs before pointing this at anything larger.
#
# What it measures: wall time, turns, tokens in and out, cache reads, and the
# cost the CLI itself reports. What it does NOT measure: whether the answer was
# any good. Read bench/results/<stamp>/<task>.<preset>.<n>.txt and judge that
# yourself — that is the part no script can do for you.

set -euo pipefail

CLAUDECUT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export CLAUDECUT_ROOT
# shellcheck source=../lib/presets.sh
. "$CLAUDECUT_ROOT/lib/presets.sh"

presets=""
tasks=""
repeat=1
workdir="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --presets) presets="${2:?}"; shift 2 ;;
    --tasks)   tasks="${2:?}"; shift 2 ;;
    --repeat)  repeat="${2:?}"; shift 2 ;;
    --dir)     workdir="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "bench: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$presets" ] || presets="$(claudecut_presets | paste -sd, -)"
if [ -z "$tasks" ]; then
  tasks="$(find "$CLAUDECUT_ROOT/bench/tasks" -name '*.md' -exec basename {} .md \; | sort | paste -sd, -)"
fi

command -v jq >/dev/null || { echo "bench: jq is required" >&2; exit 127; }

stamp="$(date +%Y%m%d-%H%M%S)"
outdir="$CLAUDECUT_ROOT/bench/results/$stamp"
mkdir -p "$outdir"

claude_bin="${CLAUDECUT_CLAUDE_BIN:-$(command -v claude)}"
[ -n "$claude_bin" ] || { echo "bench: claude not found in PATH" >&2; exit 127; }

echo "bench: $stamp"
echo "bench: workdir  $workdir"
echo "bench: presets  $presets"
echo "bench: tasks    $tasks"
echo "bench: repeat   $repeat"
echo

IFS=',' read -r -a task_list <<< "$tasks"
IFS=',' read -r -a preset_list <<< "$presets"

for task in "${task_list[@]}"; do
  task_file="$CLAUDECUT_ROOT/bench/tasks/$task.md"
  [ -f "$task_file" ] || { echo "bench: no such task: $task" >&2; exit 2; }
  prompt="$(cat "$task_file")"

  for preset in "${preset_list[@]}"; do
    # No mapfile: macOS still ships bash 3.2.
    flags=()
    while IFS= read -r flag; do
      [ -n "$flag" ] && flags+=("$flag")
    done < <(claudecut_preset_flags "$preset")
    # Pin model, effort and settings sources for every arm, including the
    # "default" one, so the comparison does not depend on the runner's config.
    while IFS= read -r flag; do
      flags+=("$flag")
    done < <(claudecut_bench_pin)

    for n in $(seq 1 "$repeat"); do
      label="$task.$preset.$n"
      printf 'bench: %-34s ' "$label"

      start=$(date +%s)
      set +e
      ( cd "$workdir" && "$claude_bin" ${flags[@]+"${flags[@]}"} \
          --output-format json -p "$prompt" ) > "$outdir/$label.json" 2> "$outdir/$label.err"
      status=$?
      set -e
      end=$(date +%s)

      if [ $status -ne 0 ] || ! jq -e . "$outdir/$label.json" >/dev/null 2>&1; then
        echo "FAILED (exit $status, see $label.err)"
        jq -n --arg task "$task" --arg preset "$preset" --argjson n "$n" \
              --argjson wall "$((end - start))" \
          '{task:$task,preset:$preset,run:$n,ok:false,wall_s:$wall}' \
          >> "$outdir/rows.jsonl"
        continue
      fi

      # Keep the answer next to the numbers, so quality can be judged by hand.
      jq -r '.result // ""' "$outdir/$label.json" > "$outdir/$label.txt"

      jq --arg task "$task" --arg preset "$preset" --argjson n "$n" \
         --argjson wall "$((end - start))" \
        '{task:$task, preset:$preset, run:$n, ok:(.is_error|not),
          wall_s:$wall, duration_ms:.duration_ms, turns:.num_turns,
          cost_usd:.total_cost_usd,
          input:.usage.input_tokens, output:.usage.output_tokens,
          cache_read:.usage.cache_read_input_tokens,
          cache_write:.usage.cache_creation_input_tokens}' \
        "$outdir/$label.json" >> "$outdir/rows.jsonl"

      jq -r '"\(.total_cost_usd | . * 10000 | round / 10000) USD  \(.num_turns) turns  \(.duration_ms)ms"' \
        "$outdir/$label.json"
    done
  done
done

echo
"$CLAUDECUT_ROOT/bench/summarize.sh" "$outdir" | tee "$outdir/summary.md"
echo
echo "bench: raw results in $outdir"
