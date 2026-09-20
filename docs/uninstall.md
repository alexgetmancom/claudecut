# Uninstall

claudecut installs nothing into Claude Code. It writes no settings, patches no
binary, and touches no file under `~/.claude`. Removing it is removing a
directory and a line from your shell profile.

```bash
# 1. drop the PATH entry (or the alias/function, if you added one)
$EDITOR ~/.zshrc          # delete the claudecut line

# 2. remove the checkout
rm -rf ~/projects/claudecut

# 3. remove optional config, if you created one
rm -rf ~/.config/claudecut
```

That is all of it. `claude` behaves exactly as it did before, because it was
never modified.

## What to check afterwards

```bash
command -v claudecut     # nothing
command -v claude        # your normal install
claude --version         # unchanged
```

## If you also changed settings

The two settings mentioned in [findings §9](findings.md#9-cheap-things-that-are-not-tools)
are yours, not claudecut's, and survive uninstall. Remove them by hand if you no
longer want them:

- `"autoCompactWindow"` in `~/.claude/settings.json`
- `"modelSettings"` in `~/.claude/settings.json`

## Benchmark leftovers

`bench/results/` is gitignored and lives inside the checkout, so step 2 takes it
with everything else. Nothing is written outside the repo.
