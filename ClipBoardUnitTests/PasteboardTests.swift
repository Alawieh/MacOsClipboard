//
//  PasteboardTests.swift
//  ClipBoardUnitTests
//
//  PasteboardReader, PasteboardWriter and PasteboardMonitor against private, uniquely named pasteboards.
//

import AppKit
import Testing
import UniformTypeIdentifiers
@testable import ClipBoard

@MainActor
@Suite("Pasteboard")
struct PasteboardTests {
    let pasteboard = NSPasteboard.withUniqueName()
    let reader = PasteboardReader()

    @Test("Plain text is read with its RTF when present")
    func readsText() {
        let rtf = SampleData.rtf("hello")
        pasteboard.clearContents()
        pasteboard.setData(rtf, forType: .rtf)
        pasteboard.setString("hello", forType: .string)
        #expect(reader.read(pasteboard) == .text("hello", rtf: rtf))
    }

    @Test("Whitespace-only and empty pasteboards are not recorded")
    func ignoresBlank() {
        pasteboard.clearContents()
        #expect(reader.read(pasteboard) == nil)
        pasteboard.setString("  \n\t ", forType: .string)
        #expect(reader.read(pasteboard) == nil)
    }

    @Test("Password-manager copies (concealed type) are not recorded")
    func ignoresConcealed() {
        pasteboard.clearContents()
        pasteboard.setString("hunter2", forType: .string)
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        #expect(reader.read(pasteboard) == nil)
    }

    @Test("Text over the length limit is not recorded")
    func ignoresHugeText() {
        var small = reader
        small.maxTextLength = 3
        pasteboard.clearContents()
        pasteboard.setString("abcd", forType: .string)
        #expect(small.read(pasteboard) == nil)
    }

    @Test("Finder file copies are read as files, not as text or icon")
    func readsFiles() {
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        #expect(reader.read(pasteboard) == .files([url]))
    }

    @Test("A PNG-only copy is read as an image")
    func readsPNG() {
        let png = SampleData.png()
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        #expect(reader.read(pasteboard) == .media(png, type: PNG))
    }

    @Test("A TIFF-only copy is converted to PNG")
    func readsTIFF() throws {
        let tiff = try #require(NSBitmapImageRep(data: SampleData.png())?.tiffRepresentation)
        pasteboard.clearContents()
        pasteboard.setData(tiff, forType: .tiff)
        guard case .media(let png, let type) = reader.read(pasteboard) else {
            Issue.record("expected an image")
            return
        }
        #expect(type == PNG)
        #expect(NSBitmapImageRep(data: png) != nil)
    }

    @Test("A GIF is kept as GIF (so it stays animated), even when TIFF and PNG are offered first")
    func keepsGIF() {
        let gif = SampleData.gif()
        pasteboard.clearContents()
        pasteboard.setData(SampleData.png(), forType: .tiff)
        pasteboard.setData(SampleData.png(), forType: .png)
        pasteboard.setData(gif, forType: NSPasteboard.PasteboardType(GIF))
        #expect(reader.read(pasteboard) == .media(gif, type: GIF))
    }

    @Test("A JPEG offered alongside TIFF is kept as JPEG")
    func prefersOriginalOverTIFF() throws {
        let jpeg = try #require(NSBitmapImageRep(data: SampleData.png())?.representation(using: .jpeg, properties: [:]))
        let jpegType = UTType.jpeg.identifier
        pasteboard.clearContents()
        pasteboard.setData(SampleData.png(), forType: .tiff)
        pasteboard.setData(jpeg, forType: NSPasteboard.PasteboardType(jpegType))
        #expect(reader.read(pasteboard) == .media(jpeg, type: jpegType))
    }

    @Test("Video and audio data are recorded with their type", arguments: [MP4, MP3])
    func readsVideoAndAudio(type: String) {
        pasteboard.clearContents()
        pasteboard.setData(SampleData.movie(), forType: NSPasteboard.PasteboardType(type))
        #expect(reader.read(pasteboard) == .media(SampleData.movie(), type: type))
    }

    @Test("Non-media data (e.g. PDF) is not recorded")
    func ignoresNonMedia() {
        pasteboard.clearContents()
        pasteboard.setData(Data("%PDF".utf8), forType: .pdf)
        #expect(reader.read(pasteboard) == nil)
    }

    @Test("A broken TIFF is not recorded")
    func ignoresBrokenTIFF() {
        pasteboard.clearContents()
        pasteboard.setData(Data("nope".utf8), forType: .tiff)
        #expect(reader.read(pasteboard) == nil)
    }

    @Test("Media over the size limit is not recorded")
    func ignoresHugeImage() {
        var small = reader
        small.maxMediaBytes = 1
        pasteboard.clearContents()
        pasteboard.setData(SampleData.png(), forType: .png)
        #expect(small.read(pasteboard) == nil)
    }

    @Test("Text plus a picture (e.g. spreadsheet cells) is read as text")
    func prefersTextOverImage() {
        pasteboard.clearContents()
        pasteboard.setString("A1", forType: .string)
        pasteboard.setData(SampleData.png(), forType: .png)
        #expect(reader.read(pasteboard) == .text("A1", rtf: nil))
    }

    @Test("Writer output reads back as the same content", arguments: [
        ClipContent.text("plain", rtf: nil),
        ClipContent.text("rich", rtf: SampleData.rtf("rich")),
        ClipContent.media(SampleData.png(), type: PNG),
        ClipContent.media(SampleData.gif(), type: GIF),
        ClipContent.media(SampleData.movie(), type: MP4),
        ClipContent.files([URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]),
    ])
    func writerRoundTrip(content: ClipContent) {
        PasteboardWriter().write(content, to: pasteboard)
        #expect(reader.read(pasteboard) == content)
    }

    @Test("Written images also carry TIFF for older apps")
    func writerAddsTIFF() {
        PasteboardWriter().write(.media(SampleData.png(), type: PNG), to: pasteboard)
        #expect(pasteboard.data(forType: .tiff) != nil)

        PasteboardWriter().write(.media(SampleData.movie(), type: MP4), to: pasteboard)
        #expect(pasteboard.data(forType: .tiff) == nil)
    }

    // MARK: - Monitor

    final class Captures {
        var items: [(ClipContent, String?)] = []
    }

    func makeMonitor(_ captures: Captures) -> PasteboardMonitor {
        PasteboardMonitor(pasteboard: pasteboard, frontmostAppName: { "Notes" }) { content, app in
            captures.items.append((content, app))
        }
    }

    @Test("Monitor reports each new copy once, with the source app")
    func monitorReportsOnce() {
        let captures = Captures()
        let monitor = makeMonitor(captures)
        monitor.poll()
        #expect(captures.items.isEmpty)

        pasteboard.clearContents()
        pasteboard.setString("copied", forType: .string)
        monitor.poll()
        monitor.poll()

        #expect(captures.items.count == 1)
        #expect(captures.items.first?.0 == .text("copied", rtf: nil))
        #expect(captures.items.first?.1 == "Notes")
    }

    @Test("Monitor ignores what was on the pasteboard before it started")
    func monitorIgnoresExistingContents() {
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        let captures = Captures()
        let monitor = makeMonitor(captures)
        monitor.start()
        monitor.poll()
        monitor.stop()
        #expect(captures.items.isEmpty)
    }

    @Test("Monitor skips the app's own writes")
    func monitorSkipsOwnWrites() {
        let captures = Captures()
        let monitor = makeMonitor(captures)
        PasteboardWriter().write(.text("ours", rtf: nil), to: pasteboard)
        monitor.markOwnWrite()
        monitor.poll()
        #expect(captures.items.isEmpty)
    }

    @Test("Monitor skips copies the reader rejects")
    func monitorSkipsRejected() {
        let captures = Captures()
        let monitor = makeMonitor(captures)
        pasteboard.clearContents()
        pasteboard.setString("   ", forType: .string)
        monitor.poll()
        #expect(captures.items.isEmpty)
    }
}
