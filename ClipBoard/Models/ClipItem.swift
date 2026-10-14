//
//  ClipItem.swift
//  ClipBoard
//
//  One entry in the clipboard history, as persisted to history.json.
//

import Foundation
import UniformTypeIdentifiers

/// A stored clipboard entry. Media bytes live in files next to history.json and are referenced by
/// `mediaFileName` (relative), never by absolute path. Decoding is lenient: missing or invalid
/// fields fall back to defaults instead of failing the whole history file.
struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text
        case image
        case video
        case audio
        case files

        /// Audio for audio types, video for other audiovisual types, image otherwise.
        static func forMedia(type: String) -> Kind {
            guard let utType = UTType(type) else { return .image }
            if utType.conforms(to: .audio) { return .audio }
            if utType.conforms(to: .audiovisualContent) { return .video }
            return .image
        }

        var isMedia: Bool {
            self == .image || self == .video || self == .audio
        }
    }

    let id: UUID
    var kind: Kind
    var text: String?
    var rtfData: Data?
    var mediaFileName: String?
    /// Uniform type identifier of the media file, e.g. `public.png`.
    var mediaType: String?
    var filePaths: [String]?
    var copiedAt: Date
    var isPinned: Bool
    /// SHA-256 of the content; two copies with the same hash are the same entry.
    var contentHash: String
    var sourceAppName: String?

    init(
        id: UUID,
        kind: Kind,
        text: String? = nil,
        rtfData: Data? = nil,
        mediaFileName: String? = nil,
        mediaType: String? = nil,
        filePaths: [String]? = nil,
        copiedAt: Date,
        isPinned: Bool = false,
        contentHash: String,
        sourceAppName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.rtfData = rtfData
        self.mediaFileName = mediaFileName
        self.mediaType = mediaType
        self.filePaths = filePaths
        self.copiedAt = copiedAt
        self.isPinned = isPinned
        self.contentHash = contentHash
        self.sourceAppName = sourceAppName
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, text, rtfData, mediaFileName, mediaType, filePaths, copiedAt, isPinned, contentHash, sourceAppName
    }

    /// Lenient decode: a missing id gets a fresh one, a missing hash falls back to the id (so it
    /// never merges with other entries), a missing date sorts as oldest.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? container.decode(Kind.self, forKey: .kind)) ?? .text
        text = try? container.decode(String.self, forKey: .text)
        rtfData = try? container.decode(Data.self, forKey: .rtfData)
        mediaFileName = try? container.decode(String.self, forKey: .mediaFileName)
        mediaType = try? container.decode(String.self, forKey: .mediaType)
        filePaths = try? container.decode([String].self, forKey: .filePaths)
        copiedAt = (try? container.decode(Date.self, forKey: .copiedAt)) ?? .distantPast
        isPinned = (try? container.decode(Bool.self, forKey: .isPinned)) ?? false
        contentHash = (try? container.decode(String.self, forKey: .contentHash)) ?? id.uuidString
        sourceAppName = try? container.decode(String.self, forKey: .sourceAppName)
    }

    /// True when the entry carries the payload its kind needs; entries without one are dropped on load.
    var hasContent: Bool {
        switch kind {
        case .text: !(text ?? "").isEmpty
        case .image, .video, .audio: !(mediaFileName ?? "").isEmpty && !(mediaType ?? "").isEmpty
        case .files: !(filePaths ?? []).isEmpty
        }
    }
}
