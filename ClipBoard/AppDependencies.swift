//
//  AppDependencies.swift
//  ClipBoard
//
//  Builds every store, service, view model and controller once, wires them, and starts them.
//

import AppKit
import OSLog

/// The app's object graph. Built once at launch; `start()` turns the clipboard on.
@MainActor
final class AppDependencies {
    let store: ClipHistoryStore
    let monitor: PasteboardMonitor
    let panelViewModel: ClipboardPanelViewModel
    let panelController: ClipboardPanelController
    let menuViewModel: MenuBarViewModel
    let hotKey: HotKeyService
    private var activationObserver: NSObjectProtocol?

    init() {
        let store = ClipHistoryStore()
        let monitor = PasteboardMonitor { content, sourceAppName in
            store.add(content, sourceAppName: sourceAppName)
        }
        let permissions = AccessibilityPermissionService()
        let pasteService = PasteService(permissions: permissions, onOwnWrite: { monitor.markOwnWrite() })
        let panelViewModel = ClipboardPanelViewModel(
            store: store,
            paster: pasteService,
            permissions: permissions,
            thumbnailer: ThumbnailService()
        )
        let panelController = ClipboardPanelController(viewModel: panelViewModel)
        let menuViewModel = MenuBarViewModel(
            store: store,
            launchAtLogin: LaunchAtLoginService(),
            permissions: permissions,
            settings: SettingsStore(),
            // Let the menu finish closing before the panel takes keyboard focus.
            openPanel: { Task { @MainActor in panelController.show() } },
            terminate: { NSApp.terminate(nil) }
        )
        let hotKey = HotKeyService { [weak menuViewModel] in
            panelController.toggle()
            menuViewModel?.refresh()
        }

        self.store = store
        self.monitor = monitor
        self.panelViewModel = panelViewModel
        self.panelController = panelController
        self.menuViewModel = menuViewModel
        self.hotKey = hotKey
    }

    /// Loads history, starts watching the clipboard, registers ⌘⇧V, and (first run from
    /// /Applications only) turns on Launch at Login.
    func start() {
        store.load()
        monitor.start()
        if !hotKey.register() {
            Log.hotKey.error("⌘⇧V is taken by another app; open the clipboard from the menu bar instead")
        }
        menuViewModel.enableLaunchAtLoginOnFirstInstall(bundlePath: Bundle.main.bundlePath)
        menuViewModel.refresh()
        // Switching apps (e.g. back from System Settings) is when permission changes show up.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak menuViewModel] _ in
            MainActor.assumeIsolated { menuViewModel?.refresh() }
        }
    }
}
