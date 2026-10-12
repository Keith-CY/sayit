//
//  SearchableProviderPicker.swift
//  SayIt
//
//  A searchable picker for selecting AI providers.
//  Uses a popover with search field for better UX when there are many providers.
//

import SwiftUI

struct SearchableProviderPicker: View {
    @Environment(\.theme) private var theme
    let builtInProviders: [(id: String, name: String)]
    let savedProviders: [SettingsStore.SavedProvider]
    @Binding var selectedProviderID: String
    let controlWidth: CGFloat
    let controlHeight: CGFloat?

    init(
        builtInProviders: [(id: String, name: String)],
        savedProviders: [SettingsStore.SavedProvider],
        selectedProviderID: Binding<String>,
        controlWidth: CGFloat = 180,
        controlHeight: CGFloat? = nil
    ) {
        self.builtInProviders = builtInProviders
        self.savedProviders = savedProviders
        self._selectedProviderID = selectedProviderID
        self.controlWidth = controlWidth
        self.controlHeight = controlHeight
    }

    @State private var searchText = ""
    @State private var isShowingPopover = false

    private struct Option: Identifiable {
        let id: String
        let name: String
        let isBuiltIn: Bool
    }

    private var allProviders: [Option] {
        self.builtInProviders.map { Option(id: $0.id, name: $0.name, isBuiltIn: true) } +
            self.savedProviders.map { Option(id: $0.id, name: $0.name, isBuiltIn: false) }
    }

    private var filteredProviders: [Option] {
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return self.allProviders }
        return self.allProviders.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedProviderName: String {
        self.allProviders.first(where: { $0.id == self.selectedProviderID })?.name ?? self.selectedProviderID
    }

    var body: some View {
        Button(action: { self.isShowingPopover.toggle() }) {
            PickerFieldLabel(
                text: self.selectedProviderName,
                placeholder: "Choose a Provider",
                width: self.controlWidth,
                height: self.controlHeight ?? PickerLayout.defaultControlHeight
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Provider")
        .accessibilityValue(self.selectedProviderName.isEmpty ? "None selected" : self.selectedProviderName)
        .accessibilityHint("Shows the available providers")
        .popover(isPresented: self.$isShowingPopover, arrowEdge: .bottom) {
            self.popoverContent
        }
    }

    private var popoverContent: some View {
        let builtIns = self.filteredProviders.filter(\.isBuiltIn)
        let saved = self.filteredProviders.filter { !$0.isBuiltIn }

        return VStack(spacing: 0) {
            PickerSearchField(placeholder: "Search providers", text: self.$searchText) {
                if let first = self.filteredProviders.first { self.select(first.id) }
            }

            Divider()

            if self.filteredProviders.isEmpty {
                PickerEmptyState(
                    symbol: "magnifyingglass",
                    title: "No Matches",
                    message: "No providers match “\(self.searchText)”."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !builtIns.isEmpty {
                            self.sectionHeader("Built-in")
                            ForEach(builtIns) { provider in
                                PickerOptionRow(title: provider.name, isSelected: provider.id == self.selectedProviderID) {
                                    self.select(provider.id)
                                }
                            }
                        }
                        if !saved.isEmpty {
                            self.sectionHeader("Custom")
                            ForEach(saved) { provider in
                                PickerOptionRow(title: provider.name, isSelected: provider.id == self.selectedProviderID) {
                                    self.select(provider.id)
                                }
                            }
                        }
                    }
                    .padding(Space.xs)
                }
                .frame(maxHeight: PickerLayout.popoverListMaxHeight)
            }
        }
        .frame(width: PickerLayout.popoverWidth)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppFont.captionEmphasis)
            .foregroundStyle(self.theme.palette.tertiaryText)
            .padding(.horizontal, Space.sm + Space.xxs)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private func select(_ providerID: String) {
        self.selectedProviderID = providerID
        self.searchText = ""
        self.isShowingPopover = false
    }
}

#Preview {
    SearchableProviderPicker(
        builtInProviders: [
            ("openai", "OpenAI"),
            ("groq", "Groq"),
            ("cerebras", "Cerebras"),
        ],
        savedProviders: [],
        selectedProviderID: .constant("openai")
    )
    .padding()
    .sayItTheme()
}
