//
//  ClipBoardApp.swift
//  ClipBoard
//
//  Entry point: a menu-bar-only app (no Dock icon, LSUIElement) with a ⌘⇧V history panel.
//

import SwiftUI

@main
struct ClipBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(appDelegate.dependencies != nil)) {
            if let dependencies = appDelegate.dependencies {
                MenuBarMenuView(viewModel: dependencies.menuViewModel)
            }
        } label: {
            Image(systemName: "list.clipboard")
        }
    }
}
