//
//  ClipItemTests.swift
//  ClipBoardUnitTests
//
//  Lenient decoding of history entries and the content-presence rule.
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ClipBoard

@Suite("ClipItem")
struct ClipItemTests {
    @Test("Missing fields decode to safe defaults")
    func lenientDecoding() throws {
        let json = Data(#"[{"text":"hi"}, {"kind":"bogus","isPinned":"yes"}]"#.utf8)
        let items = try JSONDecoder().decode([ClipItem].self, from: json)

        #expect(items.count == 2)
        #expect(items[0].kind == .text)
        #expect(items[0].text == "hi")
        #expect(items[0].isPinned == false)
        #expect(items[0].copiedAt == .distantPast)
        #expect(items[0].contentHash == items[0].id.uuidString)
        #expect(items[1].kind == .text)
        #expect(items[1].hasContent == false)
    }

    @Test("hasContent needs the payload the kind requires")
    func hasContent() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        #expect(ClipItem(id: UUID(), kind: .text, text: "x", copiedAt: date, contentHash: "1").hasContent)
        #expect(!ClipItem(id: UUID(), kind: .text, text: "", copiedAt: date, contentHash: "2").hasContent)
        #expect(ClipItem(id: UUID(), kind: .image, mediaFileName: "a.png", mediaType: PNG, copiedAt: date, contentHash: "3").hasContent)
        #expect(!ClipItem(id: UUID(), kind: .image, copiedAt: date, contentHash: "4").hasContent)
        #expect(!ClipItem(id: UUID(), kind: .video, mediaFileName: "a.mp4", copiedAt: date, contentHash: "4b").hasContent)
        #expect(ClipItem(id: UUID(), kind: .files, filePaths: ["/a"], copiedAt: date, contentHash: "5").hasContent)
        #expect(!ClipItem(id: UUID(), kind: .files, filePaths: [], copiedAt: date, contentHash: "6").hasContent)
    }

    @Test("Content kinds map to item kinds")
    func contentKind() {
        #expect(ClipItem.Kind.video.isMedia && ClipItem.Kind.audio.isMedia && ClipItem.Kind.image.isMedia)
        #expect(!ClipItem.Kind.text.isMedia && !ClipItem.Kind.files.isMedia)
        #expect(ClipContent.text("a", rtf: nil).kind == .text)
        #expect(ClipContent.media(Data(), type: PNG).kind == .image)
        #expect(ClipContent.media(Data(), type: GIF).kind == .image)
        #expect(ClipContent.media(Data(), type: MP4).kind == .video)
        #expect(ClipContent.media(Data(), type: UTType.quickTimeMovie.identifier).kind == .video)
        #expect(ClipContent.media(Data(), type: MP3).kind == .audio)
        #expect(ClipContent.media(Data(), type: "not.a.real.type").kind == .image)
        #expect(ClipContent.files([]).kind == .files)
    }
}
