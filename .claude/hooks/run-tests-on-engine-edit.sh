#!/usr/bin/env bash
# PostToolUse/Edit: run swift test after edits to engine or matching files.
input=$(cat)
file=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

engine_patterns=(
  "Sources/GIEngineCore"
  "Sources/CLEngineCore"
  "Sources/TranscriptParserCore"
  "GlycoTrack/Modules/Matching"
)

for pattern in "${engine_patterns[@]}"; do
  if [[ "$file" == *$pattern* ]]; then
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$repo_root" ]; then
      echo "Running swift test after edit to $(basename "$file")…" >&2
      cd "$repo_root" && swift test 2>&1 | tail -30
    fi
    break
  fi
done
