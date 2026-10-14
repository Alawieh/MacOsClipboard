//
//  MenuBarViewModelTests.swift
//  ClipBoardUnitTests
//
//  Menu intents: launch at login (including the one-time auto-enable), permission, clear, open, quit.
//

import Foundation
import Testing
@testable import ClipBoard

@MainActor
@Suite("MenuBarViewModel")
struct MenuBarViewModelTests {
    let folder = TemporaryDirectory()
    let suiteName = "ClipBoardTests-\(UUID().uuidString)"
    let launchAtLogin = FakeLaunchAtLogin()
    let permissions = FakePermissions(isTrusted: false)
    let store: ClipHistoryStore
    let settings: SettingsStore

    final class Calls {
        var opens = 0
        var quits = 0
    }
    let calls = Calls()

    init() {
        store = ClipHistoryStore(directory: folder.url)
        settings = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    func makeViewModel() -> MenuBarViewModel {
        let calls = calls
        return MenuBarViewModel(
            store: store,
            launchAtLogin: launchAtLogin,
            permissions: permissions,
            settings: settings,
            openPanel: { calls.opens += 1 },
            terminate: { calls.quits += 1 }
        )
    }

    @Test("Starts from the system's real state")
    func initialState() {
        launchAtLogin.isEnabled = true
        let viewModel = makeViewModel()
        #expect(viewModel.isLaunchAtLoginEnabled)
        #expect(!viewModel.hasAccessibilityPermission)
        #expect(!viewModel.hasHistory)
    }

    @Test("Toggling Launch at Login updates the state")
    func toggleLaunchAtLogin() {
        let viewModel = makeViewModel()
        viewModel.setLaunchAtLogin(true)
        #expect(viewModel.isLaunchAtLoginEnabled)
        #expect(viewModel.errorMessage == nil)
        viewModel.setLaunchAtLogin(false)
        #expect(!viewModel.isLaunchAtLoginEnabled)
    }

    @Test("A refused Launch at Login change shows an error and keeps the real state")
    func toggleLaunchAtLoginFailure() {
        launchAtLogin.errorToThrow = SampleError()
        let viewModel = makeViewModel()
        viewModel.setLaunchAtLogin(true)
        #expect(!viewModel.isLaunchAtLoginEnabled)
        #expect(viewModel.errorMessage?.contains("Operation not permitted") == true)

        launchAtLogin.errorToThrow = nil
        viewModel.setLaunchAtLogin(true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("First run from /Applications turns Launch at Login on, once only")
    func autoEnableOnce() {
        let viewModel = makeViewModel()
        viewModel.enableLaunchAtLoginOnFirstInstall(bundlePath: "/Applications/ClipBoard.app")
        #expect(viewModel.isLaunchAtLoginEnabled)
        #expect(settings.didAutoEnableLaunchAtLogin)

        viewModel.setLaunchAtLogin(false)
        viewModel.enableLaunchAtLoginOnFirstInstall(bundlePath: "/Applications/ClipBoard.app")
        #expect(!viewModel.isLaunchAtLoginEnabled)
    }

    @Test("Runs from Xcode's build folder never register a login item")
    func noAutoEnableOutsideApplications() {
        let viewModel = makeViewModel()
        viewModel.enableLaunchAtLoginOnFirstInstall(bundlePath: "/Users/me/Library/Developer/Xcode/DerivedData/ClipBoard.app")
        #expect(launchAtLogin.setCalls.isEmpty)
        #expect(!settings.didAutoEnableLaunchAtLogin)
    }

    @Test("Auto-enable does not re-register when already on")
    func autoEnableAlreadyOn() {
        launchAtLogin.isEnabled = true
        let viewModel = makeViewModel()
        viewModel.enableLaunchAtLoginOnFirstInstall(bundlePath: "/Applications/ClipBoard.app")
        #expect(launchAtLogin.setCalls.isEmpty)
        #expect(settings.didAutoEnableLaunchAtLogin)
    }

    @Test("Enable Auto-Paste asks for permission and refreshes")
    func requestAccessibility() {
        permissions.grantOnRequest = true
        let viewModel = makeViewModel()
        viewModel.requestAccessibility()
        #expect(permissions.requestCount == 1)
        #expect(viewModel.hasAccessibilityPermission)
    }

    @Test("Clear History keeps pinned entries")
    func clearHistory() throws {
        let pinned = try #require(store.add(.text("pinned", rtf: nil), sourceAppName: nil))
        store.togglePin(pinned.id)
        store.add(.text("loose", rtf: nil), sourceAppName: nil)
        let viewModel = makeViewModel()
        #expect(viewModel.hasHistory)
        viewModel.clearHistory()
        #expect(store.items.map(\.text) == ["pinned"])
    }

    @Test("Open and Quit call through")
    func openAndQuit() {
        let viewModel = makeViewModel()
        viewModel.openClipboard()
        viewModel.quit()
        #expect(calls.opens == 1)
        #expect(calls.quits == 1)
    }
}
