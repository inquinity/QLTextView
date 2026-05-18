//
//  QLTextViewApp.swift
//  QLTextView
//
//  Phase 1 host app. Its main job right now is to be the container that
//  registers the embedded Quick Look extension with the system. The real
//  configuration UI (editable extension list, size cap, etc.) is Phase 2.
//

import SwiftUI

@main
struct QLTextViewApp: App {
    var body: some Scene {
        Window("QLTextView", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
