#!/usr/bin/env bash
# Pre-tool-use hook: block `gh pr create` if PLAN.md is unmodified on the branch.
#
# Claude Code passes the tool input as JSON on stdin.
# We only act when the Bash command contains "gh pr create".

input=$(cat)
command=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('command',''))" 2>/dev/null)

# Only intercept gh pr create calls
if ! echo "$command" | grep -q "gh pr create"; then
  exit 0
fi

# Find the repo root (works from worktrees too)
repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$repo_root" ]; then
  exit 0
fi

# Determine the merge base with origin/develop
merge_base=$(git merge-base HEAD origin/develop 2>/dev/null)
if [ -z "$merge_base" ]; then
  exit 0
fi

# Check whether PLAN.md has been touched since branching off develop
if git diff --quiet "$merge_base" HEAD -- PLAN.md 2>/dev/null; then
  echo "ERROR: PLAN.md has not been updated on this branch." >&2
  echo "Update PLAN.md (post-MVP iterations table, DB counts, known limitations)" >&2
  echo "then re-run gh pr create." >&2
  exit 1
fi

exit 0
