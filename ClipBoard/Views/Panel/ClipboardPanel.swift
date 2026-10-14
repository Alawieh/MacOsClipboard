//
//  ClipboardPanel.swift
//  ClipBoard
//
//  The borderless floating window that hosts the history panel without stealing app focus.
//

import AppKit

/// A non-activating panel: it takes keyboard input while the app you were typing in stays the
/// active app, so ⌘V after closing lands back in that app. Reports losing key status (a click
/// elsewhere) through `onResignKey`.
final class ClipboardPanel: NSPanel {
    var onResignKey: (@MainActor () -> Void)?

    init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
