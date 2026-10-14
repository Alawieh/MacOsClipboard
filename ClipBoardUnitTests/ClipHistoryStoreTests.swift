//
//  ClipHistoryStoreTests.swift
//  ClipBoardUnitTests
//
//  History ordering, de-duplication, the cap, pinning, deletion and the on-disk round trip.
//

import Foundation
import Testing
@testable import ClipBoard

@MainActor
@Suite("ClipHistoryStore")
struct ClipHistoryStoreTests {
    let folder = TemporaryDirectory()
    let clock = TestClock()

    func makeStore(maxUnpinned: Int = 100) -> ClipHistoryStore {
        let clock = clock
        return ClipHistoryStore(directory: folder.url, maxUnpinnedItems: maxUnpinned, now: { clock.now })
    }

    @Test("A new copy goes on top with its source app and time")
    func addInsertsAtTop() {
        let store = makeStore()
        store.add(.text("first", rtf: nil), sourceAppName: "Notes")
        clock.advance(seconds: 5)
        store.add(.text("second", rtf: nil), sourceAppName: "Safari")

        #expect(store.items.map(\.text) == ["second", "first"])
        #expect(store.items[0].sourceAppName == "Safari")
        #expect(store.items[0].copiedAt == clock.now)
    }

    @Test("Copying the same text again moves it to the top instead of duplicating")
    func duplicateMovesToTop() {
        let store = makeStore()
        let original = store.add(.text("hello", rtf: nil), sourceAppName: "Notes")
        store.add(.text("other", rtf: nil), sourceAppName: nil)
        clock.advance(seconds: 60)
        let again = store.add(.text("hello", rtf: nil), sourceAppName: nil)

        #expect(store.items.count == 2)
        #expect(store.items.first?.id == original?.id)
        #expect(again?.copiedAt == clock.now)
        #expect(again?.sourceAppName == "Notes")
    }

    @Test("Same text with and without formatting is one entry")
    func rtfDoesNotSplitEntries() {
        let store = makeStore()
        store.add(.text("hello", rtf: nil), sourceAppName: nil)
        store.add(.text("hello", rtf: SampleData.rtf("hello")), sourceAppName: nil)
        #expect(store.items.count == 1)
    }

    @Test("Past the cap, the oldest unpinned entries are dropped and pinned ones kept")
    func capDropsOldestUnpinned() throws {
        let store = makeStore(maxUnpinned: 2)
        let pinned = try #require(store.add(.text("pinned", rtf: nil), sourceAppName: nil))
        store.togglePin(pinned.id)
        store.add(.text("a", rtf: nil), sourceAppName: nil)
        store.add(.text("b", rtf: nil), sourceAppName: nil)
        store.add(.text("c", rtf: nil), sourceAppName: nil)

        #expect(store.items.map(\.text) == ["c", "b", "pinned"])
    }

    @Test("Unpinning past the cap trims immediately")
    func unpinTrims() throws {
        let store = makeStore(maxUnpinned: 1)
        let old = try #require(store.add(.text("old", rtf: nil), sourceAppName: nil))
        store.togglePin(old.id)
        store.add(.text("new", rtf: nil), sourceAppName: nil)
        store.togglePin(old.id)

        #expect(store.items.map(\.text) == ["new"])
    }

    @Test("An image is saved as a PNG file and read back as the same bytes")
    func imageRoundTrip() throws {
        let store = makeStore()
        let png = SampleData.png()
        let item = try #require(store.add(.media(png, type: PNG), sourceAppName: nil))
        let url = try #require(store.mediaURL(for: item))

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(item.mediaFileName == url.lastPathComponent)
        #expect(url.pathExtension == "png")
        #expect(store.content(of: item) == .media(png, type: PNG))
    }

    @Test("GIFs and videos are stored in their original format, with a matching extension")
    func originalFormats() throws {
        let store = makeStore()
        let gif = try #require(store.add(.media(SampleData.gif(), type: GIF), sourceAppName: nil))
        let movie = try #require(store.add(.media(SampleData.movie(), type: MP4), sourceAppName: nil))

        #expect(gif.kind == .image)
        #expect(movie.kind == .video)
        #expect(store.mediaURL(for: gif)?.pathExtension == "gif")
        #expect(store.mediaURL(for: movie)?.pathExtension == "mp4")
        #expect(store.content(of: gif) == .media(SampleData.gif(), type: GIF))
        #expect(store.content(of: movie) == .media(SampleData.movie(), type: MP4))
    }

    @Test("The same bytes under a different type are different entries")
    func typeIsPartOfIdentity() {
        let store = makeStore()
        store.add(.media(SampleData.movie(), type: MP4), sourceAppName: nil)
        store.add(.media(SampleData.movie(), type: MP3), sourceAppName: nil)
        #expect(store.items.count == 2)
    }

    @Test("Deleting an image entry deletes its file")
    func removeDeletesImageFile() throws {
        let store = makeStore()
        let item = try #require(store.add(.media(SampleData.png(), type: PNG), sourceAppName: nil))
        let url = try #require(store.mediaURL(for: item))
        store.remove(item.id)

        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Images dropped by the cap lose their files too")
    func capDeletesImageFiles() throws {
        let store = makeStore(maxUnpinned: 1)
        let image = try #require(store.add(.media(SampleData.png(), type: PNG), sourceAppName: nil))
        let url = try #require(store.mediaURL(for: image))
        store.add(.text("newer", rtf: nil), sourceAppName: nil)

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Clear All removes unpinned entries only")
    func clearUnpinnedKeepsPinned() throws {
        let store = makeStore()
        let keep = try #require(store.add(.text("keep", rtf: nil), sourceAppName: nil))
        store.togglePin(keep.id)
        store.add(.text("drop", rtf: nil), sourceAppName: nil)
        store.clearUnpinned()

        #expect(store.items.map(\.text) == ["keep"])
        #expect(store.items[0].isPinned)
    }

    @Test("History survives a relaunch: text, RTF, files, images and pins")
    func persistenceRoundTrip() throws {
        let store = makeStore()
        let rtf = SampleData.rtf("bold")
        store.add(.text("bold", rtf: rtf), sourceAppName: "Pages")
        store.add(.files([URL(fileURLWithPath: "/tmp/a.txt")]), sourceAppName: "Finder")
        let image = try #require(store.add(.media(SampleData.png(), type: PNG), sourceAppName: nil))
        store.togglePin(image.id)

        let reloaded = makeStore()
        reloaded.load()

        #expect(reloaded.items == store.items)
        #expect(reloaded.content(of: reloaded.items[2]) == .text("bold", rtf: rtf))
    }

    @Test("Move to top re-stamps the time; unknown ids are ignored")
    func moveToTop() throws {
        let store = makeStore()
        let first = try #require(store.add(.text("first", rtf: nil), sourceAppName: nil))
        store.add(.text("second", rtf: nil), sourceAppName: nil)
        clock.advance(seconds: 10)
        store.moveToTop(first.id)
        store.moveToTop(UUID())

        #expect(store.items.map(\.text) == ["first", "second"])
        #expect(store.items[0].copiedAt == clock.now)
    }

    @Test("A missing history file loads as empty")
    func loadMissingFile() {
        let store = makeStore()
        store.load()
        #expect(store.items.isEmpty)
    }

    @Test("A corrupted history file loads as empty instead of crashing")
    func loadCorruptFile() throws {
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.url.appending(path: HISTORY_FILE_NAME))
        let store = makeStore()
        store.load()
        #expect(store.items.isEmpty)
    }

    @Test("Image entries whose file is gone are dropped on load; stray image files are deleted")
    func loadCleansImages() throws {
        let store = makeStore()
        let image = try #require(store.add(.media(SampleData.png(), type: PNG), sourceAppName: nil))
        store.add(.text("text", rtf: nil), sourceAppName: nil)
        try FileManager.default.removeItem(at: try #require(store.mediaURL(for: image)))
        let stray = folder.url.appending(path: HISTORY_MEDIA_FOLDER_NAME).appending(path: "stray.png")
        try SampleData.png().write(to: stray)

        let reloaded = makeStore()
        reloaded.load()

        #expect(reloaded.items.map(\.text) == ["text"])
        #expect(!FileManager.default.fileExists(atPath: stray.path))
    }

    @Test("content(of:) is nil for entries without a payload")
    func contentMissing() {
        let store = makeStore()
        let emptyText = ClipItem(id: UUID(), kind: .text, copiedAt: clock.now, contentHash: "x")
        let emptyFiles = ClipItem(id: UUID(), kind: .files, filePaths: [], copiedAt: clock.now, contentHash: "y")
        let lostImage = ClipItem(id: UUID(), kind: .image, mediaFileName: "gone.png", mediaType: PNG, copiedAt: clock.now, contentHash: "z")

        #expect(store.content(of: emptyText) == nil)
        #expect(store.content(of: emptyFiles) == nil)
        #expect(store.content(of: lostImage) == nil)
        #expect(store.mediaURL(for: emptyText) == nil)
    }

    @Test("Saving into an unwritable folder keeps history in memory")
    func unwritableFolder() throws {
        let blocker = folder.url.appending(path: "blocker")
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        try Data().write(to: blocker)
        let clock = clock
        let store = ClipHistoryStore(directory: blocker, now: { clock.now })

        store.add(.text("kept", rtf: nil), sourceAppName: nil)
        let image = store.add(.media(SampleData.png(), type: PNG), sourceAppName: nil)

        #expect(store.items.map(\.text) == ["kept"])
        #expect(image == nil)
    }

    @Test("Hashes differ by kind and content, and are stable")
    func hashing() {
        let text = ClipHistoryStore.contentHash(of: .text("a", rtf: nil))
        #expect(text == ClipHistoryStore.contentHash(of: .text("a", rtf: nil)))
        #expect(text != ClipHistoryStore.contentHash(of: .text("b", rtf: nil)))
        #expect(text != ClipHistoryStore.contentHash(of: .files([URL(fileURLWithPath: "a")])))
        #expect(text.count == 64)
    }

    @Test("Default folder is Application Support/ClipBoard")
    func defaultDirectory() {
        #expect(ClipHistoryStore.defaultDirectory.lastPathComponent == HISTORY_FOLDER_NAME)
    }
}
