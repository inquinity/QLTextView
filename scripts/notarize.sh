#!/usr/bin/env bash
#
# notarize.sh — submit a signed QLTextView.app to Apple's notary service,
# wait for the result, and staple the ticket so the app verifies offline.
#
# Prereqs:
#   1. App must already be signed with Developer ID + hardened runtime
#      + secure timestamp. Run scripts/sign.sh first.
#   2. notarytool credentials stored under a keychain profile (one-time).
#      Create the profile by running:
#
#        xcrun notarytool store-credentials "QLTextView-Notary" \
#          --apple-id robert@altmansoftwaredesign.com \
#          --team-id  45GJWJVQN2 \
#          --password 'xxxx-xxxx-xxxx-xxxx'   # an app-specific password
#                                              # from appleid.apple.com → Sign-In and Security
#
# Usage:
#   scripts/notarize.sh                        # notarizes build/Release/QLTextView.app
#   scripts/notarize.sh path/to/Some.app
#   NOTARY_PROFILE=my-other-profile scripts/notarize.sh
#
set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "$SCRIPT_DIR/.." && pwd )"

APP="${1:-$REPO_ROOT/build/Release/QLTextView.app}"
PROFILE="${NOTARY_PROFILE:-QLTextView-Notary}"

# --- sanity checks -----------------------------------------------------------
if [[ ! -d "$APP" ]]; then
  echo "error: app bundle not found: $APP" >&2
  exit 1
fi

# Confirm the app is real-signed (not ad-hoc) and has a secure timestamp,
# because notarization will reject anything missing either.
SIG_INFO="$(codesign -dvv "$APP" 2>&1 || true)"
if grep -q 'Signature=adhoc' <<<"$SIG_INFO"; then
  echo "error: $APP is ad-hoc signed. Run scripts/sign.sh first." >&2
  exit 1
fi
if ! grep -q 'Timestamp=' <<<"$SIG_INFO"; then
  echo "error: $APP has no secure timestamp. Re-sign with TIMESTAMP=yes." >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "error: notarytool keychain profile '$PROFILE' not found or invalid." >&2
  echo "See the header of this script for how to create it." >&2
  exit 1
fi

# --- package -----------------------------------------------------------------
# notarytool wants a .zip / .pkg / .dmg, not a bare .app.
# `ditto` preserves bundle metadata correctly (vs. /usr/bin/zip).
ZIP="$(dirname "$APP")/$(basename "$APP" .app)-notarize.zip"
rm -f "$ZIP"
echo "==> Packaging for upload"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "    $ZIP ($(du -h "$ZIP" | cut -f1))"

# --- submit + wait -----------------------------------------------------------
echo "==> Submitting to Apple notary service (this can take 1–10 min)"
SUBMIT_OUT="$(xcrun notarytool submit "$ZIP" \
  --keychain-profile "$PROFILE" \
  --wait \
  --output-format json)"
echo "$SUBMIT_OUT"

STATUS="$(printf '%s' "$SUBMIT_OUT" | /usr/bin/python3 -c 'import sys,json; print(json.load(sys.stdin).get("status",""))')"
SUB_ID="$(printf '%s' "$SUBMIT_OUT" | /usr/bin/python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))')"

if [[ "$STATUS" != "Accepted" ]]; then
  echo ""
  echo "❌ Notarization status: $STATUS"
  echo "Fetching detailed log for submission $SUB_ID..."
  xcrun notarytool log "$SUB_ID" --keychain-profile "$PROFILE"
  exit 1
fi

# --- staple ------------------------------------------------------------------
echo "==> Stapling notarization ticket to the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# --- final assessment --------------------------------------------------------
echo "==> Gatekeeper assessment"
spctl -a -t exec -vv "$APP"

# Clean up the upload artifact; keep the stapled .app.
rm -f "$ZIP"

echo ""
echo "✅ Notarized + stapled: $APP"
echo "Ready to distribute (zip, dmg, or Homebrew cask)."
