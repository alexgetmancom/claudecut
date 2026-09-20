#!/usr/bin/env bash
# Poll the live session transcript and stop the run after N new compactions.
# Auto-detects the transcript so a forked/renamed session id is not a problem.
PROJ="$1"; LIMIT="${2:-1}"; PAT="${3:-autocompact 100000}"
while :; do
  F=$(ls -t "$PROJ"/*.jsonl 2>/dev/null | head -1)
  if [ -n "$F" ]; then
    n=$(grep -c 'isCompactSummary":true' "$F" 2>/dev/null)
    [ -z "$n" ] && n=0
    printf '%s %s lines=%s compactions=%s\n' \
      "$(date +%H:%M:%S)" "$(basename "$F")" "$(wc -l < "$F" | tr -d ' ')" "$n"
    if [ "$n" -ge "$LIMIT" ]; then
      echo "reached $LIMIT compaction(s), stopping run"
      pkill -f "$PAT"
      break
    fi
  else
    echo "$(date +%H:%M:%S) no transcript yet"
  fi
  pgrep -f "$PAT" >/dev/null || { echo "$(date +%H:%M:%S) run ended on its own"; break; }
  sleep 300
done
