//
//  AccessibilityPermissionService.swift
//  ClipBoard
//
//  Accessibility (TCC) permission, needed to send ⌘V to the app being pasted into.
//

import AppKit
import ApplicationServices

/// Reads and requests the Accessibility permission that auto-paste depends on.
@MainActor
protocol AccessibilityPermissionChecking: AnyObject {
    var isTrusted: Bool { get }
    /// Shows the system prompt the first time per launch; later calls do nothing.
    func requestTrustOnce()
    /// Shows the system prompt and opens the Accessibility pane in System Settings.
    func requestTrust()
}

/// Thin wrapper over AXIsProcessTrusted. Without the permission, picked items are only copied.
@MainActor
final class AccessibilityPermissionService: AccessibilityPermissionChecking {
    private var didPrompt = false

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestTrustOnce() {
        guard !didPrompt else { return }
        prompt()
    }

    func requestTrust() {
        prompt()
        if let url = URL(string: ACCESSIBILITY_SETTINGS_URL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func prompt() {
        didPrompt = true
        // The literal key, because the imported kAXTrustedCheckOptionPrompt global is not concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
