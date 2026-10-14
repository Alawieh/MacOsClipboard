//
//  AppDelegate.swift
//  ClipBoard
//
//  Starts the clipboard at launch, unless the process is only hosting unit tests.
//

import AppKit

/// Holds the app's dependencies and starts them when launching finishes. When the app is the
/// host process for unit tests, it builds nothing, so tests never touch the real clipboard,
/// history file, hot key or login items.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dependencies: AppDependencies?

    override init() {
        let isTestHost = ProcessInfo.processInfo.environment[ENV_XCTEST_CONFIGURATION] != nil
        dependencies = isTestHost ? nil : AppDependencies()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        dependencies?.start()
    }
}
