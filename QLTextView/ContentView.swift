//
//  ContentView.swift
//  QLTextView
//
//  Phase 1: status + onboarding. Tells the user how to enable the
//  extension and how to refresh Quick Look during testing.
//  Phase 2 replaces the body with the editable configuration UI.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("QLTextView")
                .font(.largeTitle).bold()
            Text("A modern Quick Look text previewer. Phase 1 build — fixed allowlist, plain monospaced rendering.")
                .foregroundStyle(.secondary)

            Divider()

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
                Text("Select a .yaml, .toml, .jq, or an extensionless README in Finder and press Space.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(28)
        .frame(width: 520, height: 420, alignment: .topLeading)
    }
}

#Preview {
    ContentView()
}
