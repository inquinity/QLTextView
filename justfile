# QLTextView — build / sign / notarize / install
#
# Run `just` (no args) for the list of recipes.
# Most recipes act on a Release build by default; override with:
#   just config=Debug build
#
# One-time setup (notarization only):
#   just notary-setup    # prints the credential-store command

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# ---- config (overridable) ---------------------------------------------------
identity       := env_var_or_default("IDENTITY",       "Developer ID Application: Altman Software Design, LLC (45GJWJVQN2)")
team_id        := env_var_or_default("TEAM_ID",        "45GJWJVQN2")
apple_id       := env_var_or_default("APPLE_ID",       "robert@altmansoftwaredesign.com")
notary_profile := env_var_or_default("NOTARY_PROFILE", "QLTextView-Notary")
config         := env_var_or_default("CONFIG",         "Release")

xcode_dev          := "/Applications/Xcode.app/Contents/Developer"
app                := "build" / config / "QLTextView.app"
appex              := app / "Contents/PlugIns/QLTextViewExtension.appex"
app_entitlements   := "QLTextView/QLTextView.entitlements"
appex_entitlements := "QLTextViewExtension/QLTextViewExtension.entitlements"

# Default: show the recipe list.
default: help

# Show all recipes.
help:
    @just --list --unsorted

# ---- inspection -------------------------------------------------------------

# List code-signing identities the keychain exposes to codesign.
identities:
    @security find-identity -v -p codesigning

# Print the one-time notarytool credential-store command, pre-filled.
notary-setup:
    @echo "1. Generate an app-specific password:"
    @echo "     https://account.apple.com/sign-in  →  Sign-In and Security  →  App-Specific Passwords  →  +"
    @echo ""
    @echo "2. Then run (substituting the password Apple shows you):"
    @echo ""
    @echo "     xcrun notarytool store-credentials '{{notary_profile}}' \\"
    @echo "       --apple-id '{{apple_id}}' \\"
    @echo "       --team-id  '{{team_id}}' \\"
    @echo "       --password 'xxxx-xxxx-xxxx-xxxx'"
    @echo ""
    @echo "Verify with: just notary-check"

# Verify the notarytool keychain profile is set up.
notary-check:
    @xcrun notarytool history --keychain-profile "{{notary_profile}}" >/dev/null 2>&1 \
      && echo "✅ notary profile '{{notary_profile}}' is set up" \
      || (echo "❌ notary profile '{{notary_profile}}' not found — run: just notary-setup"; exit 1)

# ---- build pipeline ---------------------------------------------------------

# Remove all build artifacts.
clean:
    rm -rf build

# Build host app + embedded extension via xcodebuild (default: Release).
# Signing is intentionally disabled here — `just sign` applies the
# Developer ID signature + entitlements afterward (the "outside Xcode" flow).
build:
    DEVELOPER_DIR={{xcode_dev}} \
      xcodebuild -project QLTextView.xcodeproj \
                 -target QLTextView \
                 -configuration {{config}} \
                 CODE_SIGN_IDENTITY="" \
                 CODE_SIGN_STYLE=Manual \
                 CODE_SIGNING_REQUIRED=NO \
                 CODE_SIGNING_ALLOWED=NO \
                 -quiet
    @echo "✅ Built {{app}} (unsigned — run: just sign)"

# Sign app + embedded appex with Developer ID, hardened runtime, secure timestamp.
sign: _require-identity
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -d "{{app}}" ]] || { echo "no build at {{app}} — run: just build" >&2; exit 1; }
    echo "==> Signing appex"
    codesign --force --sign "{{identity}}" \
      --options runtime --timestamp \
      --entitlements "{{appex_entitlements}}" \
      "{{appex}}"
    echo "==> Signing host app"
    codesign --force --sign "{{identity}}" \
      --options runtime --timestamp \
      --entitlements "{{app_entitlements}}" \
      "{{app}}"
    echo "==> Verifying"
    codesign --verify --deep --strict --verbose=2 "{{app}}"
    codesign -dvv "{{app}}" 2>&1 | grep -E 'Identifier|TeamIdentifier|Authority|Signature|Timestamp'
    echo "==> Gatekeeper (expect 'Unnotarized Developer ID' until notarized)"
    spctl -a -t exec -vv "{{app}}" || true
    echo "✅ Signed {{app}}"

# Submit signed app to Apple, wait, staple, verify.
notarize: _require-profile
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -d "{{app}}" ]] || { echo "no build at {{app}}" >&2; exit 1; }
    SIG=$(codesign -dvv "{{app}}" 2>&1)
    grep -q 'Signature=adhoc' <<<"$SIG" && { echo "ad-hoc signed — run: just sign" >&2; exit 1; }
    grep -q 'Timestamp=' <<<"$SIG" || { echo "no secure timestamp — re-run: just sign" >&2; exit 1; }
    ZIP="build/QLTextView-notarize.zip"
    rm -f "$ZIP"
    echo "==> Packaging"
    ditto -c -k --keepParent "{{app}}" "$ZIP"
    echo "==> Submitting to Apple (1–10 min)…"
    OUT=$(xcrun notarytool submit "$ZIP" --keychain-profile "{{notary_profile}}" --wait --output-format json)
    echo "$OUT"
    STATUS=$(printf '%s' "$OUT" | /usr/bin/python3 -c 'import sys,json; print(json.load(sys.stdin).get("status",""))')
    SUB_ID=$(printf '%s' "$OUT" | /usr/bin/python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))')
    if [[ "$STATUS" != "Accepted" ]]; then
      echo "❌ status=$STATUS — fetching log for $SUB_ID"
      xcrun notarytool log "$SUB_ID" --keychain-profile "{{notary_profile}}"
      exit 1
    fi
    echo "==> Stapling"
    xcrun stapler staple "{{app}}"
    xcrun stapler validate "{{app}}"
    spctl -a -t exec -vv "{{app}}"
    rm -f "$ZIP"
    echo "✅ Notarized + stapled {{app}}"

# Full distributable pipeline: clean → build → sign → notarize → zip.
release: clean build sign notarize
    #!/usr/bin/env bash
    set -euo pipefail
    OUT="build/QLTextView-$(date +%Y%m%d).zip"
    ditto -c -k --keepParent "{{app}}" "$OUT"
    echo "✅ Release ready: $OUT"

# Install the signed build to /Applications and refresh Quick Look.
install:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -d "{{app}}" ]] || { echo "no build — run: just build sign" >&2; exit 1; }
    rm -rf /Applications/QLTextView.app
    cp -R "{{app}}" /Applications/
    qlmanage -r       >/dev/null 2>&1 || true
    qlmanage -r cache >/dev/null 2>&1 || true
    echo "✅ Installed to /Applications/QLTextView.app"
    echo "Enable: System Settings → General → Login Items & Extensions → Quick Look → toggle QLTextView on"
    open /Applications/QLTextView.app

# ---- private guards ---------------------------------------------------------

_require-identity:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! security find-identity -v -p codesigning | grep -q "{{identity}}"; then
      echo "error: signing identity not found:" >&2
      echo "       {{identity}}" >&2
      echo "Available:" >&2
      security find-identity -v -p codesigning >&2
      exit 1
    fi

_require-profile:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! xcrun notarytool history --keychain-profile "{{notary_profile}}" >/dev/null 2>&1; then
      echo "error: notarytool profile '{{notary_profile}}' not set up." >&2
      echo "Run: just notary-setup" >&2
      exit 1
    fi
