//
//  Theme.swift
//  ClipBoard
//
//  AppTheme: the only source of colors, fonts, spacing, radii and sizes for views.
//

import SwiftUI

/// Design tokens. Views style themselves only through these.
enum AppTheme {
    enum Primary {
        static let accent = Color.accentColor
    }

    enum Text {
        static let primary = Color.primary
        static let secondary = Color.secondary
        /// Badges drawn over photo and video thumbnails.
        static let onMedia = Color.white
    }

    enum Background {
        static let panel: Material = .regularMaterial
        static let panelBorder = Color.primary.opacity(0.12)
        static let selectedRow = Color.accentColor.opacity(0.25)
        static let hoveredRow = Color.primary.opacity(0.06)
        static let icon = Color.primary.opacity(0.08)
        static let clear = Color.clear
    }

    enum Typography {
        static let title = Font.headline
        static let row = Font.body
        static let caption = Font.caption
        static let hint = Font.caption2
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    enum Radius {
        static let panel: CGFloat = 12
        static let row: CGFloat = 8
        static let icon: CGFloat = 5
        static let badgeShadow: CGFloat = 1
    }

    enum Size {
        static let panel = CGSize(width: 380, height: 480)
        static let icon: CGFloat = 32
        /// Gap kept between the panel and the screen edge.
        static let screenMargin: CGFloat = 8
    }
}
