//
//  AccessibilityID.swift
//  ClipBoard
//
//  Accessibility identifiers for every control and observable element (<screen>_<element>_<kind>).
//

import Foundation

/// Identifier constants. Call sites never use string literals.
enum AccessibilityID {
    enum Panel {
        static let root = "clipboard_root_view"
        static let searchField = "clipboard_search_textField"
        static let list = "clipboard_list_view"
        static let emptyLabel = "clipboard_empty_label"
        static let clearAllButton = "clipboard_clearAll_button"
        static let autoPasteOffLabel = "clipboard_autoPasteOff_label"
        static let enableAutoPasteButton = "clipboard_enableAutoPaste_button"
        static let hintsLabel = "clipboard_hints_label"

        static func row(_ id: UUID) -> String { "clipboard_row_\(id.uuidString)" }
        static func pinButton(_ id: UUID) -> String { "clipboard_pin_button_\(id.uuidString)" }
        static func deleteButton(_ id: UUID) -> String { "clipboard_delete_button_\(id.uuidString)" }
    }

    enum Menu {
        static let openButton = "menu_open_button"
        static let launchAtLoginToggle = "menu_launchAtLogin_toggle"
        static let enableAutoPasteButton = "menu_enableAutoPaste_button"
        static let errorLabel = "menu_error_label"
        static let clearHistoryButton = "menu_clearHistory_button"
        static let quitButton = "menu_quit_button"
    }
}
