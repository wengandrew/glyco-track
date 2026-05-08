#!/usr/bin/env bash
# PostToolUse/Write: regenerate BuildInfo.generated.swift after any Swift file write.
input=$(cat)
file=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

if [[ "$file" == *GlycoTrack/*.swift ]]; then
  repo_root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$repo_root" ] && bash "$repo_root/scripts/inject_build_info.sh"
fi
