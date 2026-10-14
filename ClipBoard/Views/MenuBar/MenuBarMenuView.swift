//
//  MenuBarMenuView.swift
//  ClipBoard
//
//  The menu under the clipboard icon in the menu bar.
//

import SwiftUI

/// Menu-bar menu: open the panel, launch at login, enable auto-paste, clear history, quit.
struct MenuBarMenuView: View {
    let viewModel: MenuBarViewModel

    var body: some View {
        Button("Open Clipboard") { viewModel.openClipboard() }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .accessibilityIdentifier(AccessibilityID.Menu.openButton)

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { viewModel.isLaunchAtLoginEnabled },
            set: { viewModel.setLaunchAtLogin($0) }
        ))
        .accessibilityIdentifier(AccessibilityID.Menu.launchAtLoginToggle)

        if !viewModel.hasAccessibilityPermission {
            Button("Enable Auto-Paste…") { viewModel.requestAccessibility() }
                .accessibilityIdentifier(AccessibilityID.Menu.enableAutoPasteButton)
        }

        if let errorMessage = viewModel.errorMessage {
            Text(verbatim: errorMessage)
                .accessibilityIdentifier(AccessibilityID.Menu.errorLabel)
        }

        Divider()

        Button("Clear History") { viewModel.clearHistory() }
            .disabled(!viewModel.hasHistory)
            .accessibilityIdentifier(AccessibilityID.Menu.clearHistoryButton)

        Divider()

        Button("Quit ClipBoard") { viewModel.quit() }
            .keyboardShortcut("q")
            .accessibilityIdentifier(AccessibilityID.Menu.quitButton)
    }
}
