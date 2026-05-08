#!/usr/bin/env bash
# PreToolUse/Edit: warn when one engine copy is being edited but the other hasn't been touched yet.
input=$(cat)
file=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$repo_root" ] && exit 0

changed=$(git -C "$repo_root" diff --name-only HEAD 2>/dev/null)

spm_gi_changed=$(echo "$changed" | grep -c "Sources/GIEngineCore")
ios_gi_changed=$(echo "$changed" | grep -c "GlycoTrack/Modules/GIEngine")
spm_cl_changed=$(echo "$changed" | grep -c "Sources/CLEngineCore")
ios_cl_changed=$(echo "$changed" | grep -c "GlycoTrack/Modules/CLEngine")

warn() { echo "WARNING: $1" >&2; }

if [[ "$file" == *Sources/GIEngineCore* ]] && [[ $spm_gi_changed -gt 0 && $ios_gi_changed -eq 0 ]]; then
  warn "GIEngineCore (SPM) has edits but GlycoTrack/Modules/GIEngine/GIEngine.swift (iOS mirror) hasn't been updated yet."
fi
if [[ "$file" == *GlycoTrack/Modules/GIEngine* ]] && [[ $ios_gi_changed -gt 0 && $spm_gi_changed -eq 0 ]]; then
  warn "GIEngine iOS mirror has edits but Sources/GIEngineCore (SPM copy) hasn't been updated yet."
fi
if [[ "$file" == *Sources/CLEngineCore* ]] && [[ $spm_cl_changed -gt 0 && $ios_cl_changed -eq 0 ]]; then
  warn "CLEngineCore (SPM) has edits but GlycoTrack/Modules/CLEngine/CLEngine.swift (iOS mirror) hasn't been updated yet."
fi
if [[ "$file" == *GlycoTrack/Modules/CLEngine* ]] && [[ $ios_cl_changed -gt 0 && $spm_cl_changed -eq 0 ]]; then
  warn "CLEngine iOS mirror has edits but Sources/CLEngineCore (SPM copy) hasn't been updated yet."
fi

exit 0
