#!/usr/bin/env bash
# archive.sh — Build a Release .xcarchive and export a TestFlight-ready .ipa.
#
# Usage:
#   ./scripts/archive.sh
#
# Prerequisites:
#   1. Paid Apple Developer Program account enrolled at developer.apple.com
#   2. App created in App Store Connect with bundle ID com.glycotrack.app
#   3. GlycoTrack/Config/GlycoTrack.local.xcconfig contains:
#        DEVELOPMENT_TEAM = <your 10-char team ID>
#        CLAUDE_API_KEY   = sk-ant-...
#
# Output:
#   build/GlycoTrack.xcarchive   — Xcode archive (symbols, dSYMs)
#   build/GlycoTrack.ipa         — ready to upload via Xcode Organizer or Transporter

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

SCHEME="GlycoTrack"
CONFIG="Release"
ARCHIVE_PATH="build/GlycoTrack.xcarchive"
EXPORT_PATH="build"
EXPORT_OPTIONS_PLIST="build/ExportOptions.plist"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
step() { printf "\n\033[1;34m▶ %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m✓ %s\033[0m\n" "$*"; }
err()  { printf "\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

# ── Validate prerequisites ────────────────────────────────────────────────────
step "Checking prerequisites"

LOCAL_XCCONFIG="GlycoTrack/Config/GlycoTrack.local.xcconfig"
if [[ ! -f "$LOCAL_XCCONFIG" ]]; then
  err "$LOCAL_XCCONFIG not found. Create it with DEVELOPMENT_TEAM and CLAUDE_API_KEY."
fi

TEAM_ID=$(grep -E "^DEVELOPMENT_TEAM\s*=" "$LOCAL_XCCONFIG" | sed 's/.*=\s*//' | tr -d '[:space:]' || true)
if [[ -z "$TEAM_ID" ]]; then
  err "DEVELOPMENT_TEAM not set in $LOCAL_XCCONFIG. Add: DEVELOPMENT_TEAM = <your 10-char team ID>"
fi

ok "Team ID: $TEAM_ID"

mkdir -p build

# ── Inject build info ─────────────────────────────────────────────────────────
step "Injecting build info"
./scripts/inject_build_info.sh
ok "Build info injected"

# ── Regenerate Xcode project ──────────────────────────────────────────────────
step "Regenerating Xcode project"
xcodegen generate
ok "Project regenerated"

# ── Archive ───────────────────────────────────────────────────────────────────
step "Archiving $SCHEME ($CONFIG)"
set +e
ARCHIVE_LOG=$(mktemp)
xcodebuild archive \
  -project GlycoTrack.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  2>&1 | tee "$ARCHIVE_LOG" \
  | { xcbeautify 2>/dev/null || grep -E "(error:|BUILD (SUCCEEDED|FAILED)|ARCHIVE (SUCCEEDED|FAILED))" || true; }
set -e

if grep -qE "ARCHIVE SUCCEEDED|BUILD SUCCEEDED" "$ARCHIVE_LOG"; then
  ok "Archive succeeded → $ARCHIVE_PATH"
else
  echo ""
  echo "── Archive errors ────────────────────────────────"
  grep "error:" "$ARCHIVE_LOG" | head -20
  rm -f "$ARCHIVE_LOG"
  err "Archive failed. See above for errors."
fi
rm -f "$ARCHIVE_LOG"

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  err "Archive not found at $ARCHIVE_PATH"
fi

# ── Write ExportOptions.plist ─────────────────────────────────────────────────
step "Writing ExportOptions.plist"
cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
PLIST
ok "ExportOptions.plist written"

# ── Export .ipa ───────────────────────────────────────────────────────────────
step "Exporting .ipa"
set +e
EXPORT_LOG=$(mktemp)
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  2>&1 | tee "$EXPORT_LOG" \
  | { xcbeautify 2>/dev/null || grep -E "(error:|EXPORT (SUCCEEDED|FAILED))" || true; }
set -e

if grep -q "EXPORT SUCCEEDED" "$EXPORT_LOG"; then
  ok "Export succeeded → $EXPORT_PATH/GlycoTrack.ipa"
else
  echo ""
  echo "── Export errors ─────────────────────────────────"
  grep "error:" "$EXPORT_LOG" | head -20
  rm -f "$EXPORT_LOG"
  err "Export failed. See above for errors."
fi
rm -f "$EXPORT_LOG"
rm -f "$EXPORT_OPTIONS_PLIST"

IPA_PATH="$EXPORT_PATH/GlycoTrack.ipa"
if [[ ! -f "$IPA_PATH" ]]; then
  err ".ipa not found at $IPA_PATH after export."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
bold "Done. TestFlight build ready."
echo ""
echo "  Archive: $ARCHIVE_PATH"
echo "  IPA:     $IPA_PATH"
echo ""
echo "Next: upload to TestFlight via one of:"
echo "  • Xcode → Window → Organizer → select archive → Distribute App"
echo "  • xcrun altool --upload-app -f $IPA_PATH -t ios --apiKey <key> --apiIssuer <issuer>"
echo ""
echo "After uploading, go to App Store Connect → TestFlight → add tester emails."
echo "Remember to bump CFBundleVersion in GlycoTrack/Info.plist before the next upload."
