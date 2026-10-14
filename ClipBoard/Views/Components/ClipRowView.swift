//
//  ClipRowView.swift
//  ClipBoard
//
//  One history row: icon or thumbnail, preview, source and age, pin/delete on hover, ⌘-number hint.
//

import SwiftUI

/// A history row. Clicking anywhere outside its buttons pastes the entry.
struct ClipRowView: View {
    let itemID: UUID
    let title: String
    let subtitle: String
    let kind: ClipItem.Kind
    let thumbnail: NSImage?
    let isPinned: Bool
    let isSelected: Bool
    let shortcutNumber: Int?
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            leadingIcon
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(verbatim: title)
                    .font(AppTheme.Typography.row)
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: subtitle)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(1)
            }
            trailingControls
        }
        .padding(AppTheme.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .fill(rowBackground)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onPaste)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(AccessibilityID.Panel.row(itemID))
    }

    private var rowBackground: Color {
        if isSelected { return AppTheme.Background.selectedRow }
        return isHovered ? AppTheme.Background.hoveredRow : AppTheme.Background.clear
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: AppTheme.Size.icon, height: AppTheme.Size.icon)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.icon, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if kind == .video {
                        Image(systemName: "play.circle.fill")
                            .font(AppTheme.Typography.hint)
                            .foregroundStyle(AppTheme.Text.onMedia)
                            .shadow(radius: AppTheme.Radius.badgeShadow)
                            .padding(AppTheme.Spacing.xxs)
                    }
                }
        } else {
            Image(systemName: iconName)
                .foregroundStyle(AppTheme.Text.secondary)
                .frame(width: AppTheme.Size.icon, height: AppTheme.Size.icon)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.icon, style: .continuous)
                        .fill(AppTheme.Background.icon)
                )
        }
    }

    private var iconName: String {
        switch kind {
        case .text: "text.alignleft"
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .files: "doc"
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        if isHovered || isPinned {
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(isPinned ? Text("Unpin") : Text("Pin"))
            .accessibilityLabel(isPinned ? Text("Unpin") : Text("Pin"))
            .accessibilityIdentifier(AccessibilityID.Panel.pinButton(itemID))
        }
        if isHovered {
            Button(action: onDelete) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(Text("Delete"))
            .accessibilityLabel(Text("Delete"))
            .accessibilityIdentifier(AccessibilityID.Panel.deleteButton(itemID))
        } else if let shortcutNumber {
            Text(verbatim: "⌘\(shortcutNumber)")
                .font(AppTheme.Typography.hint)
                .foregroundStyle(AppTheme.Text.secondary)
        }
    }
}
