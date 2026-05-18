//
//  TextDetection.swift
//  QLTextViewExtension
//
//  Phase 1: the core "is this text, and if so decode it" logic.
//  Deliberately dependency-free and fast — this runs inside the Quick Look
//  performance budget, out-of-process, with no debugger attached.
//

import Foundation

enum TextDetection {

    /// Result of attempting to load a file as text.
    enum LoadResult {
        case text(String)
        case notText            // looked like binary
        case tooLarge(Int)      // exceeded the configured byte cap
        case unreadable(String) // I/O or decode failure, with a reason
    }

    /// Hardcoded Phase-1 allowlist. Phase 2 replaces this with the
    /// user-editable shared config. Kept intentionally small but
    /// representative of the qlstephen use case.
    static let defaultExtensions: Set<String> = [
        "yaml", "yml", "toml", "jq", "ini", "conf", "cfg", "env",
        "properties", "lock", "log", "csv", "tsv", "tf", "tfvars",
        "dockerignore", "gitignore", "gitattributes", "editorconfig"
    ]

    static let defaultFilenames: Set<String> = [
        "Dockerfile", "Makefile", "Procfile", "Brewfile", "Rakefile",
        "Gemfile", "Vagrantfile", "README", "LICENSE", "CHANGELOG",
        "INSTALL", "AUTHORS", "NOTICE", "COPYING"
    ]

    /// Default byte cap, mirrors qlstephen's 100 KB default.
    static let defaultMaxBytes = 102_400

    /// Decide + load in one call.
    static func load(url: URL,
                     allowedExtensions: Set<String>,
                     allowedFilenames: Set<String>,
                     maxBytes: Int,
                     sniffUnknown: Bool) -> LoadResult {

        let name = url.lastPathComponent
        let ext  = url.pathExtension.lowercased()

        // dotfiles: ".zshrc" -> treat the leading-dot name as a candidate
        let isDotfile = name.hasPrefix(".") && !name.dropFirst().contains(".")

        let nameAllowed = allowedFilenames.contains(name)
            || (isDotfile && allowedExtensions.contains(String(name.dropFirst())))
        let extAllowed  = !ext.isEmpty && allowedExtensions.contains(ext)

        // Peek at the bytes once; reused for both sniffing and decoding.
        guard let probe = try? readPrefix(url: url, limit: maxBytes) else {
            return .unreadable("Could not read file.")
        }

        if probe.truncated && probe.fileSize > maxBytes && probe.data.isEmpty {
            return .tooLarge(probe.fileSize)
        }

        let looksTextual = isProbablyText(probe.data)

        let shouldRender: Bool
        if nameAllowed || extAllowed {
            shouldRender = looksTextual            // allowlisted, but still guard against binary
        } else if sniffUnknown {
            shouldRender = looksTextual            // qlstephen-style "just works" path
        } else {
            shouldRender = false
        }

        guard shouldRender else { return .notText }

        guard let decoded = decode(probe.data) else {
            return .unreadable("File is not valid UTF-8 / UTF-16 / Latin-1 text.")
        }

        let body = probe.truncated
            ? decoded + "\n\n… [truncated — file exceeds \(byteString(maxBytes)) preview limit]"
            : decoded

        return .text(body)
    }

    // MARK: - Byte reading

    private struct Probe {
        let data: Data
        let truncated: Bool
        let fileSize: Int
    }

    private static func readPrefix(url: URL, limit: Int) throws -> Probe {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs[.size] as? Int) ?? 0

        let data = try handle.read(upToCount: limit) ?? Data()
        let truncated = fileSize > data.count
        return Probe(data: data, truncated: truncated, fileSize: fileSize)
    }

    // MARK: - Heuristics

    /// Conservative "is this text" sniff. Mirrors the spirit of file(1):
    /// reject NUL bytes outright, reject a high ratio of non-text control
    /// characters, accept anything that decodes cleanly as UTF-8.
    static func isProbablyText(_ data: Data) -> Bool {
        if data.isEmpty { return true }                 // empty file: harmless to show

        if data.contains(0x00) { return false }         // NUL → almost certainly binary

        // UTF-8 BOM or clean UTF-8 decode is a strong positive.
        if String(data: data, encoding: .utf8) != nil { return true }

        // Otherwise count "suspicious" bytes outside the printable/whitespace range.
        var suspicious = 0
        for byte in data {
            let isPrintable = (byte >= 0x20 && byte < 0x7F)
            let isCommonWhitespace = (byte == 0x09 || byte == 0x0A
                                      || byte == 0x0D || byte == 0x0C)
            let isHighLatin = byte >= 0x80   // could be Latin-1 / UTF-8 continuation
            if !(isPrintable || isCommonWhitespace || isHighLatin) {
                suspicious += 1
            }
        }
        let ratio = Double(suspicious) / Double(data.count)
        return ratio < 0.05
    }

    /// Decode with a sensible fallback chain.
    static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8)   { return s }
        if let s = String(data: data, encoding: .utf16)  { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return nil
    }

    // MARK: - Formatting

    private static func byteString(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024.0)
    }
}
