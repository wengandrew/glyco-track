#!/usr/bin/env bash
# PostToolUse/Edit: remind to update CLAUDE.md when architecture-level files are changed.
input=$(cat)
file=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

arch_files=(
  "GlycoTrackManagedObjectModel.swift"
  "FoodMatcher.swift"
  "FoodLogProcessor.swift"
)

for f in "${arch_files[@]}"; do
  if [[ "$file" == *$f ]]; then
    echo "REMINDER: $f is an architecture-level file — check whether CLAUDE.md's architecture section needs updating before opening a PR." >&2
    break
  fi
done
