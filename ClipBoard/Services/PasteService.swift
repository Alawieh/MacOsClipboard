//
//  PasteService.swift
//  ClipBoard
//
//  Puts a picked history entry on the clipboard and pastes it into the frontmost app.
//

import AppKit
import Carbon.HIToolbox

/// Something that can paste content into the app the user was working in.
@MainActor
protocol ClipPasting: AnyObject {
    func paste(_ content: ClipContent)
}

/// Writes the content to the pasteboard, then sends ⌘V to the frontmost app. Sending keystrokes
/// needs Accessibility permission; without it the content is left on the clipboard and the user is
/// prompted (once per launch) so they can paste by hand.
@MainActor
final class PasteService: ClipPasting {
    private let pasteboard: NSPasteboard
    private let writer: PasteboardWriter
    private let permissions: AccessibilityPermissionChecking
    private let onOwnWrite: @MainActor () -> Void
    private let postPasteKeystroke: @MainActor () -> Void
    private let keystrokeDelay: Duration

    /// - Parameter onOwnWrite: called right after writing, so the pasteboard monitor skips this change.
    init(
        pasteboard: NSPasteboard = .general,
        writer: PasteboardWriter = PasteboardWriter(),
        permissions: AccessibilityPermissionChecking,
        onOwnWrite: @escaping @MainActor () -> Void,
        postPasteKeystroke: @escaping @MainActor () -> Void = PasteService.postCommandV,
        keystrokeDelay: Duration = PASTE_KEYSTROKE_DELAY
    ) {
        self.pasteboard = pasteboard
        self.writer = writer
        self.permissions = permissions
        self.onOwnWrite = onOwnWrite
        self.postPasteKeystroke = postPasteKeystroke
        self.keystrokeDelay = keystrokeDelay
    }

    func paste(_ content: ClipContent) {
        Task { await performPaste(content) }
    }

    /// Writes, marks the write as our own, then (if trusted) waits `keystrokeDelay` and sends ⌘V.
    func performPaste(_ content: ClipContent) async {
        writer.write(content, to: pasteboard)
        onOwnWrite()
        guard permissions.isTrusted else {
            permissions.requestTrustOnce()
            return
        }
        try? await Task.sleep(for: keystrokeDelay)
        postPasteKeystroke()
    }

    /// Sends a synthetic ⌘V key down/up to the session.
    nonisolated static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
