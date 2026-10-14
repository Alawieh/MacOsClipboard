//
//  ClipboardPanelPlacementTests.swift
//  ClipBoardUnitTests
//
//  The panel opens at the pointer but always stays fully on screen.
//

import AppKit
import Testing
@testable import ClipBoard

@MainActor
@Suite("Panel placement")
struct ClipboardPanelPlacementTests {
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
    let size = CGSize(width: 380, height: 480)
    let margin = AppTheme.Size.screenMargin

    @Test("Top-left corner sits at the pointer when there is room")
    func atPointer() {
        let origin = ClipboardPanelController.origin(forMouse: NSPoint(x: 400, y: 700), panelSize: size, visibleFrame: screen)
        #expect(origin == NSPoint(x: 400, y: 220))
    }

    @Test("Near the right and bottom edges it is pushed back on screen")
    func clampsBottomRight() {
        let origin = ClipboardPanelController.origin(forMouse: NSPoint(x: 1430, y: 10), panelSize: size, visibleFrame: screen)
        #expect(origin == NSPoint(x: 1440 - margin - 380, y: margin))
    }

    @Test("On a second screen to the left, coordinates stay within that screen")
    func secondScreen() {
        let left = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let origin = ClipboardPanelController.origin(forMouse: NSPoint(x: -1915, y: 1079), panelSize: size, visibleFrame: left)
        #expect(origin == NSPoint(x: -1920 + margin, y: 1080 - margin - 480))
    }
}
