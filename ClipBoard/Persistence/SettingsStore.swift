//
//  SettingsStore.swift
//  ClipBoard
//
//  The app's small UserDefaults-backed flags.
//

import Foundation

/// All UserDefaults access. Tests pass a throwaway suite.
@MainActor
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True once the app has turned Launch at Login on by itself, so a later "off" from the user sticks.
    var didAutoEnableLaunchAtLogin: Bool {
        get { defaults.bool(forKey: DEFAULTS_KEY_DID_AUTO_ENABLE_LAUNCH_AT_LOGIN) }
        set { defaults.set(newValue, forKey: DEFAULTS_KEY_DID_AUTO_ENABLE_LAUNCH_AT_LOGIN) }
    }
}
