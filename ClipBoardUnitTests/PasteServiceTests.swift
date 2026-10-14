//
//  PasteServiceTests.swift
//  ClipBoardUnitTests
//
//  Paste flow: write the clipboard, skip it in the monitor, then send ⌘V only with permission.
//

import AppKit
import Testing
@testable import ClipBoard

@MainActor
@Suite("PasteService")
struct PasteServiceTests {
    let pasteboard = NSPasteboard.withUniqueName()

    final class Calls {
        var ownWrites = 0
        var keystrokes = 0
    }

    func makeService(_ calls: Calls, permissions: FakePermissions) -> PasteService {
        PasteService(
            pasteboard: pasteboard,
            permissions: permissions,
            onOwnWrite: { calls.ownWrites += 1 },
            postPasteKeystroke: { calls.keystrokes += 1 },
            keystrokeDelay: .zero
        )
    }

    @Test("With permission: writes the clipboard, marks it as ours, sends ⌘V")
    func pastesWhenTrusted() async {
        let calls = Calls()
        let permissions = FakePermissions(isTrusted: true)
        await makeService(calls, permissions: permissions).performPaste(.text("hello", rtf: nil))

        #expect(pasteboard.string(forType: .string) == "hello")
        #expect(calls.ownWrites == 1)
        #expect(calls.keystrokes == 1)
        #expect(permissions.requestOnceCount == 0)
    }

    @Test("Without permission: leaves it on the clipboard, prompts, sends nothing")
    func copiesOnlyWhenUntrusted() async {
        let calls = Calls()
        let permissions = FakePermissions(isTrusted: false)
        await makeService(calls, permissions: permissions).performPaste(.text("hello", rtf: nil))

        #expect(pasteboard.string(forType: .string) == "hello")
        #expect(calls.ownWrites == 1)
        #expect(calls.keystrokes == 0)
        #expect(permissions.requestOnceCount == 1)
    }

    @Test("paste(_:) runs the same flow asynchronously")
    func pasteEntryPoint() async {
        let calls = Calls()
        let service = makeService(calls, permissions: FakePermissions(isTrusted: true))
        service.paste(.text("async", rtf: nil))
        for _ in 0..<100 where calls.keystrokes == 0 {
            await Task.yield()
        }
        #expect(calls.keystrokes == 1)
        #expect(pasteboard.string(forType: .string) == "async")
    }
}
