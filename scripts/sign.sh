#!/usr/bin/env bash
#
# sign.sh — code-sign QLTextView.app (and its embedded .appex) with
# our Developer ID identity, hardened runtime, and entitlements.
#
# Quick Look extensions are sandboxed app extensions. The OS will only
# register / load them if they are properly signed AND carry the right
# entitlements in the embedded signature. The linker-signed ad-hoc
# signature you get from `CODE_SIGNING_ALLOWED=NO` builds is NOT
# enough — it has no entitlements blob.
#
# Sign order matters: the .appex inside Contents/PlugIns must be signed
# BEFORE the host .app, because the app's CodeDirectory seals the
# embedded appex's signature. We walk inside-out.
#
# Usage:
#   scripts/sign.sh                              # signs build/Debug/QLTextView.app
#   scripts/sign.sh path/to/Some.app             # sign a different bundle
#   TIMESTAMP=no scripts/sign.sh                 # skip Apple's timestamp server
#                                                  (offline iteration only — required for notarization)
#   IDENTITY="Apple Development: ..." scripts/sign.sh   # use a different identity
#
set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "$SCRIPT_DIR/.." && pwd )"

# --- config (overridable via env) ---------------------------------------------
IDENTITY="${IDENTITY:-Developer ID Application: Altman Software Design, LLC (45GJWJVQN2)}"
APP="${1:-$REPO_ROOT/build/Debug/QLTextView.app}"
APP_ENTITLEMENTS="${APP_ENTITLEMENTS:-$REPO_ROOT/QLTextView/QLTextView.entitlements}"
APPEX_ENTITLEMENTS="${APPEX_ENTITLEMENTS:-$REPO_ROOT/QLTextViewExtension/QLTextViewExtension.entitlements}"

# --timestamp hits timestamp.apple.com. Required for notarization.
# Set TIMESTAMP=no to skip when iterating offline.
if [[ "${TIMESTAMP:-yes}" == "no" ]]; then
  TS_FLAG="--timestamp=none"
else
  TS_FLAG="--timestamp"
fi

# --- sanity checks -----------------------------------------------------------
if [[ ! -d "$APP" ]]; then
  echo "error: app bundle not found: $APP" >&2
  exit 1
fi
APPEX="$APP/Contents/PlugIns/QLTextViewExtension.appex"
if [[ ! -d "$APPEX" ]]; then
  echo "error: expected embedded appex not found: $APPEX" >&2
  exit 1
fi
for f in "$APP_ENTITLEMENTS" "$APPEX_ENTITLEMENTS"; do
  [[ -f "$f" ]] || { echo "error: entitlements file missing: $f" >&2; exit 1; }
done
if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "error: signing identity not found or invalid:" >&2
  echo "       $IDENTITY" >&2
  echo "Available identities:" >&2
  security find-identity -v -p codesigning >&2
  exit 1
fi

# --- sign --------------------------------------------------------------------
echo "==> Signing appex"
echo "    $APPEX"
codesign --force --sign "$IDENTITY" \
  --options runtime $TS_FLAG \
  --entitlements "$APPEX_ENTITLEMENTS" \
  "$APPEX"

echo "==> Signing host app"
echo "    $APP"
codesign --force --sign "$IDENTITY" \
  --options runtime $TS_FLAG \
  --entitlements "$APP_ENTITLEMENTS" \
  "$APP"

# --- verify ------------------------------------------------------------------
echo "==> Verifying signature (deep + strict)"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Final signature summary"
codesign -dvv "$APP" 2>&1 | grep -E 'Identifier|TeamIdentifier|Authority|Signature|Format'
echo "--- appex ---"
codesign -dvv "$APPEX" 2>&1 | grep -E 'Identifier|TeamIdentifier|Authority|Signature|Format'

echo "==> Gatekeeper assessment (will fail until notarized — expected)"
spctl -a -t exec -vv "$APP" || true

echo ""
echo "✅ Signed: $APP"
if [[ "${TIMESTAMP:-yes}" == "no" ]]; then
  echo "⚠️  Built WITHOUT a trusted timestamp. Re-sign with TIMESTAMP=yes before notarizing."
else
  echo "Next: scripts/notarize.sh \"$APP\""
fi
