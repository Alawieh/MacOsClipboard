//
//  ClipboardPanelViewModel.swift
//  ClipBoard
//
//  State and intents for the ⌘⇧V history panel: search, selection, paste, pin, delete.
//

import AppKit
import Observation
import UniformTypeIdentifiers

/// Drives the history panel. Lists pinned entries first, then the rest, both newest first, filtered
/// by `query`. Keeps exactly one entry selected while any are visible.
@MainActor
@Observable
final class ClipboardPanelViewModel {
    /// Search text. Changing it selects the first match.
    var query = "" {
        didSet { selectFirst() }
    }
    private(set) var selectedID: UUID?
    /// Bumped on every show so the view re-focuses the search field.
    private(set) var focusRequest = 0
    /// Snapshot of the Accessibility permission, refreshed on every show.
    private(set) var isAutoPasteAvailable = true
    /// Previews loaded so far, by entry id. Filled lazily by `loadThumbnail(for:)`.
    private(set) var thumbnails: [UUID: NSImage] = [:]

    /// Hides the panel. Set by the panel controller.
    @ObservationIgnored var onDismiss: @MainActor () -> Void = {}

    @ObservationIgnored private let store: ClipHistoryStore
    @ObservationIgnored private let paster: ClipPasting
    @ObservationIgnored private let permissions: AccessibilityPermissionChecking
    @ObservationIgnored private let thumbnailer: ThumbnailProviding
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let relativeFormatter = RelativeDateTimeFormatter()

    init(
        store: ClipHistoryStore,
        paster: ClipPasting,
        permissions: AccessibilityPermissionChecking,
        thumbnailer: ThumbnailProviding,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.store = store
        self.paster = paster
        self.permissions = permissions
        self.thumbnailer = thumbnailer
        self.now = now
        relativeFormatter.unitsStyle = .short
    }

    // MARK: - Derived state

    /// Pinned matches first, then unpinned matches; each group newest first.
    var visibleItems: [ClipItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = needle.isEmpty ? store.items : store.items.filter { matches($0, needle) }
        return matching.filter(\.isPinned) + matching.filter { !$0.isPinned }
    }

    var hasUnpinnedItems: Bool {
        store.items.contains { !$0.isPinned }
    }

    /// Text for the empty list, or nil when there is something to show.
    var emptyStateMessage: String? {
        guard visibleItems.isEmpty else { return nil }
        return store.items.isEmpty
            ? String(localized: "Nothing copied yet. Copy something and it shows up here.")
            : String(localized: "No matches")
    }

    /// The ⌘-number shown on a row at `index` in `visibleItems`, or nil past the ninth row.
    static func shortcutNumber(at index: Int) -> Int? {
        index < PANEL_SHORTCUT_COUNT ? index + 1 : nil
    }

    /// One-line preview: the text itself, the file names, or the media format ("GIF image",
    /// "MPEG-4 movie"), falling back to Image / Video / Audio.
    func title(for item: ClipItem) -> String {
        switch item.kind {
        case .text:
            return (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .image, .video, .audio:
            if let description = item.mediaType.flatMap({ UTType($0) })?.localizedDescription, !description.isEmpty {
                return description.prefix(1).uppercased() + description.dropFirst()
            }
            switch item.kind {
            case .video: return String(localized: "Video")
            case .audio: return String(localized: "Audio")
            default: return String(localized: "Image")
            }
        case .files:
            // String-only: URL(fileURLWithPath:) would stat the file (see loadThumbnail).
            let names = (item.filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            return names.joined(separator: ", ")
        }
    }

    /// "Safari · 5 min. ago", or just the time when the source app is unknown.
    func subtitle(for item: ClipItem) -> String {
        let age = relativeFormatter.localizedString(for: item.copiedAt, relativeTo: now())
        guard let app = item.sourceAppName, !app.isEmpty else { return age }
        return "\(app) · \(age)"
    }

    /// The file a real preview is made from: the media copy in the app's own storage. Nil for text and
    /// for Finder files, whose originals are never opened.
    func thumbnailURL(for item: ClipItem) -> URL? {
        item.kind.isMedia ? store.mediaURL(for: item) : nil
    }

    /// Loads the entry's preview into `thumbnails` once: a Quick Look thumbnail for media, the
    /// file-type icon (from the extension alone) for Finder files. Never opens, reads or stats the
    /// user's own files, so it can't trigger macOS's Desktop/Documents/Downloads access prompts.
    /// Text entries and failures leave no entry.
    func loadThumbnail(for item: ClipItem) async {
        guard thumbnails[item.id] == nil else { return }
        if item.kind == .files {
            guard let firstPath = item.filePaths?.first else { return }
            thumbnails[item.id] = thumbnailer.icon(forPathExtension: (firstPath as NSString).pathExtension)
            return
        }
        guard let url = thumbnailURL(for: item) else { return }
        guard let image = await thumbnailer.thumbnail(for: url, side: HISTORY_THUMBNAIL_SIDE) else { return }
        thumbnails[item.id] = image
    }

    // MARK: - Intents

    /// Resets search, selects the newest entry, refreshes the permission snapshot and asks for focus.
    func prepareForShow() {
        query = ""
        selectFirst()
        isAutoPasteAvailable = permissions.isTrusted
        focusRequest += 1
    }

    /// Moves the selection up (negative) or down (positive), stopping at the ends.
    func moveSelection(by offset: Int) {
        let items = visibleItems
        guard !items.isEmpty else {
            selectedID = nil
            return
        }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + offset, 0), items.count - 1)
        selectedID = items[next].id
    }

    func select(_ item: ClipItem) {
        selectedID = item.id
    }

    func pasteSelected() {
        guard let item = selectedItem else { return }
        paste(item)
    }

    /// Pastes the row showing `number` (1-based, as in ⌘1). Out-of-range numbers do nothing.
    func paste(atShortcutNumber number: Int) {
        let items = visibleItems
        guard number >= 1, number <= min(items.count, PANEL_SHORTCUT_COUNT) else { return }
        paste(items[number - 1])
    }

    /// Moves the entry to the top of history, hides the panel and pastes it into the frontmost app.
    /// Entries whose content is gone (deleted media file) are removed instead.
    func paste(_ item: ClipItem) {
        guard let content = store.content(of: item) else {
            delete(item)
            return
        }
        store.moveToTop(item.id)
        dismiss()
        paster.paste(content)
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        togglePin(item)
    }

    /// Pins or unpins; the entry stays selected as it moves between groups.
    func togglePin(_ item: ClipItem) {
        store.togglePin(item.id)
        selectedID = item.id
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        delete(item)
    }

    /// Deletes the entry. If it was selected, the entry that takes its place (or the new last one) is selected.
    func delete(_ item: ClipItem) {
        let before = visibleItems
        let index = before.firstIndex { $0.id == item.id }
        let wasSelected = item.id == selectedID
        store.remove(item.id)
        thumbnails[item.id] = nil
        guard wasSelected || selectedItem == nil else { return }
        let after = visibleItems
        guard !after.isEmpty else {
            selectedID = nil
            return
        }
        selectedID = after[min(index ?? 0, after.count - 1)].id
    }

    /// Deletes every unpinned entry and selects the first remaining one.
    func clearUnpinned() {
        store.clearUnpinned()
        let remaining = Set(store.items.map(\.id))
        thumbnails = thumbnails.filter { remaining.contains($0.key) }
        selectFirst()
    }

    /// Asks for the system Accessibility prompt so auto-paste can work.
    func enableAutoPaste() {
        permissions.requestTrust()
        isAutoPasteAvailable = permissions.isTrusted
    }

    func dismiss() {
        onDismiss()
    }

    // MARK: - Private

    private var selectedItem: ClipItem? {
        visibleItems.first { $0.id == selectedID }
    }

    private func selectFirst() {
        selectedID = visibleItems.first?.id
    }

    private func matches(_ item: ClipItem, _ needle: String) -> Bool {
        title(for: item).localizedStandardContains(needle)
            || (item.sourceAppName ?? "").localizedStandardContains(needle)
    }
}
