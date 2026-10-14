//
//  ClipboardPanelController.swift
//  ClipBoard
//
//  Shows, places and hides the history panel and maps its keyboard shortcuts to view model intents.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Owns the panel window. Opens it at the mouse pointer, routes ↑ ↓ ↩ esc ⌘1–9 ⌘P ⌘⌫ to the view
/// model while it is open, and hides it on esc, after a paste, or when it loses focus.
@MainActor
final class ClipboardPanelController {
    private let panel: ClipboardPanel
    private let viewModel: ClipboardPanelViewModel
    private var keyMonitor: Any?
    private var isShowing = false

    init(viewModel: ClipboardPanelViewModel) {
        self.viewModel = viewModel
        panel = ClipboardPanel(size: AppTheme.Size.panel)
        panel.contentView = NSHostingView(rootView: ClipboardPanelView(viewModel: viewModel))
        panel.onResignKey = { [weak self] in self?.hide() }
        viewModel.onDismiss = { [weak self] in self?.hide() }
    }

    func toggle() {
        isShowing ? hide() : show()
    }

    func show() {
        viewModel.prepareForShow()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            panel.setFrameOrigin(Self.origin(forMouse: mouse, panelSize: panel.frame.size, visibleFrame: visibleFrame))
        }
        isShowing = true
        installKeyMonitor()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    /// Top-left corner at the pointer, pushed inside `visibleFrame` (minus a margin) so the whole
    /// panel stays on screen. AppKit coordinates: origin is the bottom-left corner.
    static func origin(forMouse mouse: NSPoint, panelSize: CGSize, visibleFrame: NSRect) -> NSPoint {
        let margin = AppTheme.Size.screenMargin
        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - margin - panelSize.width)
        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - margin - panelSize.height)
        return NSPoint(
            x: min(max(mouse.x, minX), maxX),
            y: min(max(mouse.y - panelSize.height, minY), maxY)
        )
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// - Returns: true when the key was a panel shortcut and must not reach the search field.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch Int(event.keyCode) {
        case kVK_DownArrow:
            viewModel.moveSelection(by: 1)
        case kVK_UpArrow:
            viewModel.moveSelection(by: -1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            viewModel.pasteSelected()
        case kVK_Escape:
            viewModel.dismiss()
        case kVK_Delete where flags == .command:
            viewModel.deleteSelected()
        case kVK_ANSI_P where flags == .command:
            viewModel.togglePinSelected()
        default:
            guard flags == .command,
                  let characters = event.charactersIgnoringModifiers,
                  let number = Int(characters) else { return false }
            viewModel.paste(atShortcutNumber: number)
        }
        return true
    }
}
