//
//  PreviewViewController.swift
//  QLTextViewExtension
//
//  Phase 1 renderer: read-only monospaced NSTextView.
//  Implements QLPreviewingController (the modern, macOS 11+ API).
//

import Cocoa
import Quartz
import os

private let log = Logger(subsystem: "com.qltextview.extension", category: "preview")

final class PreviewViewController: NSViewController, QLPreviewingController {

    private var scrollView: NSScrollView!
    private var textView: NSTextView!

    override func loadView() {
        // Build the view hierarchy programmatically — no storyboard,
        // keeps the extension lean and startup fast.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        let scroll = NSScrollView(frame: container.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder

        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        tv.textColor = .textColor
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: .greatestFiniteMagnitude)

        scroll.documentView = tv
        container.addSubview(scroll)

        self.scrollView = scroll
        self.textView = tv
        self.view = container
    }

    // Modern file-based entry point.
    func preparePreviewOfFile(at url: URL) async throws {
        log.debug("preparePreviewOfFile: \(url.lastPathComponent, privacy: .public)")

        // Phase 1: hardcoded allowlist + defaults. Phase 2 swaps these
        // for the user-editable shared App Group config.
        let result = TextDetection.load(
            url: url,
            allowedExtensions: TextDetection.defaultExtensions,
            allowedFilenames: TextDetection.defaultFilenames,
            maxBytes: TextDetection.defaultMaxBytes,
            sniffUnknown: true)

        await MainActor.run {
            switch result {
            case .text(let body):
                render(body, monospaced: true, dimmed: false)
            case .notText:
                render("This file does not appear to be text, so QLTextView did not preview it.",
                       monospaced: false, dimmed: true)
            case .tooLarge(let size):
                render("File is too large to preview (\(size) bytes).",
                       monospaced: false, dimmed: true)
            case .unreadable(let why):
                render(why, monospaced: false, dimmed: true)
            }
        }
    }

    @MainActor
    private func render(_ string: String, monospaced: Bool, dimmed: Bool) {
        textView.font = monospaced
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 13)
        textView.textColor = dimmed ? .secondaryLabelColor : .textColor
        textView.string = string
        textView.scrollToBeginningOfDocument(nil)
    }
}
