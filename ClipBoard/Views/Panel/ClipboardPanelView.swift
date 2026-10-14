//
//  ClipboardPanelView.swift
//  ClipBoard
//
//  The ⌘⇧V history panel: title, search, history list, auto-paste notice and key hints.
//

import SwiftUI

/// Content of the floating history panel. Keyboard shortcuts are handled by ClipboardPanelController;
/// typing goes to the search field.
struct ClipboardPanelView: View {
    @Bindable var viewModel: ClipboardPanelViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: AppTheme.Size.panel.width, height: AppTheme.Size.panel.height)
        .background(AppTheme.Background.panel)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.panel, style: .continuous)
                .strokeBorder(AppTheme.Background.panelBorder)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Panel.root)
        .onChange(of: viewModel.focusRequest, initial: true) {
            isSearchFocused = true
        }
    }

    private var header: some View {
        HStack {
            Text("Clipboard")
                .font(AppTheme.Typography.title)
            Spacer()
            Button("Clear All") { viewModel.clearUnpinned() }
                .buttonStyle(.borderless)
                .disabled(!viewModel.hasUnpinnedItems)
                .accessibilityIdentifier(AccessibilityID.Panel.clearAllButton)
        }
        .padding(.horizontal, AppTheme.Spacing.l)
        .padding(.top, AppTheme.Spacing.m)
        .padding(.bottom, AppTheme.Spacing.s)
    }

    private var searchField: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.Text.secondary)
            TextField("Search", text: $viewModel.query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .accessibilityIdentifier(AccessibilityID.Panel.searchField)
        }
        .padding(.horizontal, AppTheme.Spacing.l)
        .padding(.bottom, AppTheme.Spacing.s)
    }

    @ViewBuilder
    private var list: some View {
        if let message = viewModel.emptyStateMessage {
            Text(verbatim: message)
                .font(AppTheme.Typography.row)
                .foregroundStyle(AppTheme.Text.secondary)
                .multilineTextAlignment(.center)
                .padding(AppTheme.Spacing.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier(AccessibilityID.Panel.emptyLabel)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.xxs) {
                        ForEach(Array(viewModel.visibleItems.enumerated()), id: \.element.id) { index, item in
                            ClipRowView(
                                itemID: item.id,
                                title: viewModel.title(for: item),
                                subtitle: viewModel.subtitle(for: item),
                                kind: item.kind,
                                thumbnail: viewModel.thumbnails[item.id],
                                isPinned: item.isPinned,
                                isSelected: item.id == viewModel.selectedID,
                                shortcutNumber: ClipboardPanelViewModel.shortcutNumber(at: index),
                                onPaste: { viewModel.paste(item) },
                                onTogglePin: { viewModel.togglePin(item) },
                                onDelete: { viewModel.delete(item) }
                            )
                            .id(item.id)
                            .task(id: item.id) { await viewModel.loadThumbnail(for: item) }
                        }
                    }
                    .padding(AppTheme.Spacing.s)
                }
                .accessibilityIdentifier(AccessibilityID.Panel.list)
                .onChange(of: viewModel.selectedID) { _, selectedID in
                    guard let selectedID else { return }
                    proxy.scrollTo(selectedID)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if !viewModel.isAutoPasteAvailable {
                HStack(spacing: AppTheme.Spacing.s) {
                    Text("Auto-paste is off: picked items are copied, press ⌘V to paste.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Text.secondary)
                        .accessibilityIdentifier(AccessibilityID.Panel.autoPasteOffLabel)
                    Spacer()
                    Button("Enable") { viewModel.enableAutoPaste() }
                        .buttonStyle(.borderless)
                        .font(AppTheme.Typography.caption)
                        .accessibilityIdentifier(AccessibilityID.Panel.enableAutoPasteButton)
                }
            }
            Text("↩ Paste   ⌘1–9 Quick paste   ⌘P Pin   ⌘⌫ Delete   esc Close")
                .font(AppTheme.Typography.hint)
                .foregroundStyle(AppTheme.Text.secondary)
                .accessibilityIdentifier(AccessibilityID.Panel.hintsLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.l)
        .padding(.vertical, AppTheme.Spacing.s)
    }
}
