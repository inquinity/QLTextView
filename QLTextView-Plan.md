# QLTextView — Project Plan

A modern Quick Look text previewer for macOS Tahoe (26) and later. Spiritual successor to `qlstephen`, rebuilt on Apple's current App Extension architecture, with **runtime-configurable file extensions** so you can say "treat `.yaml`, `.toml`, `.jq`, … as text" without rebuilding or re-signing.

---

## 1. The core problem (why no good solution exists)

`qlstephen` worked because it used the **legacy Quick Look Generator API** (`.qlgenerator` bundles). That API let one plugin claim a broad type like `public.data` and decide *in code, at runtime* whether to render a file as text. Apple deprecated this API in macOS 10.15 and has been progressively removing it; it is not a viable foundation for Tahoe and later.

The **modern API (macOS 11+)** is the App Extension model:

- A **host app** (`.app`) containing an embedded **Quick Look Preview Extension** (`.appex`).
- The extension declares the types it handles in a **static `QLSupportedContentTypes` array** in its `Info.plist`.
- Quick Look routes a file to the extension **only if the file's resolved UTI exactly matches** an entry in that array. Declaring a *parent* type (e.g. `public.data`) is explicitly **not** sufficient — the match must be against the file's actual resolved type.

That static, code-signed plist is the entire reason "add an extension without rebuilding" is hard: the OS reads supported types from the signed bundle at registration time, not at preview time.

### The resolution

The fix is a two-layer design:

1. **Layer 1 — broad UTI net (static, in plist):** Declare the small set of *broad* text-family UTIs that the system already resolves the overwhelming majority of text-ish files to: `public.plain-text`, `public.text`, `public.source-code`, `public.script`, `public.shell-script`, `public.xml`, `public.json`, `public.yaml`, and `public.data` as the catch-all. Most files you care about (`yaml`, `toml`, `ini`, `conf`, `env`, `Dockerfile`, dotfiles, `jq`, …) already resolve to one of these through the system UTI database.

2. **Layer 2 — runtime allowlist (dynamic, in code):** The extension reads a **user-editable config file** at preview time. For each file it's handed, it checks the extension/filename against the user's allowlist, sniffs the bytes to confirm the content is actually text (not binary), and then renders or politely declines. **Adding an extension to the config takes effect immediately** for any file resolving to one of the Layer-1 UTIs — no rebuild, no re-sign.

3. **Escape hatch (documented, rare):** For a genuinely novel extension the system maps to *nothing* text-like (so Layer 1 never hands it to us), document an optional `UTImportedTypeDeclarations` entry the user can add. This is the only path that requires a rebuild, and in practice it is rarely needed.

This delivers `qlstephen`'s "it just works" behavior on the modern, supported, notarizable architecture.

---

## 2. Decisions locked in

| Area | Decision |
|---|---|
| UTI strategy | Broad UTI net in plist + in-code runtime allowlist; documented import-declaration escape hatch |
| Configuration UX | SwiftUI host app with an editable extension list + max-file-size; config persisted to a shared on-disk file; hand-editable; `defaults`-compatible fallback for `qlstephen` muscle memory |
| Rendering | Phase 1: fast plain monospaced text (qlstephen parity). Phase 2 (documented, later): optional syntax highlighting |
| Distribution | Architect for Developer ID signing + notarization; iterate locally unsigned first; ship signed/notarized build (Homebrew-cask-friendly) |
| Apple account | Paid Developer account available (dormant — see §8 re-activation gotchas) |
| Language / UI | Swift end-to-end. SwiftUI for the host app. Swift extension using AppKit `NSTextView` as the render surface (predictable for large read-only monospaced text). No Objective-C/C anywhere |

---

## 3. Architecture

```
QLTextView.app                         (host app — SwiftUI)
├── Contents/MacOS/QLTextView          configuration UI + onboarding
├── Contents/PlugIns/
│   └── QLTextViewExtension.appex       Quick Look Preview Extension
│       └── QLSupportedContentTypes     ← Layer 1 broad UTI net (static)
└── Shared config (App Group container)
    └── config.json                     ← Layer 2 allowlist + settings (dynamic)
```

### Components

**A. Host app (`QLTextView`)**
- SwiftUI menu-bar + window app.
- Editable list of extensions/filenames to treat as text (add/remove rows).
- "Max preview size" field (mirrors qlstephen's `maxFileSize`, default 100 KB).
- Reads/writes the shared config file in an **App Group container** (so the sandboxed extension can read it).
- Onboarding panel: how to enable the extension in System Settings, how to refresh Quick Look (`qlmanage -r`), troubleshooting.
- Optional: "Reveal config file" + "Restart Quick Look" buttons.

**B. Quick Look Preview Extension (`QLTextViewExtension`)**
- Implements `QLPreviewingController` (view-based) — an `NSViewController` subclass.
- On `preparePreviewOfFile(at:)`:
  1. Load shared config (allowlist + max size + options).
  2. Resolve the file's effective extension / leaf name (handles extensionless files and dotfiles).
  3. **Decision:** is it in the allowlist *or* does the binary sniff say "this is text"? If neither → render a clear "Not previewed as text" placeholder (don't crash, don't show garbage).
  4. Read up to `maxFileSize` bytes; detect encoding (UTF‑8 → UTF‑16 → ISO‑8859‑1 fallback chain); decode.
  5. Render into a read-only monospaced `NSTextView` (line-wrap toggle from config).
  6. Respect Quick Look's tight time budget — stream/limit large files, never block.
- No network, minimal entitlements, sandboxed.

**C. Shared config (`config.json`)**
```json
{
  "version": 1,
  "extensions": ["yaml", "yml", "toml", "jq", "ini", "conf", "env"],
  "filenames": ["Dockerfile", "Makefile", "Procfile", ".gitignore"],
  "maxFileSize": 102400,
  "wrapLines": true,
  "treatUnknownAsTextIfDetected": true
}
```
- Lives in the App Group container; also symlinked/mirrored to `~/.config/qltextview/config.json` for hand-editing convenience.
- `defaults read com.<you>.qltextview maxFileSize` honored as an override for parity with qlstephen users.

---

## 4. Key technical decisions & risks

| Topic | Approach | Risk / mitigation |
|---|---|---|
| Extension not invoked for a type | Broad UTI net covers the common cases | If a file resolves to a UTI we didn't list, it never reaches us. Mitigation: include `public.data` catch-all + document import-declaration escape hatch |
| Sandbox can't read config | Use **App Group** shared container | Must enable App Groups capability on *both* targets with the *same* group ID; verify the extension can actually read it (sandbox is strict) |
| Binary files matching `public.data` | Byte-sniff (NUL bytes, control-char ratio, encoding validity) before rendering | Conservative heuristic; on "unsure" show placeholder, not garbage |
| Quick Look performance budget | Hard byte cap, lazy decode, no main-thread blocking | Extensions that are slow get killed by the OS; measure with large files |
| Debugging difficulty | Extensions run outside Xcode debugger | Use `os_log`/Console; `qlmanage -p <file>` and `qlmanage -r` for the dev loop |
| Precedence vs other plugins | `qlmanage -m` to inspect which generator/extension wins | Document conflict diagnosis in troubleshooting |
| Gatekeeper/quarantine | Notarize for distribution | Document `xattr -cr` + `qlmanage -r` workaround for local/unsigned builds |

---

## 5. Build phases

### Phase 0 — Project scaffolding
- Xcode project: macOS app target (SwiftUI) + Quick Look Preview Extension target.
- Set deployment target to macOS 26 (Tahoe). Bundle IDs: `com.<you>.qltextview` / `.extension`.
- Enable **App Groups** capability on both targets, shared ID `group.com.<you>.qltextview`.
- Confirm empty extension registers: build, run host app, check **System Settings → General → Login Items & Extensions → Quick Look**.

### Phase 1 — Minimum viable previewer (qlstephen parity)
- Implement `QLPreviewingController` with monospaced read-only rendering.
- Hardcode a sensible default allowlist; implement byte-sniff + encoding fallback + size cap.
- Populate `QLSupportedContentTypes` with the Layer-1 broad net.
- **Exit criterion:** previewing `.yaml`, `.toml`, `.jq`, an extensionless `README`, and a dotfile all show correct text via spacebar in Finder.

### Phase 2 — Configuration app + shared config
- SwiftUI host UI: editable extension/filename lists, max-size field, wrap toggle.
- Read/write `config.json` in the App Group container; mirror to `~/.config/qltextview/`.
- Extension reads config live (re-read each preview; cheap).
- `defaults` override compatibility.
- **Exit criterion:** add `xyz` in the app, immediately preview a `.xyz` text file with no rebuild.

### Phase 3 — Polish & robustness
- Onboarding/troubleshooting UI ("enable me", "refresh Quick Look", "reveal config").
- Graceful placeholders for binary / too-large / undecodable files.
- Edge cases: huge files, CRLF, BOMs, mixed encodings, symlinks, zero-byte files.
- Light/dark appearance, line numbers (optional), wrap toggle.

### Phase 4 — Signing, notarization, distribution
- Re-activate Developer account (see §8), regenerate Developer ID Application cert.
- Sign host app + embedded `.appex` (hardened runtime), notarize, staple.
- Produce a zip/dmg; draft a Homebrew cask.
- **Exit criterion:** fresh-Mac install with no quarantine prompts; extension works after a normal install.

### Phase 5 (optional, later) — Syntax highlighting
- Pluggable highlighter (e.g. tree-sitter or Highlightr) behind a config flag, default off, with strict perf budget so previews stay instant.

---

## 6. Open questions to resolve during build

1. **App Group vs. alternative config delivery.** App Groups is the clean path but historically finicky for Quick Look extensions under sandbox. Fallback options to keep in pocket: a config file in a known location read via a security-scoped bookmark, or a small XPC helper. Decide empirically in Phase 0/2.
2. **Default-on byte sniffing.** Should an unrecognized extension still preview if the bytes are clearly text (`treatUnknownAsTextIfDetected`)? This is the closest to qlstephen's magic; default **on**, but make it a visible toggle.
3. **Exact Layer-1 UTI list.** Finalize empirically by running `mdls`/`qlmanage -m` against a corpus of real config files to see what each resolves to on Tahoe.

---

## 7. Testing strategy

- **Corpus:** `.yaml .yml .toml .jq .ini .conf .env .properties .gitignore Dockerfile Makefile`, extensionless (`README`, `LICENSE`), dotfiles (`.zshrc`), large file (>1 MB), binary mislabeled as text, UTF‑16/BOM, CRLF, zero-byte.
- **Methods:** `qlmanage -p <file>` (render), `qlmanage -m` (precedence), Finder spacebar (real path), Console for `os_log`.
- **Regression:** scripted run of the corpus through `qlmanage` after each phase.

---

## 8. Dormant Developer account — reactivation gotchas (Phase 4)

Because the account hasn't been used in years, expect and plan for:
- **Updated Apple Developer Program License Agreement** must be accepted in the developer portal before any new certificate/notarization works (silent failures otherwise).
- **Expired certificates:** old Developer ID / signing certs are almost certainly expired — regenerate a **Developer ID Application** certificate.
- **App-specific password / notarytool credentials:** set up a fresh app-specific password (or API key) for `notarytool`; old Application Loader / `altool` flows are gone.
- **Xcode/account state:** sign out/in of the Apple ID in Xcode → Settings → Accounts so it refreshes teams and provisioning.
- Do this re-activation *early in Phase 4*, not at the end — agreement/cert propagation can take time and blocks notarization.

---

## 9. Deliverables

- `QLTextView.app` (host app + embedded extension), signed & notarized.
- Editable `config.json` with documented schema.
- README: install, enable, configure, troubleshoot (incl. `qlmanage -r`, `xattr -cr`, precedence checks).
- Homebrew cask draft.
- This plan, updated as decisions are validated.

---

## Suggested immediate next step

Build **Phase 0 + Phase 1** as a single first milestone — a hardcoded-allowlist previewer that proves the modern extension actually gets invoked on Tahoe for `.yaml`/extensionless files. That de-risks the entire approach (the "does the broad UTI net actually catch these files" question) before investing in the config app. Everything else is incremental once that's proven.
