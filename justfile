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
pbxproj            := "QLTextView.xcodeproj/project.pbxproj"
releases_dir       := "releases"

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

# ---- versioning -------------------------------------------------------------
# Two independent numbers, edited only here so the hand-maintained pbxproj keeps
# its readable formatting (we avoid `agvtool`, which would rewrite the file):
#
#   CURRENT_PROJECT_VERSION  (build number)  — auto-bumped on every `build`.
#   MARKETING_VERSION        (e.g. 0.1.0)    — changed deliberately via release
#                                              flow or `just set-version X.Y.Z`.

# Print the current marketing + build numbers.
version:
    #!/usr/bin/env bash
    set -euo pipefail
    mv=$(grep -m1 'MARKETING_VERSION'       "{{pbxproj}}" | sed -E 's/.*= ([^;]+);.*/\1/')
    bn=$(grep -m1 'CURRENT_PROJECT_VERSION' "{{pbxproj}}" | sed -E 's/.*= ([0-9]+);.*/\1/')
    echo "marketing: $mv"
    echo "build:     $bn"

# Bump the build number (+1, all configs); runs as part of `build`.
bump-build:
    #!/usr/bin/env bash
    set -euo pipefail
    cur=$(grep -oE 'CURRENT_PROJECT_VERSION = [0-9]+;' "{{pbxproj}}" \
            | grep -oE '[0-9]+' | sort -n | tail -1)
    next=$(( cur + 1 ))
    sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${next};/g" "{{pbxproj}}"
    echo "==> build number ${cur} → ${next}"

# Set the marketing version (e.g. `just set-version 0.2.0`). Deliberate action.
set-version VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! [[ "{{VERSION}}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
      echo "error: '{{VERSION}}' is not a MAJOR.MINOR.PATCH version" >&2
      exit 1
    fi
    sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = {{VERSION}};/g" "{{pbxproj}}"
    echo "==> marketing version → {{VERSION}}"

# ---- build pipeline ---------------------------------------------------------

# Remove all build artifacts.
clean:
    rm -rf build

# Signing is intentionally disabled here — `just sign` applies the Developer ID
# signature + entitlements afterward (the "outside Xcode" flow). `bump-build`
# runs first, so every build carries a fresh, never-reused build number.
#
# Build the unsigned host app + extension (auto-bumps the build number).
build: bump-build
    DEVELOPER_DIR={{xcode_dev}} \
      xcodebuild -project QLTextView.xcodeproj \
                 -target QLTextView \
                 -configuration {{config}} \
                 CODE_SIGN_IDENTITY="" \
                 CODE_SIGN_ENTITLEMENTS="" \
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

# Verify that the extension list in ContentView.swift matches the one in
# TextDetection.swift. Run automatically by `dist` — catches drift before
# the expensive build/sign/notarize steps.
check-extensions:
    #!/usr/bin/env bash
    set -euo pipefail
    td="QLTextViewExtension/TextDetection.swift"
    cv="QLTextView/ContentView.swift"
    # macOS system awk does not support \s; use POSIX [[:space:]] instead.
    # td: range ends on the line that is nothing but whitespace + "]"
    # cv: range ends on "].sorted()" (the only ] followed immediately by .sorted)
    td_exts=$(awk '/static let defaultExtensions/,/^[[:space:]]*\]$/' "$td" \
                | grep -oE '"[a-z][^"]*"' | tr -d '"' | sort)
    cv_exts=$(awk '/private let supportedExtensions/,/\]\.sorted/' "$cv" \
                | grep -oE '"[a-z][^"]*"' | tr -d '"' | sort)
    if [[ "$td_exts" != "$cv_exts" ]]; then
      echo "error: extension lists are out of sync" >&2
      echo "  in TextDetection but missing from ContentView:" >&2
      comm -23 <(echo "$td_exts") <(echo "$cv_exts") | sed 's/^/    /' >&2
      echo "  in ContentView but missing from TextDetection:" >&2
      comm -13 <(echo "$td_exts") <(echo "$cv_exts") | sed 's/^/    /' >&2
      echo "Update both files then re-run." >&2
      exit 1
    fi
    echo "✅ Extension lists in sync ($(echo "$td_exts" | wc -l | tr -d ' ') extensions)"

# Repeatable and side-effect-free w.r.t. git/versioning — run it as often as you
# like to produce a notarized zip for testing on another machine ("trial
# release"). The zip is named with marketing + build numbers so successive
# trials of the same version are distinguishable. Does NOT tag or release.
#
# Build a notarized distributable zip (clean → build → sign → notarize → zip).
dist: check-extensions clean build sign notarize
    #!/usr/bin/env bash
    set -euo pipefail
    mv=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "{{app}}/Contents/Info.plist")
    bn=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion"             "{{app}}/Contents/Info.plist")
    out="build/QLTextView-${mv}-${bn}.zip"
    ditto -c -k --keepParent "{{app}}" "$out"
    echo "✅ Distribution ready: $out  (v${mv}, build ${bn})"

# Steps: (1) require clean tree + unused tag; (2) dist (bumps build number);
# (3) archive zip into releases/; (4) commit the bump + annotated tag v<version>;
# (5) post-bump the patch version and commit "start <next> development".
# For a minor/major bump, run `just set-version X.Y.0` and commit first.
#
# Finalize an official release of the current marketing version.
release:
    #!/usr/bin/env bash
    set -euo pipefail

    # 1a. clean working tree
    if [[ -n "$(git status --porcelain)" ]]; then
      echo "error: working tree not clean — commit or stash before releasing." >&2
      git status --short >&2
      exit 1
    fi
    # 1b. the version we're about to ship, and a tag-collision guard (fail
    #     before the slow notarize step, not after).
    version=$(grep -m1 'MARKETING_VERSION' "{{pbxproj}}" | sed -E 's/.*= ([^;]+);.*/\1/')
    tag="v${version}"
    if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
      echo "error: tag ${tag} already exists — bump with: just set-version X.Y.Z" >&2
      exit 1
    fi
    echo "==> Releasing ${tag}"

    # 2. produce the notarized distributable (bumps the build number)
    just dist

    # 3. authoritative version/build come from the built bundle
    mv=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "{{app}}/Contents/Info.plist")
    bn=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion"             "{{app}}/Contents/Info.plist")
    mkdir -p "{{releases_dir}}"
    cp "build/QLTextView-${mv}-${bn}.zip" "{{releases_dir}}/"
    echo "==> Archived {{releases_dir}}/QLTextView-${mv}-${bn}.zip"

    # 4. release commit (captures the build-number bump) + annotated tag
    git add -A
    git commit -m "Release ${tag} (build ${bn})"
    git tag -a "${tag}" -m "QLTextView ${mv} (build ${bn})"

    # 5. post-bump the patch version for ongoing development
    IFS=. read -r maj min pat <<< "${mv}"
    next="${maj}.${min}.$(( pat + 1 ))"
    just set-version "${next}"
    git add -A
    git commit -m "Start ${next} development"

    echo "✅ Released ${tag} (build ${bn}); now on ${next}-dev"
    echo "   Publish with:  git push && git push origin ${tag}"

# Also repairs Launch Services: a Quick Look extension is keyed by bundle ID,
# and stray copies (build/, worktrees) can win the registration over the
# installed app — silently breaking previews. We deregister every copy that
# isn't /Applications, then force-register the installed one.
#
# Install the signed build to /Applications and refresh Quick Look.
install:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -d "{{app}}" ]] || { echo "no build — run: just build sign" >&2; exit 1; }
    lsreg="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    canonical="/Applications/QLTextView.app"

    rm -rf "$canonical"
    cp -R "{{app}}" /Applications/

    echo "==> Deregistering stray copies of the bundle"
    strays=$("$lsreg" -dump 2>/dev/null \
      | grep -oE '/[^"]*QLTextView\.app' \
      | sort -u \
      | grep -vx "$canonical" || true)
    if [[ -n "$strays" ]]; then
      while IFS= read -r stray; do
        echo "    - $stray"
        "$lsreg" -u "$stray" 2>/dev/null || true
      done <<< "$strays"
    else
      echo "    (none)"
    fi

    echo "==> Registering $canonical"
    "$lsreg" -f "$canonical"

    # Reinstalling resets the extension to disabled; re-enable it so Quick Look
    # is actually allowed to use it (otherwise files fall back to a generic panel).
    echo "==> Enabling the Quick Look extension"
    pluginkit -e use -i com.qltextview.app.QLTextViewExtension 2>/dev/null || true

    echo "==> Refreshing Quick Look"
    qlmanage -r       >/dev/null 2>&1 || true
    qlmanage -r cache >/dev/null 2>&1 || true

    echo "✅ Installed to $canonical"
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
