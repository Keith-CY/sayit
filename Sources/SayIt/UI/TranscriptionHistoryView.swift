import SwiftUI

struct TranscriptionHistoryView: View {
    @ObservedObject private var historyStore: TranscriptionHistoryStore
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.theme) private var theme
    @Environment(\.undoManager) private var undoManager

    @State private var searchQuery: String = ""
    @State private var showClearConfirmation = false
    @State private var selectedEntryID: UUID?
    @State private var recentlyDeleted: DeletedEntry?
    @State private var toastTask: Task<Void, Never>?

    private struct DeletedEntry: Equatable {
        let entry: TranscriptionHistoryEntry
        let index: Int
    }

    /// Sidebar (220) + list (240) + detail (320) stays within the 800pt minimum window.
    private static let listMinWidth: CGFloat = 240
    private static let listIdealWidth: CGFloat = 300
    private static let listMaxWidth: CGFloat = 380
    private static let detailMinWidth: CGFloat = 320

    init() {
        self.init(historyStore: .shared)
    }

    init(historyStore: TranscriptionHistoryStore) {
        _historyStore = ObservedObject(wrappedValue: historyStore)
    }

    private var filteredEntries: [TranscriptionHistoryEntry] {
        self.historyStore.search(query: self.searchQuery)
    }

    private var selectedEntry: TranscriptionHistoryEntry? {
        guard let id = self.selectedEntryID else { return nil }
        return self.filteredEntries.first(where: { $0.id == id })
    }

    var body: some View {
        Group {
            if self.historyStore.entries.isEmpty {
                // Nothing to list or select: one calm, full-page empty state.
                self.emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    self.listPane
                        .frame(minWidth: Self.listMinWidth, idealWidth: Self.listIdealWidth, maxWidth: Self.listMaxWidth)

                    self.detailPane
                        .frame(minWidth: Self.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(self.theme.palette.contentBackground)
        .overlay(alignment: .bottom) {
            if let deleted = self.recentlyDeleted {
                ActivityUI.Toast("Dictation deleted") {
                    Button("Undo") { self.undoDelete(deleted) }
                        .buttonStyle(.sayIt(.quiet, size: .small))
                        .keyboardShortcut("z", modifiers: .command)
                }
                .padding(.bottom, Space.lg)
                .motionTransition()
            }
        }
        .onAppear {
            if self.selectedEntryID == nil {
                self.selectedEntryID = self.filteredEntries.first?.id
            }
        }
        .onChange(of: self.searchQuery) { _, _ in
            if self.selectedEntry == nil {
                self.selectedEntryID = self.filteredEntries.first?.id
            }
        }
        .confirmationDialog(
            "Clear all history?",
            isPresented: self.$showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                withMotion(Motion.exit) {
                    self.historyStore.clearAllHistory()
                    self.selectedEntryID = nil
                    self.recentlyDeleted = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes \(CopyFormat.count(self.historyStore.entries.count, "dictation")) and resets your stats. This can’t be undone.")
        }
    }

    // MARK: - List Pane

    private var listPane: some View {
        VStack(spacing: 0) {
            self.searchField
                .padding(Space.md)

            if !self.settings.saveTranscriptionHistory, !self.historyStore.entries.isEmpty {
                self.historyOffNotice
                    .padding(.horizontal, Space.md)
                    .padding(.bottom, Space.sm)
            }

            Divider()

            if self.filteredEntries.isEmpty {
                self.emptyState
                    .frame(maxHeight: .infinity)
            } else {
                self.entryList
            }

            Divider()
            self.footer
        }
        .background(self.theme.palette.sidebarBackground.opacity(0.4))
    }

    private var searchField: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.iconSmall)
                .foregroundStyle(self.theme.palette.secondaryText)
                .accessibilityHidden(true)

            TextField("Search dictations", text: self.$searchQuery)
                .textFieldStyle(.plain)
                .font(AppFont.body)
                .accessibilityLabel("Search dictations")

            if !self.searchQuery.isEmpty {
                IconButton("Clear Search", systemName: "xmark.circle.fill", size: Space.lg + Space.xs) {
                    self.searchQuery = ""
                }
            }
        }
        .padding(.horizontal, Space.sm + Space.xxs)
        .padding(.vertical, Space.sm - Space.xxs)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(self.theme.palette.surfaceSunken)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
        )
    }

    private var historyOffNotice: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "pause.circle")
                .foregroundStyle(self.theme.palette.secondaryText)
                .accessibilityHidden(true)
            Text("History is off. New dictations aren’t saved.")
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Turn On") {
                self.settings.saveTranscriptionHistory = true
            }
            .buttonStyle(.sayIt(.quiet, size: .small))
        }
    }

    private var entryList: some View {
        List(selection: self.$selectedEntryID) {
            ForEach(self.filteredEntries) { entry in
                HistoryRow(entry: entry)
                    .tag(entry.id)
                    .contextMenu { self.contextMenu(for: entry) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .onDeleteCommand {
            if let entry = self.selectedEntry {
                self.delete(entry)
            }
        }
        .onCopyCommand {
            guard let entry = self.selectedEntry else { return [] }
            return [NSItemProvider(object: entry.processedText as NSString)]
        }
        .accessibilityLabel("Dictations")
    }

    @ViewBuilder
    private func contextMenu(for entry: TranscriptionHistoryEntry) -> some View {
        Button("Copy") { ActivityUI.copyToPasteboard(entry.processedText) }
        if entry.wasAIProcessed {
            Button("Copy Original") { ActivityUI.copyToPasteboard(entry.rawText) }
        }
        Divider()
        Button("Delete", role: .destructive) { self.delete(entry) }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !self.searchQuery.isEmpty {
            ActivityUI.EmptyState(
                systemImage: "magnifyingglass",
                title: "No Results",
                message: "Nothing matches “\(self.searchQuery)”. Try another word or an app name."
            )
        } else if !self.settings.saveTranscriptionHistory {
            ActivityUI.EmptyState(
                systemImage: "pause.circle",
                title: "History Is Off",
                message: "SayIt isn’t saving dictations. Turn on history to review past dictations and see your stats."
            ) {
                Button("Turn On History") {
                    self.settings.saveTranscriptionHistory = true
                }
                .buttonStyle(.sayIt(.primary, size: .small))
            }
        } else {
            ActivityUI.EmptyState(
                systemImage: "clock.arrow.circlepath",
                title: "No Dictations Yet",
                message: "Everything you dictate with SayIt is listed here, newest first."
            )
        }
    }

    private var footer: some View {
        HStack(spacing: Space.sm) {
            Text(self.footerSummary)
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
            Spacer()
            if !self.historyStore.entries.isEmpty {
                Button("Clear All…") {
                    self.showClearConfirmation = true
                }
                .buttonStyle(.sayIt(.destructive, size: .small))
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
    }

    private var footerSummary: String {
        let total = self.historyStore.entries.count
        guard !self.searchQuery.isEmpty else {
            return CopyFormat.count(total, "dictation")
        }
        return "\(self.filteredEntries.count.formatted()) of \(CopyFormat.count(total, "dictation"))"
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if let entry = self.selectedEntry {
            HistoryDetail(entry: entry) {
                self.delete(entry)
            }
            .id(entry.id)
        } else if !self.filteredEntries.isEmpty {
            ActivityUI.EmptyState(
                systemImage: "text.quote",
                title: "Select a Dictation",
                message: "Choose a dictation on the left to read it in full."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    // MARK: - Delete & Undo

    private func delete(_ entry: TranscriptionHistoryEntry) {
        guard let index = self.historyStore.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let visible = self.filteredEntries
        let position = visible.firstIndex(where: { $0.id == entry.id }) ?? 0
        let nextSelection = visible.indices.contains(position + 1)
            ? visible[position + 1].id
            : (position > 0 ? visible[position - 1].id : nil)

        withMotion(Motion.state) {
            self.historyStore.deleteEntry(id: entry.id)
            self.selectedEntryID = nextSelection
            self.recentlyDeleted = DeletedEntry(entry: entry, index: index)
        }

        let store = self.historyStore
        self.undoManager?.registerUndo(withTarget: store) { store in
            store.restoreEntry(entry, at: index)
        }
        self.undoManager?.setActionName("Delete Dictation")

        self.toastTask?.cancel()
        self.toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withMotion(Motion.exit) { self.recentlyDeleted = nil }
        }
    }

    private func undoDelete(_ deleted: DeletedEntry) {
        if let undoManager = self.undoManager, undoManager.canUndo {
            undoManager.undo()
        } else {
            self.historyStore.restoreEntry(deleted.entry, at: deleted.index)
        }
        self.toastTask?.cancel()
        withMotion(Motion.state) {
            self.selectedEntryID = deleted.entry.id
            self.recentlyDeleted = nil
        }
    }
}

// MARK: - Row

private struct HistoryRow: View {
    @Environment(\.theme) private var theme
    let entry: TranscriptionHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Text(self.entry.appName.isEmpty ? "Unknown App" : self.entry.appName)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if self.entry.wasAIProcessed {
                    Image(systemName: "sparkles")
                        .font(AppFont.micro)
                        .foregroundStyle(.secondary)
                        .help("Enhanced")
                        .accessibilityLabel("Enhanced")
                }
                Spacer(minLength: Space.xs)
                Text(self.entry.relativeTimeString)
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(self.entry.previewText)
                .font(AppFont.transcript)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

private struct HistoryDetail: View {
    @Environment(\.theme) private var theme

    let entry: TranscriptionHistoryEntry
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(self.entry.appName.isEmpty ? "Unknown App" : self.entry.appName)
                            .font(AppFont.pageTitle)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text(self.entry.fullDateString)
                            .font(AppFont.callout)
                            .foregroundStyle(self.theme.palette.secondaryText)
                    }
                    Spacer(minLength: Space.md)
                    ActivityUI.CopyButton(text: self.entry.processedText)
                    IconButton("Delete Dictation", systemName: "trash", role: .destructive, action: self.onDelete)
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(spacing: Space.sm) {
                        Text(self.entry.wasAIProcessed ? "Final Text" : "Text")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(self.theme.palette.secondaryText)
                        if self.entry.wasAIProcessed {
                            ActivityUI.Badge(text: "Enhanced", systemImage: "sparkles")
                        }
                    }
                    ActivityUI.TranscriptBlock(text: self.entry.processedText, large: true)
                }

                if self.entry.wasAIProcessed {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack {
                            Text("Original Transcription")
                                .font(AppFont.captionEmphasis)
                                .foregroundStyle(self.theme.palette.secondaryText)
                            Spacer()
                            ActivityUI.CopyButton(text: self.entry.rawText, title: "Copy Original")
                        }
                        ActivityUI.TranscriptBlock(text: self.entry.rawText, emphasis: false)
                    }
                }

                Divider()

                Grid(alignment: .topLeading, horizontalSpacing: Space.xl, verticalSpacing: Space.lg) {
                    GridRow {
                        ActivityUI.LabeledValue(
                            label: "Application",
                            value: self.entry.appName.isEmpty ? "Unknown" : self.entry.appName,
                            systemImage: "app"
                        )
                        ActivityUI.LabeledValue(
                            label: "Window",
                            value: self.entry.windowTitle.isEmpty ? "Unknown" : self.entry.windowTitle,
                            systemImage: "macwindow"
                        )
                    }
                    GridRow {
                        ActivityUI.LabeledValue(
                            label: "Length",
                            value: "\(CopyFormat.count(self.entry.wordCount, "word")) · \(CopyFormat.count(self.entry.characterCount, "character"))",
                            systemImage: "textformat.size"
                        )
                        ActivityUI.LabeledValue(
                            label: "AI Enhancement",
                            value: self.entry.wasAIProcessed ? "Applied" : "Not applied",
                            systemImage: "sparkles"
                        )
                    }
                }
            }
            .padding(Space.xxl)
            .frame(maxWidth: ActivityUI.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(self.theme.palette.contentBackground)
    }
}

#Preview {
    TranscriptionHistoryView()
        .frame(width: 800, height: 600)
        .sayItTheme()
}
