//
//  ThumbnailService.swift
//  ClipBoard
//
//  Previews for history rows: Quick Look thumbnails for stored media, type icons for Finder files.
//

import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Produces small preview images for history rows.
@MainActor
protocol ThumbnailProviding: AnyObject {
    /// - Returns: a thumbnail at most `side` points square, or nil if none can be made.
    func thumbnail(for url: URL, side: CGFloat) async -> NSImage?
    /// The generic icon for a file type, from its extension alone (empty means a folder).
    func icon(forPathExtension pathExtension: String) -> NSImage
}

/// Thin wrapper over QLThumbnailGenerator and NSWorkspace icons. `thumbnail(for:side:)` reads the
/// file, so it is only used on files in the app's own storage; `icon(forPathExtension:)` touches
/// no file at all.
@MainActor
final class ThumbnailService: ThumbnailProviding {
    func thumbnail(for url: URL, side: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }

    func icon(forPathExtension pathExtension: String) -> NSImage {
        let type = pathExtension.isEmpty ? UTType.folder : (UTType(filenameExtension: pathExtension) ?? .data)
        return NSWorkspace.shared.icon(for: type)
    }
}
