#!/usr/bin/env bash
# Long-session test: run one context-growing task per preset until the session
# has compacted several times, then read the compaction behaviour back out of
# the session transcript.
#
# Unlike run.sh, which measures single-shot overhead, this measures what
# happens to a session that outlives its own context window.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/presets.sh"

PRESETS="sh,default"
TASK="audit"
WINDOW=100000
WORKDIR="$PWD"
OUTDIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --presets) PRESETS="$2"; shift 2 ;;
    --task)    TASK="$2"; shift 2 ;;
    --window)  WINDOW="$2"; shift 2 ;;
    --dir)     WORKDIR="$2"; shift 2 ;;
    --out)     OUTDIR="$2"; shift 2 ;;
    *) printf 'longrun: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "longrun: jq is required" >&2; exit 1; }

stamp="$(date +%Y%m%d-%H%M%S)"
[ -n "$OUTDIR" ] || OUTDIR="$ROOT/bench/results/long-$stamp"
mkdir -p "$OUTDIR"

prompt="$(cat "$ROOT/bench/tasks/$TASK.md")"

echo "longrun: $stamp"
echo "longrun: workdir $WORKDIR"
echo "longrun: task    $TASK"
echo "longrun: window  $WINDOW"
echo "longrun: presets $PRESETS"
echo

# Transcripts live under a directory named after the working directory, with
# every non-alphanumeric character replaced by a dash.
slug="$(printf '%s' "$WORKDIR" | sed 's/[^a-zA-Z0-9]/-/g')"
projdir="$HOME/.claude/projects/$slug"

IFS=, read -r -a preset_list <<< "$PRESETS"

for preset in "${preset_list[@]}"; do
  flags=()
  while IFS= read -r line; do
    [ -n "$line" ] && flags+=("$line")
  done < <(CLAUDECUT_AUTOCOMPACT="$WINDOW" claudecut_preset_flags "$preset")

  # The default preset carries no preset flags, so set the window explicitly.
  case "$preset" in
    default) flags=(--autocompact "$WINDOW") ;;
  esac

  # Both arms get the same model, effort and settings sources. Without this the
  # stock arm would inherit whatever the runner's own settings files say.
  while IFS= read -r flag; do
    flags+=("$flag")
  done < <(claudecut_bench_pin)

  echo "longrun: starting $preset ..."
  start=$(date +%s)
  ( cd "$WORKDIR" && env -u ANTHROPIC_API_KEY claude \
      --output-format json \
      ${flags[@]+"${flags[@]}"} \
      -p "$prompt" ) > "$OUTDIR/$preset.json" 2> "$OUTDIR/$preset.err" || true
  end=$(date +%s)

  if ! jq -e . "$OUTDIR/$preset.json" >/dev/null 2>&1; then
    echo "longrun: $preset produced no valid JSON, see $preset.err"
    continue
  fi

  jq -r '.result // ""' "$OUTDIR/$preset.json" > "$OUTDIR/$preset.answer.txt"
  sid="$(jq -r '.session_id // ""' "$OUTDIR/$preset.json")"
  cost="$(jq -r '.total_cost_usd // 0' "$OUTDIR/$preset.json")"
  turns="$(jq -r '.num_turns // 0' "$OUTDIR/$preset.json")"

  printf 'longrun: %s done  %s USD  %s turns  %ss  session %s\n' \
    "$preset" "$cost" "$turns" "$((end - start))" "$sid"

  if [ -n "$sid" ] && [ -f "$projdir/$sid.jsonl" ]; then
    cp "$projdir/$sid.jsonl" "$OUTDIR/$preset.transcript.jsonl"
  else
    echo "longrun: transcript not found for $preset ($projdir/$sid.jsonl)"
  fi
  echo
done

node "$ROOT/bench/compaction.mjs" "$OUTDIR" | tee "$OUTDIR/summary.md"
echo
echo "longrun: raw results in $OUTDIR"
