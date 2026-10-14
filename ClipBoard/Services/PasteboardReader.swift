//
//  PasteboardReader.swift
//  ClipBoard
//
//  Turns whatever is on a pasteboard into ClipContent, or decides it should not be recorded.
//

import AppKit
import UniformTypeIdentifiers

/// Reads one copy off a pasteboard. Precedence: files, then text, then media (image, video, audio),
/// so a Finder copy is recorded as files (not the icon image) and a spreadsheet copy as text (not
/// its picture).
struct PasteboardReader {
    var ignoredTypes: Set<String> = PASTEBOARD_IGNORED_TYPES
    var maxTextLength = HISTORY_MAX_TEXT_LENGTH
    var maxMediaBytes = HISTORY_MAX_MEDIA_BYTES

    /// - Returns: the content, or nil when the pasteboard is empty, whitespace-only, marked
    ///   concealed/transient (password managers), or over the size limits.
    func read(_ pasteboard: NSPasteboard) -> ClipContent? {
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard !types.isEmpty, types.isDisjoint(with: ignoredTypes) else { return nil }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return .files(urls)
        }

        if let text = pasteboard.string(forType: .string) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= maxTextLength else { return nil }
            return .text(text, rtf: pasteboard.data(forType: .rtf))
        }

        if let media = media(from: pasteboard) {
            guard case .media(let data, _) = media, data.count <= maxMediaBytes else { return nil }
            return media
        }
        return nil
    }

    /// Picks the richest media flavour the source offered, keeping its original format:
    /// GIF first (keeps animation), then the source's first non-TIFF image/video/audio type.
    /// TIFF is only used when nothing else is offered, and is converted to PNG (TIFF is uncompressed).
    private func media(from pasteboard: NSPasteboard) -> ClipContent? {
        let candidates = (pasteboard.types ?? []).filter { type in
            guard let utType = UTType(type.rawValue) else { return false }
            return utType.conforms(to: .image) || utType.conforms(to: .audiovisualContent)
        }
        guard let chosen = candidates.first(where: { $0.rawValue == UTType.gif.identifier })
                ?? candidates.first(where: { $0 != .tiff })
                ?? candidates.first,
              let data = pasteboard.data(forType: chosen), !data.isEmpty else { return nil }

        guard chosen == .tiff else { return .media(data, type: chosen.rawValue) }
        guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return nil }
        return .media(png, type: UTType.png.identifier)
    }
}
