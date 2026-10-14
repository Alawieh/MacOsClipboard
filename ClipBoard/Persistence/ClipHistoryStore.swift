//
//  ClipHistoryStore.swift
//  ClipBoard
//
//  Owns the clipboard history: ordering, de-duplication, the size cap, and the files on disk.
//

import CryptoKit
import Foundation
import Observation
import OSLog
import UniformTypeIdentifiers

/// The clipboard history, newest first, persisted as `history.json` plus one file per image, video
/// or audio clip (original format) in `media/` inside `directory`. Every mutation saves immediately. Only value types leave the store.
@MainActor
@Observable
final class ClipHistoryStore {
    /// Newest first. Pinned items keep their place by recency; views decide how to group them.
    private(set) var items: [ClipItem] = []

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let maxUnpinnedItems: Int
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let makeID: @MainActor () -> UUID
    @ObservationIgnored private let fileManager = FileManager.default

    /// `~/Library/Application Support/ClipBoard`.
    nonisolated static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: HISTORY_FOLDER_NAME, directoryHint: .isDirectory)
    }

    init(
        directory: URL = ClipHistoryStore.defaultDirectory,
        maxUnpinnedItems: Int = HISTORY_MAX_UNPINNED_ITEMS,
        now: @escaping @MainActor () -> Date = Date.init,
        makeID: @escaping @MainActor () -> UUID = UUID.init
    ) {
        self.directory = directory
        self.maxUnpinnedItems = maxUnpinnedItems
        self.now = now
        self.makeID = makeID
    }

    private var historyFileURL: URL { directory.appending(path: HISTORY_FILE_NAME) }
    private var mediaFolderURL: URL { directory.appending(path: HISTORY_MEDIA_FOLDER_NAME, directoryHint: .isDirectory) }

    // MARK: - Loading

    /// Replaces `items` with what is on disk. A missing or unreadable file yields an empty history
    /// (never a crash). Entries without content, or media whose file is gone, are dropped, and media
    /// files no entry references are deleted.
    func load() {
        items = []
        guard let data = try? Data(contentsOf: historyFileURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([ClipItem].self, from: data)
            items = decoded.filter { $0.hasContent && (!$0.kind.isMedia || mediaFileExists(for: $0)) }
        } catch {
            Log.history.error("History file unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
        }
        removeOrphanMediaFiles()
    }

    // MARK: - Mutations

    /// Records a copy. If the same content is already in history, that entry moves to the top
    /// (keeping its pin) instead of being duplicated. Unpinned entries past the cap are dropped,
    /// oldest first, along with their media files.
    /// - Returns: the entry now at the top, or nil if a media file could not be written.
    @discardableResult
    func add(_ content: ClipContent, sourceAppName: String?) -> ClipItem? {
        let hash = Self.contentHash(of: content)
        if let index = items.firstIndex(where: { $0.contentHash == hash }) {
            var existing = items.remove(at: index)
            existing.copiedAt = now()
            existing.sourceAppName = sourceAppName ?? existing.sourceAppName
            items.insert(existing, at: 0)
            save()
            return existing
        }

        var item = ClipItem(id: makeID(), kind: content.kind, copiedAt: now(), contentHash: hash, sourceAppName: sourceAppName)
        switch content {
        case .text(let text, let rtf):
            item.text = text
            item.rtfData = rtf
        case .media(let data, let type):
            let fileExtension = UTType(type)?.preferredFilenameExtension ?? "data"
            let fileName = "\(item.id.uuidString).\(fileExtension)"
            do {
                try fileManager.createDirectory(at: mediaFolderURL, withIntermediateDirectories: true)
                try data.write(to: mediaFolderURL.appending(path: fileName), options: .atomic)
            } catch {
                Log.history.error("Could not save media: \(error.localizedDescription, privacy: .public)")
                return nil
            }
            item.mediaFileName = fileName
            item.mediaType = type
        case .files(let urls):
            item.filePaths = urls.map(\.path)
        }

        items.insert(item, at: 0)
        trimToCap()
        save()
        return item
    }

    /// Moves an entry to the top and stamps it as just used. Unknown ids are ignored.
    func moveToTop(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.copiedAt = now()
        items.insert(item, at: 0)
        save()
    }

    /// Pins or unpins an entry. Pinned entries survive the cap and "Clear All".
    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        trimToCap()
        save()
    }

    /// Deletes an entry and its media file, if any.
    func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        deleteMediaFile(of: items.remove(at: index))
        save()
    }

    /// Deletes every unpinned entry and its media file. Pinned entries stay.
    func clearUnpinned() {
        items.filter { !$0.isPinned }.forEach(deleteMediaFile(of:))
        items.removeAll { !$0.isPinned }
        save()
    }

    // MARK: - Reading content

    /// The pasteable payload of an entry, or nil if it can no longer be produced (e.g. media file gone).
    func content(of item: ClipItem) -> ClipContent? {
        switch item.kind {
        case .text:
            guard let text = item.text, !text.isEmpty else { return nil }
            return .text(text, rtf: item.rtfData)
        case .image, .video, .audio:
            guard let url = mediaURL(for: item), let type = item.mediaType,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            return .media(data, type: type)
        case .files:
            guard let paths = item.filePaths, !paths.isEmpty else { return nil }
            // .inferFromPath: URL(fileURLWithPath:) would stat each file, which can trigger folder-access prompts.
            return .files(paths.map { URL(filePath: $0, directoryHint: .inferFromPath) })
        }
    }

    /// Where a media entry's file lives, or nil for text and file entries.
    func mediaURL(for item: ClipItem) -> URL? {
        guard item.kind.isMedia, let fileName = item.mediaFileName, !fileName.isEmpty else { return nil }
        return mediaFolderURL.appending(path: fileName)
    }

    // MARK: - Hashing

    /// SHA-256 over a kind tag plus the payload. RTF is ignored: the same text copied with and
    /// without formatting is one entry.
    nonisolated static func contentHash(of content: ClipContent) -> String {
        var hasher = SHA256()
        switch content {
        case .text(let text, _):
            hasher.update(data: Data("text:".utf8))
            hasher.update(data: Data(text.utf8))
        case .media(let data, let type):
            hasher.update(data: Data("media:\(type):".utf8))
            hasher.update(data: data)
        case .files(let urls):
            hasher.update(data: Data("files:".utf8))
            hasher.update(data: Data(urls.map(\.path).joined(separator: "\n").utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private

    private func trimToCap() {
        var unpinnedKept = 0
        var kept: [ClipItem] = []
        for item in items {
            if item.isPinned {
                kept.append(item)
            } else if unpinnedKept < maxUnpinnedItems {
                unpinnedKept += 1
                kept.append(item)
            } else {
                deleteMediaFile(of: item)
            }
        }
        items = kept
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            Log.history.error("Could not save history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func mediaFileExists(for item: ClipItem) -> Bool {
        guard let url = mediaURL(for: item) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    private func deleteMediaFile(of item: ClipItem) {
        guard let url = mediaURL(for: item) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func removeOrphanMediaFiles() {
        guard let files = try? fileManager.contentsOfDirectory(atPath: mediaFolderURL.path) else { return }
        let referenced = Set(items.compactMap(\.mediaFileName))
        for file in files where !referenced.contains(file) {
            try? fileManager.removeItem(at: mediaFolderURL.appending(path: file))
        }
    }
}
