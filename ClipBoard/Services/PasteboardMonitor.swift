//
//  PasteboardMonitor.swift
//  ClipBoard
//
//  Watches the system pasteboard and reports every new copy.
//

import AppKit

/// Polls `changeCount` (macOS has no pasteboard-changed notification) and calls `onCapture` once
/// per new copy that the reader accepts. Writes the app makes itself are skipped via `markOwnWrite()`.
@MainActor
final class PasteboardMonitor {
    private let pasteboard: NSPasteboard
    private let reader: PasteboardReader
    private let interval: Duration
    private let frontmostAppName: @MainActor () -> String?
    private let onCapture: @MainActor (ClipContent, String?) -> Void
    private var lastChangeCount: Int
    private var pollTask: Task<Void, Never>?

    /// - Parameters:
    ///   - frontmostAppName: name of the app the copy came from, shown in the history row.
    ///   - onCapture: called on the main actor with the content and its source app name.
    init(
        pasteboard: NSPasteboard = .general,
        reader: PasteboardReader = PasteboardReader(),
        interval: Duration = PASTEBOARD_POLL_INTERVAL,
        frontmostAppName: @escaping @MainActor () -> String? = { NSWorkspace.shared.frontmostApplication?.localizedName },
        onCapture: @escaping @MainActor (ClipContent, String?) -> Void
    ) {
        self.pasteboard = pasteboard
        self.reader = reader
        self.interval = interval
        self.frontmostAppName = frontmostAppName
        self.onCapture = onCapture
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Starts polling. Whatever is on the pasteboard at start is not recorded. Calling twice is a no-op.
    func start() {
        guard pollTask == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let interval = interval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Checks once for a new copy. Each pasteboard change is reported at most once.
    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard let content = reader.read(pasteboard) else { return }
        onCapture(content, frontmostAppName())
    }

    /// Call right after the app writes to the pasteboard, so that write is not recorded as a new copy.
    func markOwnWrite() {
        lastChangeCount = pasteboard.changeCount
    }
}
