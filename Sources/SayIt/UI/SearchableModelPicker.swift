//
//  SearchableModelPicker.swift
//  SayIt
//
//  A searchable picker for selecting AI models.
//  Uses a popover with search field for better UX.
//

import SwiftUI

enum PickerLayout {
    static let defaultControlHeight: CGFloat = 28
    static let popoverWidth: CGFloat = 300
    static let popoverListMaxHeight: CGFloat = 260
    static let maxVisibleOptions = 100
}

struct SearchableModelPicker: View {
    @Environment(\.theme) private var theme
    let models: [String]
    @Binding var selectedModel: String
    var onRefresh: (() async -> Void)?
    var isRefreshing: Bool = false
    var refreshEnabled: Bool = true
    var selectionEnabled: Bool = true
    let controlWidth: CGFloat
    let controlHeight: CGFloat?

    init(
        models: [String],
        selectedModel: Binding<String>,
        onRefresh: (() async -> Void)? = nil,
        isRefreshing: Bool = false,
        refreshEnabled: Bool = true,
        selectionEnabled: Bool = true,
        controlWidth: CGFloat = 180,
        controlHeight: CGFloat? = nil
    ) {
        self.models = models
        self._selectedModel = selectedModel
        self.onRefresh = onRefresh
        self.isRefreshing = isRefreshing
        self.refreshEnabled = refreshEnabled
        self.selectionEnabled = selectionEnabled
        self.controlWidth = controlWidth
        self.controlHeight = controlHeight
    }

    @State private var searchText = ""
    @State private var isShowingPopover = false

    private var filteredModels: [String] {
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return self.models }
        return self.models.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            Button(action: { self.isShowingPopover.toggle() }) {
                PickerFieldLabel(
                    text: self.selectedModel,
                    placeholder: "Choose a Model",
                    isMonospaced: true,
                    width: self.controlWidth,
                    height: self.controlHeight ?? PickerLayout.defaultControlHeight
                )
            }
            .buttonStyle(.plain)
            .disabled(!self.selectionEnabled)
            .opacity(self.selectionEnabled ? 1 : 0.45)
            .help(self.selectedModel.isEmpty ? "Choose a model" : self.selectedModel)
            .accessibilityLabel("Model")
            .accessibilityValue(self.selectedModel.isEmpty ? "None selected" : self.selectedModel)
            .accessibilityHint("Shows the available models")
            .popover(isPresented: self.$isShowingPopover, arrowEdge: .bottom) {
                self.popoverContent
            }

            if let onRefresh {
                if self.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: PickerLayout.defaultControlHeight, height: PickerLayout.defaultControlHeight)
                        .accessibilityLabel("Refreshing models")
                } else {
                    IconButton("Refresh Models", systemName: "arrow.clockwise", size: PickerLayout.defaultControlHeight) {
                        Task { await onRefresh() }
                    }
                    .disabled(!self.refreshEnabled)
                }
            }
        }
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            PickerSearchField(placeholder: "Search models", text: self.$searchText) {
                if let first = self.filteredModels.first { self.select(first) }
            }

            Divider()

            if self.models.isEmpty {
                PickerEmptyState(
                    symbol: "tray",
                    title: "No Models Yet",
                    message: self.onRefresh == nil
                        ? "This provider hasn’t listed any models."
                        : "Refresh the list to load models from the provider."
                )
            } else if self.filteredModels.isEmpty {
                PickerEmptyState(
                    symbol: "magnifyingglass",
                    title: "No Matches",
                    message: "No models match “\(self.searchText)”."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(self.filteredModels.prefix(PickerLayout.maxVisibleOptions), id: \.self) { model in
                            PickerOptionRow(title: model, isSelected: model == self.selectedModel, isMonospaced: true) {
                                self.select(model)
                            }
                        }
                    }
                    .padding(Space.xs)
                }
                .frame(maxHeight: PickerLayout.popoverListMaxHeight)

                let hidden = self.filteredModels.count - PickerLayout.maxVisibleOptions
                if hidden > 0 {
                    Divider()
                    Text("\(CopyFormat.count(hidden, "more model")) — refine your search to see them.")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .padding(Space.sm)
                }
            }
        }
        .frame(width: PickerLayout.popoverWidth)
    }

    private func select(_ model: String) {
        self.selectedModel = model
        self.searchText = ""
        self.isShowingPopover = false
    }
}

// MARK: - Shared Picker Parts

/// The closed state of a searchable picker: reads like a native pop-up button.
struct PickerFieldLabel: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false
    let text: String
    let placeholder: String
    var isMonospaced = false
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        HStack(spacing: Space.sm) {
            Text(self.text.isEmpty ? self.placeholder : self.text)
                .font(self.isMonospaced && !self.text.isEmpty ? AppFont.mono : AppFont.callout)
                .foregroundStyle(self.text.isEmpty ? self.theme.palette.secondaryText : self.theme.palette.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Space.xs)
            Image(systemName: "chevron.up.chevron.down")
                .font(AppFont.iconSmall)
                .foregroundStyle(self.theme.palette.tertiaryText)
        }
        .padding(.horizontal, Space.sm + Space.xxs)
        .frame(width: self.width, height: self.height, alignment: .leading)
        .background(shape.fill(self.isHovered ? self.theme.palette.surfaceHover : self.theme.palette.surfaceSunken))
        .overlay(shape.strokeBorder(self.theme.palette.hairline, lineWidth: 1))
        .contentShape(shape)
        .onHover { self.isHovered = $0 }
        .motion(Motion.snappy, value: self.isHovered)
    }
}

struct PickerSearchField: View {
    @Environment(\.theme) private var theme
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(self.theme.palette.tertiaryText)
                .accessibilityHidden(true)
            TextField(self.placeholder, text: self.$text, prompt: Text(self.placeholder))
                .textFieldStyle(.plain)
                .font(AppFont.body)
                .labelsHidden()
                .onSubmit(self.onSubmit)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm + Space.xxs)
    }
}

struct PickerOptionRow: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false
    let title: String
    let isSelected: Bool
    var isMonospaced = false
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: Space.sm) {
                Text(self.title)
                    .font(self.isMonospaced ? AppFont.mono : AppFont.body)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Space.sm)
                if self.isSelected {
                    Image(systemName: "checkmark")
                        .font(AppFont.iconSmall)
                        .foregroundStyle(self.theme.palette.accentForeground)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Space.sm + Space.xxs)
            .padding(.vertical, Space.xs + Space.xxs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(self.isHovered ? self.theme.palette.surfaceHover : (self.isSelected ? self.theme.palette.accentSubtle : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
        .accessibilityAddTraits(self.isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct PickerEmptyState: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: self.symbol)
                .font(AppFont.iconLarge)
                .foregroundStyle(self.theme.palette.tertiaryText)
                .accessibilityHidden(true)
            Text(self.title)
                .font(AppFont.rowTitle)
                .foregroundStyle(self.theme.palette.primaryText)
            Text(self.message)
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SearchableModelPicker(
        models: ["gpt-4.1", "gpt-4o", "gpt-3.5-turbo", "claude-3-opus", "claude-3-sonnet"],
        selectedModel: .constant("gpt-4.1"),
        onRefresh: { try? await Task.sleep(nanoseconds: 1_000_000_000) },
        isRefreshing: false
    )
    .padding()
    .sayItTheme()
}
