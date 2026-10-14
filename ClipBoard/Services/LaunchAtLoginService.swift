//
//  LaunchAtLoginService.swift
//  ClipBoard
//
//  Registers the app as a login item so it is always running.
//

import ServiceManagement

/// Turns "open at login" on or off for this app.
@MainActor
protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Thin wrapper over SMAppService.mainApp.
@MainActor
final class LaunchAtLoginService: LaunchAtLoginControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Throws the ServiceManagement error if macOS refuses the change.
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
