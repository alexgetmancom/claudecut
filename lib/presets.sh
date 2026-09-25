# claudecut presets — sourced by bin/claudecut and bench/run.sh.
#
# A preset is a set of flags handed to the Claude Code CLI at launch.
# Nothing here is patched or wrapped: these are documented CLI flags.
#
# claudecut_preset_flags <name>   prints the flags, one per line.
# claudecut_presets               prints every preset name.

CLAUDECUT_ROOT="${CLAUDECUT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"

# The whole system prompt. Replaces Claude Code's default one.
CLAUDECUT_SYSTEM_PROMPT="${CLAUDECUT_SYSTEM_PROMPT:-Coding agent in a git repo. Be concise. Never run destructive git or rm without asking.}"

# Auto-compact window. Smaller window = earlier compaction = predictable spend,
# larger = fewer compactions and less re-reading after each one. 300k is the
# default because on a long session the compactions themselves are the expensive
# part; drop it if you would rather cap what a single turn can cost.
#
# A value in `autoCompactWindow` in ~/.claude/settings.json wins over the
# --autocompact flag passed here, so set it in one place or the other.
CLAUDECUT_AUTOCOMPACT="${CLAUDECUT_AUTOCOMPACT:-300000}"

# Effort level, when the model exposes one: low, medium, high, xhigh, max.
CLAUDECUT_EFFORT="${CLAUDECUT_EFFORT:-low}"

# The one-tool MCP server.
CLAUDECUT_MCP_CONFIG="${CLAUDECUT_MCP_CONFIG:-$CLAUDECUT_ROOT/mini-sh/mcp.json}"

# --- Benchmark-only knobs -----------------------------------------------------
#
# The launcher never uses these. They exist because a benchmark has to compare
# like with like: without them the cut presets would run at CLAUDECUT_EFFORT
# while the "default" arm silently picked up whatever model and effort level
# your own settings files happen to set. Both arms get these, appended last so
# they win over anything a preset set earlier.
CLAUDECUT_BENCH_MODEL="${CLAUDECUT_BENCH_MODEL:-claude-opus-5}"
CLAUDECUT_BENCH_EFFORT="${CLAUDECUT_BENCH_EFFORT:-low}"

# Settings sources the benchmark is allowed to read. Empty means "none", so a
# stray autoCompactWindow or modelSettings in your own config cannot skew a run.
CLAUDECUT_BENCH_SETTING_SOURCES="${CLAUDECUT_BENCH_SETTING_SOURCES-}"

claudecut_bench_pin() {
  [ -n "$CLAUDECUT_BENCH_MODEL" ]  && printf '%s\n' --model  "$CLAUDECUT_BENCH_MODEL"
  [ -n "$CLAUDECUT_BENCH_EFFORT" ] && printf '%s\n' --effort "$CLAUDECUT_BENCH_EFFORT"
  printf '%s\n' --setting-sources "$CLAUDECUT_BENCH_SETTING_SOURCES"
  return 0
}

claudecut_presets() {
  printf '%s\n' sh bash sh-read read-edit restricted default
}

claudecut_preset_flags() {
  local preset="$1"

  # Shared by every cut preset. "default" opts out below.
  local -a common=(
    --system-prompt "$CLAUDECUT_SYSTEM_PROMPT"
    --autocompact "$CLAUDECUT_AUTOCOMPACT"
    --strict-mcp-config
    --mcp-config "$CLAUDECUT_MCP_CONFIG"
  )
  [ -n "$CLAUDECUT_EFFORT" ] && common+=(--effort "$CLAUDECUT_EFFORT")

  case "$preset" in
    # One tool total: the shell. Read, inspect and write all happen through it.
    sh)         printf '%s\n' "${common[@]}" --tools= ;;

    # The native Bash tool instead of the MCP shell: no MCP server to launch,
    # but Claude Code's own Bash schema in place of mini-sh's three lines.
    bash)       printf '%s\n' --system-prompt "$CLAUDECUT_SYSTEM_PROMPT" \
                  --autocompact "$CLAUDECUT_AUTOCOMPACT" --strict-mcp-config \
                  ${CLAUDECUT_EFFORT:+--effort} ${CLAUDECUT_EFFORT:+"$CLAUDECUT_EFFORT"} \
                  --tools=Bash ;;

    # Shell plus the native reader, for cheaper file reads with line numbers.
    sh-read)    printf '%s\n' "${common[@]}" --tools=Read ;;

    # Native file tools alongside the shell. Closest to normal editing.
    read-edit)  printf '%s\n' "${common[@]}" --tools=Read,Edit,Write ;;

    # Every built-in tool EXCEPT the ones that execute commands or code.
    # --restricted is a stock CLI flag; the shell tool still comes from MCP.
    restricted) printf '%s\n' "${common[@]}" --restricted ;;

    # Stock Claude Code. The baseline you are measuring against.
    default)    : ;;

    *) printf 'claudecut: unknown preset: %s\n' "$preset" >&2; return 1 ;;
  esac
}
