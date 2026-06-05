# Adding a new file extension

Two files need to change, plus a rebuild. The order matters.

## Before you start — check the UTI

Run this in Terminal (replace `e42` with your extension):

```bash
touch /tmp/test.e42
mdls -name kMDItemContentType -name kMDItemContentTypeTree /tmp/test.e42
```

| `kMDItemContentType` result | What it means | Which path to follow |
|---|---|---|
| `dyn.ah62…` (dynamic) | No app or system owns this extension yet | **Common path** — Steps 1 + 2 below |
| A named UTI (e.g. `public.yaml`) | System or an installed app already declared it | **Named UTI path** — Step 2 only (see note) |
| A named video/audio UTI | A system handler may beat your extension | Check the Known Limitations section in README.md |

---

## Common path — dynamic UTI (most unknown extensions)

### Step 1 — Declare the extension in the host app's `Info.plist`

Open `QLTextView/Info.plist`. Find the `UTExportedTypeDeclarations` array and add
your extension alongside the existing entries:

```xml
<key>public.filename-extension</key>
<array>
    <string>jq</string>
    <string>jsonl</string>
    <!-- add yours here -->
    <string>e42</string>
    ...
</array>
```

This binds your extension to the `com.qltextview.app.previewable-text` UTI
(which conforms to `public.plain-text`), so Quick Look routes the file to the
extension. **Without this step, routing silently fails for dynamic-UTI files.**

### Step 2 — Add to the in-code allowlist

Open `QLTextViewExtension/TextDetection.swift` and add your extension to
`defaultExtensions`:

```swift
static let defaultExtensions: Set<String> = [
    "yaml", "yml", "toml", "json", "jsonl", "jq",
    "e42",   // ← add here
    ...
]
```

This documents the intent and is the last guard before rendering: even if
routing works, the byte-sniff will reject binary files with your extension.

### Step 3 — Rebuild and install

```bash
just build && just sign && just install
```

Test in Finder: select a file with your new extension and press Space.

---

## Named UTI path

If `mdls` returned a named UTI (not `dyn.*`), the extension is already bound
to a known type. Skip Step 1 (`Info.plist`). Instead, check whether that UTI
is already declared in `QLTextViewExtension/Info.plist` under
`QLSupportedContentTypes`. If it is, only Step 2 is needed. If it isn't, add
the UTI string to that array as well.

---

## Does this require a new release?

Yes. Both `Info.plist` (baked into the bundle at build time) and
`TextDetection.swift` (compiled Swift) require a rebuild. The fast loop
(`just build && just sign && just install`) is enough for local use. For
distributing to other machines, run `just dist`.

**Phase 2 note:** When user-editable configuration is implemented, extensions
whose UTI is already covered by the existing `QLSupportedContentTypes`
declarations will be addable at runtime without a rebuild. Extensions that need
a new `UTExportedTypeDeclarations` entry will always require a new build.
