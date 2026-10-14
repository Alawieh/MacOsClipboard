//
//  TestDoubles.swift
//  ClipBoardUnitTests
//
//  Fakes, a controllable clock, temp folders and sample data shared by the unit tests.
//

import AppKit
import UniformTypeIdentifiers
@testable import ClipBoard

let PNG = UTType.png.identifier
let GIF = UTType.gif.identifier
let MP4 = UTType.mpeg4Movie.identifier
let MP3 = UTType.mp3.identifier

/// A folder under the system temp directory, deleted when the instance goes away.
final class TemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appending(path: "ClipBoardTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A clock tests move by hand.
@MainActor
final class TestClock {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func advance(seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// Records pastes instead of touching the system.
@MainActor
final class FakePaster: ClipPasting {
    private(set) var pasted: [ClipContent] = []

    func paste(_ content: ClipContent) {
        pasted.append(content)
    }
}

@MainActor
final class FakePermissions: AccessibilityPermissionChecking {
    var isTrusted: Bool
    var grantOnRequest = false
    private(set) var requestOnceCount = 0
    private(set) var requestCount = 0

    init(isTrusted: Bool = true) {
        self.isTrusted = isTrusted
    }

    func requestTrustOnce() {
        requestOnceCount += 1
    }

    func requestTrust() {
        requestCount += 1
        if grantOnRequest { isTrusted = true }
    }
}

@MainActor
final class FakeLaunchAtLogin: LaunchAtLoginControlling {
    var isEnabled = false
    var errorToThrow: Error?
    private(set) var setCalls: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        setCalls.append(enabled)
        if let errorToThrow { throw errorToThrow }
        isEnabled = enabled
    }
}

/// Returns fixed images, and records every file it was asked to read and every icon extension.
@MainActor
final class FakeThumbnails: ThumbnailProviding {
    let image = NSImage(size: NSSize(width: 4, height: 4))
    let icon = NSImage(size: NSSize(width: 2, height: 2))
    var fails = false
    private(set) var requests: [URL] = []
    private(set) var iconExtensions: [String] = []

    func thumbnail(for url: URL, side: CGFloat) async -> NSImage? {
        requests.append(url)
        return fails ? nil : image
    }

    func icon(forPathExtension pathExtension: String) -> NSImage {
        iconExtensions.append(pathExtension)
        return icon
    }
}

struct SampleError: LocalizedError {
    var errorDescription: String? { "Operation not permitted" }
}

enum SampleData {
    /// A valid PNG of the given size, filled with one colour.
    static func png(width: Int = 2, height: Int = 2, red: UInt8 = 255) -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        for x in 0..<width {
            for y in 0..<height {
                bitmap.setColor(NSColor(red: CGFloat(red) / 255, green: 0, blue: 0, alpha: 1), atX: x, y: y)
            }
        }
        return bitmap.representation(using: .png, properties: [:])!
    }

    /// A one-frame GIF; enough to check the format survives untouched.
    static func gif() -> Data {
        NSBitmapImageRep(data: png())!.representation(using: .gif, properties: [:])!
    }

    /// Stand-in movie bytes. The app never decodes media, it only stores and re-pastes it.
    static func movie() -> Data {
        Data("fake mp4 bytes".utf8)
    }

    static func rtf(_ text: String) -> Data {
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        return attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])!
    }
}
