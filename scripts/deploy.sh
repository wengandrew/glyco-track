#!/usr/bin/env bash
# deploy.sh — Build GlycoTrack and push it to a connected iPhone, no Xcode UI needed.
#
# Usage:
#   ./scripts/deploy.sh                   # auto-detect first connected device
#   ./scripts/deploy.sh --device <UDID>   # target a specific device
#   ./scripts/deploy.sh --no-launch       # install but don't relaunch the app
#   ./scripts/deploy.sh --clean           # xcodebuild clean before building
#   ./scripts/deploy.sh --no-regen        # skip xcodegen (faster, if no files changed)
#
# Requirements:
#   - Xcode 15+ (provides xcrun devicectl)
#   - Device trusted on this Mac (Settings > General > VPN & Device Management)
#   - GlycoTrack/Config/GlycoTrack.local.xcconfig with a valid DEVELOPMENT_TEAM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

SCHEME="GlycoTrack"
BUNDLE_ID="com.glycotrack.app"
CONFIG="Debug"
BUILD_DIR="$ROOT/build"
APP_PATH="$BUILD_DIR/Build/Products/$CONFIG-iphoneos/$SCHEME.app"

# xcodebuild uses the hardware UDID (00008110-...)
# devicectl uses the coredevice identifier UUID (92B8CB36-...)
# Both are auto-detected; pass --device to override with either value or a name.
DEVICE_ARG=""      # raw --device arg (name / hardware UDID / coredevice UUID)
DEVICE_HW_UDID=""  # for xcodebuild -destination id=
DEVICE_CD_ID=""    # for devicectl --device
DO_LAUNCH=true
DO_CLEAN=false
DO_REGEN=true

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)    DEVICE_ARG="$2"; shift 2 ;;
    --no-launch) DO_LAUNCH=false; shift ;;
    --clean)     DO_CLEAN=true; shift ;;
    --regen)     DO_REGEN=true; shift ;;
    --no-regen)  DO_REGEN=false; shift ;;
    -h|--help)
      grep '^#' "$0" | grep -v '!/usr/bin' | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
bold() { printf "\033[1m%s\033[0m\n" "$*"; }
step() { printf "\n\033[1;34m▶ %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m✓ %s\033[0m\n" "$*"; }
err()  { printf "\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

# ── Detect device ─────────────────────────────────────────────────────────────
step "Detecting device"
# devicectl appends a human-readable table after the JSON, so use a temp file.
_DEVCTL_JSON=$(mktemp)
xcrun devicectl list devices --json-output "$_DEVCTL_JSON" >/dev/null 2>&1 || true

IFS=$'\t' read -r DEVICE_NAME DEVICE_HW_UDID DEVICE_CD_ID < <(python3 - "$_DEVCTL_JSON" "${DEVICE_ARG:-}" <<'PYEOF'
import json, sys
path, want = sys.argv[1], sys.argv[2]
data = json.load(open(path))
devices = data.get('result', {}).get('devices', [])
connected = [d for d in devices if d.get('connectionProperties', {}).get('transportType') is not None]
if not connected:
    sys.exit(1)
# If caller specified a device, match by name, hardware UDID, or coredevice identifier.
if want:
    matches = [d for d in connected if
               want in (d['deviceProperties']['name'],
                        d['hardwareProperties']['udid'],
                        d.get('identifier',''))]
    if not matches:
        print(f"No connected device matching '{want}'", file=sys.stderr); sys.exit(1)
    d = matches[0]
else:
    d = connected[0]
print(d['deviceProperties']['name'] + '\t' +
      d['hardwareProperties']['udid'] + '\t' +
      d.get('identifier', d['hardwareProperties']['udid']))
PYEOF
) || err "No connected device found. Plug in your iPhone and trust this Mac, or pass --device <name|UDID>."

rm -f "$_DEVCTL_JSON"
ok "Target: $DEVICE_NAME  hw=$DEVICE_HW_UDID  cd=$DEVICE_CD_ID"

ok "Target: $DEVICE_NAME ($DEVICE_HW_UDID)"

# ── Inject build info (git branch/commit/timestamp) ───────────────────────────
step "Injecting build info"
./scripts/inject_build_info.sh
ok "Build info injected"

# ── Optionally regenerate project ─────────────────────────────────────────────
if $DO_REGEN; then
  step "Regenerating Xcode project"
  xcodegen generate
  ok "Project regenerated"
fi

# ── Optionally clean ──────────────────────────────────────────────────────────
if $DO_CLEAN; then
  step "Cleaning build folder"
  xcodebuild clean \
    -project GlycoTrack.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    | grep -E "^(Clean|BUILD)" || true
  ok "Clean done"
fi

# ── Build ─────────────────────────────────────────────────────────────────────
step "Building $SCHEME ($CONFIG) for device"
set +e
BUILD_LOG=$(mktemp)
# Use hardware UDID for xcodebuild destination.
xcodebuild \
  -project GlycoTrack.xcodeproj \
  -scheme "$SCHEME" \
  -destination "id=$DEVICE_HW_UDID" \
  -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_STYLE=Automatic \
  2>&1 | tee "$BUILD_LOG" \
  | { xcbeautify 2>/dev/null || grep -E "(error:|BUILD (SUCCEEDED|FAILED))" || true; }
set -e

if grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
  ok "Build succeeded"
else
  echo ""
  echo "── Build errors ──────────────────────────────────"
  grep "error:" "$BUILD_LOG" | head -20
  err "Build failed. See above for errors."
fi
rm -f "$BUILD_LOG"

if [[ ! -d "$APP_PATH" ]]; then
  err "App bundle not found at $APP_PATH"
fi

# ── Install ───────────────────────────────────────────────────────────────────
step "Installing on $DEVICE_NAME"
# Use coredevice identifier UUID for devicectl.
xcrun devicectl device install app \
  --device "$DEVICE_CD_ID" \
  "$APP_PATH" 2>&1 | grep -Ev "^$|^Preparing|^Copying" || true
ok "Installed $BUNDLE_ID"

# ── Launch ────────────────────────────────────────────────────────────────────
if $DO_LAUNCH; then
  step "Launching app"
  xcrun devicectl device process launch \
    --device "$DEVICE_CD_ID" \
    "$BUNDLE_ID" 2>&1 | grep -Ev "^$|^Launching" || true
  ok "Launched $BUNDLE_ID on $DEVICE_NAME"
fi

echo ""
bold "Done. GlycoTrack is live on $DEVICE_NAME."
