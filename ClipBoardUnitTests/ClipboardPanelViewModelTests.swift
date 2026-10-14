//
//  ClipboardPanelViewModelTests.swift
//  ClipBoardUnitTests
//
//  Panel intents: search, ordering, selection, paste, pin, delete, clear, empty states.
//

import Foundation
import Testing
@testable import ClipBoard

@MainActor
@Suite("ClipboardPanelViewModel")
struct ClipboardPanelViewModelTests {
    let folder = TemporaryDirectory()
    let clock = TestClock()
    let paster = FakePaster()
    let permissions = FakePermissions()
    let thumbnails = FakeThumbnails()
    let store: ClipHistoryStore
    let viewModel: ClipboardPanelViewModel

    init() {
        let clock = clock
        store = ClipHistoryStore(directory: folder.url, now: { clock.now })
        viewModel = ClipboardPanelViewModel(
            store: store,
            paster: paster,
            permissions: permissions,
            thumbnailer: thumbnails,
            now: { clock.now }
        )
    }

    /// Adds texts oldest first, so the last one ends up on top.
    @discardableResult
    func add(_ texts: String...) -> [ClipItem] {
        texts.compactMap { text in
            clock.advance(seconds: 1)
            return store.add(.text(text, rtf: nil), sourceAppName: "Notes")
        }
    }

    @Test("Opening resets search, selects the newest entry and requests focus")
    func prepareForShow() {
        add("old", "new")
        viewModel.query = "old"
        let focus = viewModel.focusRequest
        viewModel.prepareForShow()

        #expect(viewModel.query.isEmpty)
        #expect(viewModel.selectedID == store.items.first?.id)
        #expect(viewModel.focusRequest == focus + 1)
    }

    @Test("Pinned entries are listed first")
    func pinnedFirst() {
        let items = add("a", "b", "c")
        viewModel.togglePin(items[0])
        #expect(viewModel.visibleItems.map(\.text) == ["a", "c", "b"])
    }

    @Test("Search matches text and source app, case-insensitively, and selects the first match")
    func search() {
        add("Hello World", "goodbye")
        viewModel.query = "hello"
        #expect(viewModel.visibleItems.map(\.text) == ["Hello World"])
        #expect(viewModel.selectedID == viewModel.visibleItems.first?.id)

        viewModel.query = "notes"
        #expect(viewModel.visibleItems.count == 2)
    }

    @Test("Selection moves with arrows and stops at both ends")
    func moveSelection() {
        add("a", "b", "c")
        viewModel.prepareForShow()
        viewModel.moveSelection(by: -1)
        #expect(viewModel.selectedID == viewModel.visibleItems[0].id)
        viewModel.moveSelection(by: 1)
        viewModel.moveSelection(by: 5)
        #expect(viewModel.selectedID == viewModel.visibleItems[2].id)
    }

    @Test("Moving the selection in an empty list clears it")
    func moveSelectionEmpty() {
        viewModel.moveSelection(by: 1)
        #expect(viewModel.selectedID == nil)
    }

    @Test("Return pastes the selected entry, moves it to the top and closes the panel")
    func pasteSelected() {
        var dismissals = 0
        viewModel.onDismiss = { dismissals += 1 }
        add("older", "newer")
        viewModel.prepareForShow()
        viewModel.moveSelection(by: 1)
        viewModel.pasteSelected()

        #expect(paster.pasted == [.text("older", rtf: nil)])
        #expect(store.items.first?.text == "older")
        #expect(dismissals == 1)
    }

    @Test("Return with nothing selected does nothing")
    func pasteSelectedEmpty() {
        viewModel.pasteSelected()
        #expect(paster.pasted.isEmpty)
    }

    @Test("⌘number pastes that row; numbers outside 1…9 or past the list do nothing")
    func pasteShortcut() {
        add("a", "b", "c")
        viewModel.paste(atShortcutNumber: 2)
        #expect(paster.pasted == [.text("b", rtf: nil)])

        viewModel.paste(atShortcutNumber: 0)
        viewModel.paste(atShortcutNumber: 4)
        viewModel.paste(atShortcutNumber: 10)
        #expect(paster.pasted.count == 1)
    }

    @Test("Rows 1–9 show a ⌘ number, later rows none")
    func shortcutNumbers() {
        #expect(ClipboardPanelViewModel.shortcutNumber(at: 0) == 1)
        #expect(ClipboardPanelViewModel.shortcutNumber(at: 8) == 9)
        #expect(ClipboardPanelViewModel.shortcutNumber(at: 9) == nil)
    }

    @Test("Pasting an entry whose image file is gone removes it instead")
    func pasteBrokenImage() throws {
        let image = try #require(store.add(.media(SampleData.png(), type: PNG), sourceAppName: nil))
        try FileManager.default.removeItem(at: try #require(store.mediaURL(for: image)))
        viewModel.paste(image)

        #expect(paster.pasted.isEmpty)
        #expect(store.items.isEmpty)
    }

    @Test("⌘P pins the selected entry and keeps it selected")
    func togglePinSelected() {
        add("a", "b")
        viewModel.prepareForShow()
        viewModel.moveSelection(by: 1)
        let selected = viewModel.selectedID
        viewModel.togglePinSelected()

        #expect(viewModel.visibleItems.first?.id == selected)
        #expect(viewModel.visibleItems.first?.isPinned == true)
        #expect(viewModel.selectedID == selected)
    }

    @Test("Deleting the selected entry selects the one that takes its place")
    func deleteSelected() {
        add("a", "b", "c")
        viewModel.prepareForShow()
        viewModel.moveSelection(by: 1)
        viewModel.deleteSelected()

        #expect(viewModel.visibleItems.map(\.text) == ["c", "a"])
        #expect(viewModel.selectedID == viewModel.visibleItems[1].id)
    }

    @Test("Deleting the last remaining entry clears the selection")
    func deleteLast() {
        add("only")
        viewModel.prepareForShow()
        viewModel.deleteSelected()
        #expect(viewModel.selectedID == nil)
        viewModel.deleteSelected()
        viewModel.togglePinSelected()
        #expect(store.items.isEmpty)
    }

    @Test("Deleting a row that is not selected keeps the selection")
    func deleteOther() {
        let items = add("a", "b")
        viewModel.prepareForShow()
        let selected = viewModel.selectedID
        viewModel.delete(items[0])
        #expect(viewModel.selectedID == selected)
    }

    @Test("Clear All keeps pinned entries and selects the first remaining")
    func clearUnpinned() {
        let items = add("pin me", "drop")
        viewModel.togglePin(items[0])
        #expect(viewModel.hasUnpinnedItems)
        viewModel.clearUnpinned()

        #expect(viewModel.visibleItems.map(\.text) == ["pin me"])
        #expect(viewModel.selectedID == items[0].id)
        #expect(!viewModel.hasUnpinnedItems)
    }

    @Test("Empty states: nothing copied vs. no matches")
    func emptyStates() {
        #expect(viewModel.emptyStateMessage == String(localized: "Nothing copied yet. Copy something and it shows up here."))
        add("something")
        #expect(viewModel.emptyStateMessage == nil)
        viewModel.query = "zzz"
        #expect(viewModel.emptyStateMessage == String(localized: "No matches"))
    }

    @Test("Row titles: trimmed text, file names, or the media format")
    func titles() throws {
        let text = try #require(store.add(.text("  spaced \n", rtf: nil), sourceAppName: nil))
        let files = try #require(store.add(.files([URL(fileURLWithPath: "/a/one.txt"), URL(fileURLWithPath: "/b/two.pdf")]), sourceAppName: nil))
        let image = try #require(store.add(.media(SampleData.png(), type: PNG), sourceAppName: nil))

        #expect(viewModel.title(for: text) == "spaced")
        #expect(viewModel.title(for: files) == "one.txt, two.pdf")
        let gif = try #require(store.add(.media(SampleData.gif(), type: GIF), sourceAppName: nil))
        let movie = try #require(store.add(.media(SampleData.movie(), type: MP4), sourceAppName: nil))
        let unknownImage = ClipItem(id: UUID(), kind: .image, mediaFileName: "x", copiedAt: clock.now, contentHash: "1")
        let unknownVideo = ClipItem(id: UUID(), kind: .video, mediaFileName: "x", copiedAt: clock.now, contentHash: "2")
        let unknownAudio = ClipItem(id: UUID(), kind: .audio, mediaFileName: "x", copiedAt: clock.now, contentHash: "3")

        #expect(viewModel.title(for: image).localizedStandardContains("PNG"))
        #expect(viewModel.title(for: gif).localizedStandardContains("GIF"))
        #expect(viewModel.title(for: movie).localizedStandardContains("MPEG-4"))
        #expect(viewModel.title(for: unknownImage) == String(localized: "Image"))
        #expect(viewModel.title(for: unknownVideo) == String(localized: "Video"))
        #expect(viewModel.title(for: unknownAudio) == String(localized: "Audio"))
    }

    @Test("Subtitles show source app and age; age alone when the app is unknown")
    func subtitles() throws {
        let withApp = try #require(store.add(.text("a", rtf: nil), sourceAppName: "Safari"))
        let withoutApp = try #require(store.add(.text("b", rtf: nil), sourceAppName: nil))
        clock.advance(seconds: 300)

        #expect(viewModel.subtitle(for: withApp).hasPrefix("Safari · "))
        #expect(!viewModel.subtitle(for: withoutApp).contains("·"))
    }

    @Test("Media rows get a Quick Look preview of the stored copy, loaded once; text rows none")
    func loadsThumbnails() async throws {
        let movie = try #require(store.add(.media(SampleData.movie(), type: MP4), sourceAppName: nil))
        let text = try #require(store.add(.text("t", rtf: nil), sourceAppName: nil))

        await viewModel.loadThumbnail(for: movie)
        await viewModel.loadThumbnail(for: movie)
        await viewModel.loadThumbnail(for: text)

        #expect(thumbnails.requests == [store.mediaURL(for: movie)])
        #expect(viewModel.thumbnails[movie.id] === thumbnails.image)
        #expect(viewModel.thumbnails[text.id] == nil)
        #expect(viewModel.thumbnailURL(for: text) == nil)
    }

    @Test("Finder files are never opened (no folder-access prompts): they get a type icon by extension")
    func finderFilesAreNeverRead() async throws {
        let video = try #require(store.add(.files([URL(fileURLWithPath: "/Users/me/Desktop/clip.mov")]), sourceAppName: "Finder"))
        let folder = try #require(store.add(.files([URL(fileURLWithPath: "/Users/me/Documents/Taxes")]), sourceAppName: "Finder"))
        let empty = ClipItem(id: UUID(), kind: .files, filePaths: [], copiedAt: clock.now, contentHash: "e")

        await viewModel.loadThumbnail(for: video)
        await viewModel.loadThumbnail(for: folder)
        await viewModel.loadThumbnail(for: empty)

        #expect(thumbnails.requests.isEmpty)
        #expect(viewModel.thumbnailURL(for: video) == nil)
        #expect(thumbnails.iconExtensions == ["mov", ""])
        #expect(viewModel.thumbnails[video.id] === thumbnails.icon)
        #expect(viewModel.thumbnails[empty.id] == nil)
    }

    @Test("A failed preview leaves the row on its icon")
    func thumbnailFailure() async throws {
        thumbnails.fails = true
        let image = try #require(store.add(.media(SampleData.png(), type: PNG), sourceAppName: nil))
        await viewModel.loadThumbnail(for: image)
        #expect(viewModel.thumbnails.isEmpty)
    }

    @Test("Deleted and cleared entries drop their previews")
    func thumbnailsPruned() async throws {
        let pinned = try #require(store.add(.media(SampleData.png(), type: PNG), sourceAppName: nil))
        let loose = try #require(store.add(.media(SampleData.gif(), type: GIF), sourceAppName: nil))
        let other = try #require(store.add(.media(SampleData.movie(), type: MP4), sourceAppName: nil))
        store.togglePin(pinned.id)
        for item in [pinned, loose, other] {
            await viewModel.loadThumbnail(for: item)
        }

        viewModel.delete(other)
        #expect(viewModel.thumbnails[other.id] == nil)
        viewModel.clearUnpinned()
        #expect(Array(viewModel.thumbnails.keys) == [pinned.id])
    }

    @Test("Auto-paste notice follows the permission; Enable asks for it")
    func autoPaste() {
        permissions.isTrusted = false
        viewModel.prepareForShow()
        #expect(!viewModel.isAutoPasteAvailable)

        permissions.grantOnRequest = true
        viewModel.enableAutoPaste()
        #expect(permissions.requestCount == 1)
        #expect(viewModel.isAutoPasteAvailable)
    }

    @Test("Esc dismisses through the controller's hook")
    func dismiss() {
        var dismissals = 0
        viewModel.onDismiss = { dismissals += 1 }
        viewModel.dismiss()
        #expect(dismissals == 1)
    }
}
