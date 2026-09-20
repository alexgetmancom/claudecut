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

# Auto-compact window. Smaller window = earlier compaction = predictable spend.
CLAUDECUT_AUTOCOMPACT="${CLAUDECUT_AUTOCOMPACT:-200000}"

# Effort level, when the model exposes one: low, medium, high, xhigh, max.
CLAUDECUT_EFFORT="${CLAUDECUT_EFFORT:-low}"

# The one-tool MCP server.
CLAUDECUT_MCP_CONFIG="${CLAUDECUT_MCP_CONFIG:-$CLAUDECUT_ROOT/mini-sh/mcp.json}"

claudecut_presets() {
  printf '%s\n' sh sh-read read-edit restricted default
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
