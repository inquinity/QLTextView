//
//  ContentView.swift
//  QLTextView
//
//  Phase 1: status + onboarding. Tells the user how to enable the
//  extension and how to refresh Quick Look during testing.
//  Phase 2 replaces the body with the editable configuration UI.
//

import SwiftUI

/// The marketing version (CFBundleShortVersionString), read from Bundle so
/// the page always matches the build settings. Falls back to "unknown" if
/// the key is missing or empty.
private let appVersionLabel: String = {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    return (v?.isEmpty == false) ? v! : "unknown"
}()

// ---------------------------------------------------------------------------
// Supported extensions — keep in sync with TextDetection.defaultExtensions
// and TextDetection.defaultFilenames in QLTextViewExtension/TextDetection.swift.
// `just check-extensions` (run automatically by `just dist`) will fail the
// build if these lists drift. Phase 2 will replace them with a live query
// against the shared config.
// ---------------------------------------------------------------------------

private let supportedExtensions: [String] = [
    "yaml", "yml", "toml", "json", "jsonl", "jq", "ini", "conf", "cfg", "env",
    "ts", "properties", "lock", "log", "csv", "tsv", "tf", "tfvars",
    "dockerignore", "gitignore", "gitattributes", "editorconfig",
].sorted()

private let supportedFilenames: [String] = [
    "Dockerfile", "Makefile", "Procfile", "Brewfile", "Rakefile",
    "Gemfile", "Vagrantfile", "README", "LICENSE", "CHANGELOG",
    "INSTALL", "AUTHORS", "NOTICE", "COPYING",
].sorted()

// ---------------------------------------------------------------------------

struct ContentView: View {

    private var extensionTokens: [String] { supportedExtensions.map { ".\($0)" } }

    // Two equal flexible columns, left-aligned.
    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("QLTextView")
                    .font(.largeTitle).bold()
                Spacer()
                Text("v\(appVersionLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .textSelection(.enabled)
                    .accessibilityLabel("Version \(appVersionLabel)")
            }
            Text("A modern Quick Look text previewer. Phase 1 build — fixed allowlist, plain monospaced rendering.")
                .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Steps
                    Group {
                        Label("Enable the extension", systemImage: "1.circle.fill")
                            .font(.headline)
                        Text("System Settings → General → Login Items & Extensions → Quick Look → enable QLTextView.")
                            .foregroundStyle(.secondary)

                        Label("Refresh Quick Look while testing", systemImage: "2.circle.fill")
                            .font(.headline)
                        Text("Run in Terminal:  qlmanage -r  &&  qlmanage -r cache")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        Label("Try it", systemImage: "3.circle.fill")
                            .font(.headline)
                        Text("Select any supported file in Finder and press Space.")
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Supported extensions
                    Label("Supported extensions", systemImage: "4.circle.fill")
                        .font(.headline)

                    // Two-column grid; items sorted alphabetically, reading
                    // left-to-right across each row (left1, right1, left2, …).
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(extensionTokens, id: \.self) { token in
                            Text(token)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Text("Also previews extensionless files by name: \(supportedFilenames.joined(separator: ", ")).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(28)
        .frame(width: 520, height: 480, alignment: .topLeading)
    }
}

#Preview {
    ContentView()
}
