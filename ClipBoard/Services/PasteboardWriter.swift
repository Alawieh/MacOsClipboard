//
//  PasteboardWriter.swift
//  ClipBoard
//
//  Puts a ClipContent back on a pasteboard in the flavours other apps expect.
//

import AppKit
import UniformTypeIdentifiers

/// Writes content to a pasteboard, replacing what was there.
struct PasteboardWriter {
    /// Text goes out as plain string plus RTF when known; media in its original format, and images
    /// additionally as TIFF (older apps only read TIFF); files as file URLs, so pasting in Finder,
    /// Mail or Messages attaches the actual photos and videos.
    func write(_ content: ClipContent, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        switch content {
        case .text(let text, let rtf):
            if let rtf { pasteboard.setData(rtf, forType: .rtf) }
            pasteboard.setString(text, forType: .string)
        case .media(let data, let type):
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
            if ClipItem.Kind.forMedia(type: type) == .image,
               type != UTType.tiff.identifier,
               let tiff = NSBitmapImageRep(data: data)?.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        case .files(let urls):
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        }
    }
}
