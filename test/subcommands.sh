#!/usr/bin/env bash
# The subcommand list in bin/claudecut is hardcoded, because there is no way to
# ask the CLI at launch without paying for a `--help` run on every invocation.
# That means it can silently fall behind a Claude Code release: a new subcommand
# would be treated as a prompt and launched with session flags attached.
#
# This compares the hardcoded list against the live `claude --help` output.
# Extras are fine — a name we pass through that does not exist yet costs
# nothing. Anything missing is the real failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v claude >/dev/null || { echo "test: claude not on PATH" >&2; exit 1; }

# The case label spans several lines with backslash continuations.
ours="$(sed -n '/^    agents|/,/subcommand=1/p' "$ROOT/bin/claudecut" \
  | tr -d ' \\\n' | sed 's/)subcommand=1;;//' | tr '|' '\n' | sort -u)"

live="$(claude --help 2>&1 \
  | sed -n '/^Commands:/,$p' \
  | sed -n 's/^  \([a-z][a-z0-9-]*\).*/\1/p' | sort -u)"

missing="$(comm -13 <(printf '%s\n' "$ours") <(printf '%s\n' "$live"))"
extra="$(comm -23 <(printf '%s\n' "$ours") <(printf '%s\n' "$live"))"

# Some subcommands are real but hidden from --help, so an "extra" is not
# automatically dead weight: it may be one of those. `self-hosted-runner` is
# the known case in 2.1.278.
[ -n "$extra" ] && printf 'test: extras, hidden or gone: %s\n' "$(echo $extra)"

if [ -n "$missing" ]; then
  printf 'test: FAIL — subcommands this CLI has that claudecut would treat as a prompt:\n'
  printf '  %s\n' $missing
  printf 'Add them to the case block in bin/claudecut.\n'
  exit 1
fi

printf 'test: ok — every subcommand of %s is passed through\n' "$(claude --version)"
