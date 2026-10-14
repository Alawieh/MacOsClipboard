//
//  ClipContent.swift
//  ClipBoard
//
//  The payload of one clipboard copy, as read from or written to the pasteboard.
//

import Foundation

/// What was copied, independent of how it is stored in history.
/// - `.text` keeps the RTF flavour when the source offered one, so formatting survives a re-paste.
/// - `.media` keeps image, video or audio bytes in their original format (a GIF stays animated);
///   `type` is the uniform type identifier, e.g. `com.compuserve.gif` or `public.mpeg-4`.
/// - `.files` are file URLs, e.g. photos or videos copied in Finder.
enum ClipContent: Equatable, Sendable {
    case text(String, rtf: Data?)
    case media(Data, type: String)
    case files([URL])

    /// The history kind this content is stored as.
    var kind: ClipItem.Kind {
        switch self {
        case .text: .text
        case .media(_, let type): .forMedia(type: type)
        case .files: .files
        }
    }
}
