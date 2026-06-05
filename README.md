# QLTextView
QuickLook Text Viewer for multiple files types

## Known limitations

### `.ts` files are not previewed

TypeScript source files (`.ts`) collide with MPEG-2 transport-stream video,
which macOS binds to the `.ts` extension system-wide as
`public.mpeg-2-transport-stream`. Quick Look then routes the file to the
legacy `/System/Library/QuickLook/Movie.qlgenerator`, which claims the
parent type `public.movie`. That generator wins selection over our app
extension, fails to produce a preview for what is actually text, and Quick
Look does not fall through to other candidates — so the file shows the
generic "no preview" panel.

There is no clean third-party workaround:

- A third-party app cannot override the system's `.ts → public.mpeg-2-transport-stream`
  UTI binding. We declare `.ts` in the host app's `UTExportedTypeDeclarations`,
  but `mdls` confirms the file still resolves to `public.mpeg-2-transport-stream`.
- Declaring `public.mpeg-2-transport-stream` in the extension's
  `QLSupportedContentTypes` doesn't help either — Movie.qlgenerator beats our
  app extension on the routing.
- Disabling Movie.qlgenerator system-wide would require disabling SIP and
  would break Quick Look for genuine video files.

The relevant declarations are left in place (`public.mpeg-2-transport-stream`
in `QLTextViewExtension/Info.plist`, `ts` in the
`UTExportedTypeDeclarations` filename-extension list, and `ts` in
`TextDetection.defaultExtensions`) so that **if Apple retires
Movie.qlgenerator** — it has long been deprecated — `.ts` previews will
start working without a code change.

### File size cap

Files larger than 100 KB are previewed truncated, ending with a
`[truncated — file exceeds 100 KB preview limit]` notice. The cap is
`TextDetection.defaultMaxBytes`.
