//
//  MenuBarViewModel.swift
//  ClipBoard
//
//  State and intents for the menu-bar menu: open, launch at login, auto-paste permission, clear, quit.
//

import Foundation
import Observation

/// Drives the menu-bar menu.
@MainActor
@Observable
final class MenuBarViewModel {
    private(set) var isLaunchAtLoginEnabled = false
    private(set) var hasAccessibilityPermission = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let store: ClipHistoryStore
    @ObservationIgnored private let launchAtLogin: LaunchAtLoginControlling
    @ObservationIgnored private let permissions: AccessibilityPermissionChecking
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let openPanel: @MainActor () -> Void
    @ObservationIgnored private let terminate: @MainActor () -> Void

    init(
        store: ClipHistoryStore,
        launchAtLogin: LaunchAtLoginControlling,
        permissions: AccessibilityPermissionChecking,
        settings: SettingsStore,
        openPanel: @escaping @MainActor () -> Void,
        terminate: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        self.permissions = permissions
        self.settings = settings
        self.openPanel = openPanel
        self.terminate = terminate
        refresh()
    }

    var hasHistory: Bool { !store.items.isEmpty }

    /// Re-reads launch-at-login and permission state from the system.
    func refresh() {
        isLaunchAtLoginEnabled = launchAtLogin.isEnabled
        hasAccessibilityPermission = permissions.isTrusted
    }

    /// Turns launch at login on or off. On failure, keeps the real state and sets `errorMessage`.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn’t change Launch at Login: \(error.localizedDescription)")
        }
        refresh()
    }

    /// The first time the app runs from /Applications, turns Launch at Login on so the clipboard is
    /// always running. Runs once ever: if the user later turns it off, it stays off. Copies run from
    /// elsewhere (e.g. Xcode's build folder) never register themselves.
    func enableLaunchAtLoginOnFirstInstall(bundlePath: String) {
        guard !settings.didAutoEnableLaunchAtLogin, bundlePath.hasPrefix(APPLICATIONS_FOLDER_PATH) else { return }
        settings.didAutoEnableLaunchAtLogin = true
        if !launchAtLogin.isEnabled {
            setLaunchAtLogin(true)
        }
    }

    func requestAccessibility() {
        permissions.requestTrust()
        refresh()
    }

    func openClipboard() {
        openPanel()
    }

    /// Clears unpinned history; pinned entries stay.
    func clearHistory() {
        store.clearUnpinned()
    }

    func quit() {
        terminate()
    }
}
