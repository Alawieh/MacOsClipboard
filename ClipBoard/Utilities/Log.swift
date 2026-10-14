//
//  Log.swift
//  ClipBoard
//
//  Unified-logging categories. Never logs clipboard contents.
//

import OSLog

/// Loggers by area. Messages describe what happened, never what the user copied.
enum Log {
    static let history = Logger(subsystem: APP_BUNDLE_ID, category: "history")
    static let hotKey = Logger(subsystem: APP_BUNDLE_ID, category: "hotKey")
    static let system = Logger(subsystem: APP_BUNDLE_ID, category: "system")
}
