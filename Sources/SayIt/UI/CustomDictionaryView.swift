//
//  CustomDictionaryView.swift
//  SayIt
//
//  Dictionary page: replacements for words SayIt mishears, and custom words that
//  help Parakeet recognize names and terms.
//  Created: 2025-12-21
//

import SwiftUI

struct CustomDictionaryView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared

    @State private var entries: [SettingsStore.CustomDictionaryEntry] = SettingsStore.shared.customDictionaryEntries
    @State private var boostTerms: [ParakeetVocabularyStore.VocabularyConfig.Term] = []
    @State private var vocabBoostingEnabled: Bool = SettingsStore.shared.vocabularyBoostingEnabled
    @State private var boostError: String?

    @State private var replacementEditor: ReplacementEditor?
    @State private var wordEditor: WordEditor?
    @State private var pendingReplacementDeletion: SettingsStore.CustomDictionaryEntry?
    @State private var pendingWordDeletion: EditableBoostTerm?

    /// Skips disk reads for previews and snapshot tests.
    private let loadsFromDisk: Bool

    init() {
        self.loadsFromDisk = true
    }

    /// Renders the page with given content and never touches stored data.
    init(
        previewEntries: [SettingsStore.CustomDictionaryEntry],
        previewTerms: [ParakeetVocabularyStore.VocabularyConfig.Term],
        previewError: String? = nil
    ) {
        self.loadsFromDisk = false
        self._entries = State(initialValue: previewEntries)
        self._boostTerms = State(initialValue: previewTerms)
        self._boostError = State(initialValue: previewError)
    }

    var body: some View {
        SettingsKit.Page(
            title: "Dictionary",
            subtitle: "Teach SayIt the words you use: names, product terms and your own spellings."
        ) {
            self.replacementsSection
            self.customWordsSection
        }
        .sheet(item: self.$replacementEditor) { editor in
            ReplacementEditorSheet(
                entry: editor.entry,
                existingTriggers: self.allExistingTriggers(excluding: editor.entry?.id)
            ) { saved in
                if let index = self.entries.firstIndex(where: { $0.id == saved.id }) {
                    self.entries[index] = saved
                } else {
                    withMotion(Motion.state) { self.entries.append(saved) }
                }
                self.saveEntries()
            }
        }
        .sheet(item: self.$wordEditor) { editor in
            CustomWordEditorSheet(
                term: editor.existing?.term,
                existingTerms: self.existingBoostTerms(excludingIndex: editor.existing?.index)
            ) { saved in
                if let index = editor.existing?.index, self.boostTerms.indices.contains(index) {
                    self.boostTerms[index] = saved
                } else {
                    withMotion(Motion.state) { self.boostTerms.append(saved) }
                }
                self.saveBoostTerms()
            }
        }
        .confirmationDialog(
            self.pendingReplacementDeletion.map { "Delete the replacement for “\($0.replacement)”?" } ?? "",
            isPresented: Binding(
                get: { self.pendingReplacementDeletion != nil },
                set: { if !$0 { self.pendingReplacementDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: self.pendingReplacementDeletion
        ) { entry in
            Button("Delete Replacement", role: .destructive) {
                self.deleteEntry(entry)
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("SayIt will stop changing “\(entry.triggers.joined(separator: "”, “"))” to “\(entry.replacement)”.")
        }
        .confirmationDialog(
            self.pendingWordDeletion.map { "Delete “\($0.term.text)”?" } ?? "",
            isPresented: Binding(
                get: { self.pendingWordDeletion != nil },
                set: { if !$0 { self.pendingWordDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: self.pendingWordDeletion
        ) { editable in
            Button("Delete Word", role: .destructive) {
                self.deleteBoostTerm(at: editable.index)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Parakeet will no longer favor this word.")
        }
        .onAppear {
            guard self.loadsFromDisk else { return }
            self.loadBoostTerms()
        }
    }

    // MARK: - Replacements

    private var replacementsSection: some View {
        SettingsKit.Section(
            "Replacements",
            footer: "Works with every voice engine and doesn’t need AI. Matching ignores capitalization.",
            accessory: {
                // When empty, the empty state carries the add action instead.
                if !self.entries.isEmpty {
                    HStack(spacing: Space.sm) {
                        Text(CopyFormat.count(self.entries.count, "replacement"))
                            .font(AppFont.caption)
                            .foregroundStyle(self.theme.palette.secondaryText)
                        Button("Add Replacement…") {
                            self.replacementEditor = .new
                        }
                        .buttonStyle(.sayIt(.secondary, size: .small))
                    }
                }
            }
        ) {
            if self.entries.isEmpty {
                SettingsKit.EmptyState(
                    systemImage: "arrow.left.arrow.right",
                    title: "No replacements yet",
                    message: "When SayIt keeps writing a word wrong, add what it hears and how it should be written."
                ) {
                    Button("Add Replacement…") {
                        self.replacementEditor = .new
                    }
                    .buttonStyle(.sayItPrimary)
                }
            } else {
                self.columnHeader(leading: "Heard as", trailing: "Written as")
                ForEach(self.entries) { entry in
                    SettingsKit.RowDivider()
                    ReplacementRow(
                        entry: entry,
                        onEdit: { self.replacementEditor = .edit(entry) },
                        onDelete: { self.pendingReplacementDeletion = entry }
                    )
                    .motionTransition()
                }
            }
        }
        .motion(Motion.state, value: self.entries.count)
    }

    private func columnHeader(leading: String, trailing: String) -> some View {
        HStack(spacing: Space.md) {
            Text(leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: ReplacementRow.arrowWidth)
            Text(trailing)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: ReplacementRow.actionsWidth)
        }
        .font(AppFont.captionEmphasis)
        .foregroundStyle(self.theme.palette.secondaryText)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .accessibilityHidden(true)
    }

    // MARK: - Custom Words

    private var usesParakeet: Bool {
        self.settings.selectedSpeechModel == .parakeetTDT
    }

    private var customWordsSection: some View {
        SettingsKit.Section(
            "Custom Words",
            footer: "Spellings from Replacements are included automatically.",
            accessory: {
                if !self.boostTerms.isEmpty {
                    HStack(spacing: Space.sm) {
                        Text(CopyFormat.count(self.boostTerms.count, "word"))
                            .font(AppFont.caption)
                            .foregroundStyle(self.theme.palette.secondaryText)
                        Button("Add Word…") {
                            self.wordEditor = WordEditor(existing: nil)
                        }
                        .buttonStyle(.sayIt(.secondary, size: .small))
                    }
                }
            }
        ) {
            if !self.usesParakeet {
                SettingsKit.Notice(
                    .info,
                    title: "Custom words apply to Parakeet",
                    message: "You’re using \(self.settings.selectedSpeechModel.uiName). Your words are kept and take effect when you switch to Parakeet in Voice Engine."
                )
                .padding(Space.md)
            }

            if let boostError = self.boostError {
                SettingsKit.Notice(.error, title: "Custom words couldn’t be loaded or saved", message: boostError) {
                    Button("Try Again") { self.loadBoostTerms() }
                        .buttonStyle(.sayIt(.secondary, size: .small))
                }
                .padding(Space.md)
            }

            SettingsKit.ToggleRow(
                "Boost custom words",
                description: "Uses an extra on-device model so Parakeet picks your words more often. Turn it off if recognition gets worse.",
                systemImage: "dial.medium",
                isOn: self.$vocabBoostingEnabled
            )
            .onChange(of: self.vocabBoostingEnabled) { _, newValue in
                guard self.loadsFromDisk else { return }
                SettingsStore.shared.vocabularyBoostingEnabled = newValue
            }

            SettingsKit.RowDivider()

            if self.boostTerms.isEmpty {
                SettingsKit.EmptyState(
                    systemImage: "character.book.closed",
                    title: "No custom words yet",
                    message: "Add names, product terms and uncommon words so Parakeet recognizes them."
                ) {
                    Button("Add Word…") {
                        self.wordEditor = WordEditor(existing: nil)
                    }
                    .buttonStyle(.sayItPrimary)
                }
            } else {
                ForEach(Array(self.boostTerms.enumerated()), id: \.offset) { index, term in
                    if index > 0 {
                        SettingsKit.RowDivider()
                    }
                    CustomWordRow(
                        term: term,
                        onEdit: { self.wordEditor = WordEditor(existing: EditableBoostTerm(index: index, term: term)) },
                        onDelete: { self.pendingWordDeletion = EditableBoostTerm(index: index, term: term) }
                    )
                }
            }
        }
        .motion(Motion.state, value: self.boostTerms.count)
    }

    // MARK: - Actions

    private func saveEntries() {
        guard self.loadsFromDisk else { return }
        SettingsStore.shared.customDictionaryEntries = self.entries
        // Invalidate cached regex patterns so changes take effect immediately
        ASRService.invalidateDictionaryCache()
        NotificationCenter.default.post(name: .parakeetVocabularyDidChange, object: nil)
    }

    private func loadBoostTerms() {
        do {
            self.boostTerms = try ParakeetVocabularyStore.shared.loadUserBoostTerms()
            self.boostError = nil
        } catch {
            self.boostTerms = []
            self.boostError = error.localizedDescription
        }
    }

    private func saveBoostTerms() {
        guard self.loadsFromDisk else { return }
        do {
            try ParakeetVocabularyStore.shared.saveUserBoostTerms(self.boostTerms)
            self.boostError = nil
        } catch {
            self.boostError = error.localizedDescription
        }
    }

    private func deleteBoostTerm(at index: Int) {
        guard self.boostTerms.indices.contains(index) else { return }
        withMotion(Motion.state) {
            _ = self.boostTerms.remove(at: index)
        }
        self.saveBoostTerms()
    }

    private func deleteEntry(_ entry: SettingsStore.CustomDictionaryEntry) {
        withMotion(Motion.state) {
            self.entries.removeAll { $0.id == entry.id }
        }
        self.saveEntries()
    }

    /// Returns all existing trigger words for duplicate detection
    private func allExistingTriggers(excluding entryId: UUID? = nil) -> Set<String> {
        var triggers = Set<String>()
        for entry in self.entries where entry.id != entryId {
            for trigger in entry.triggers {
                triggers.insert(trigger.lowercased())
            }
        }
        return triggers
    }

    private func existingBoostTerms(excludingIndex: Int? = nil) -> Set<String> {
        var terms: Set<String> = []
        for (index, term) in self.boostTerms.enumerated() where index != excludingIndex {
            terms.insert(term.text.lowercased())
        }
        return terms
    }
}

// MARK: - Editor Identity

private enum ReplacementEditor: Identifiable {
    case new
    case edit(SettingsStore.CustomDictionaryEntry)

    var id: String {
        switch self {
        case .new: return "new"
        case let .edit(entry): return entry.id.uuidString
        }
    }

    var entry: SettingsStore.CustomDictionaryEntry? {
        if case let .edit(entry) = self { return entry }
        return nil
    }
}

private struct WordEditor: Identifiable {
    let id = UUID()
    let existing: EditableBoostTerm?
}

private struct EditableBoostTerm: Identifiable {
    let id = UUID()
    let index: Int
    let term: ParakeetVocabularyStore.VocabularyConfig.Term
}

private enum BoostStrengthPreset: String, CaseIterable, Identifiable {
    case mild = "Mild"
    case balanced = "Balanced"
    case strong = "Strong"

    var id: String { self.rawValue }

    var weight: Float {
        switch self {
        case .mild: return 5.0
        case .balanced: return 10.0
        case .strong: return 13.0
        }
    }

    var hint: String {
        switch self {
        case .mild: return "A light nudge with minimal impact."
        case .balanced: return "The best default for most names and product terms."
        case .strong: return "For words that should win more often in noisy audio."
        }
    }

    static func nearest(for weight: Float) -> Self {
        if weight < 8.5 { return .mild }
        if weight > 11.5 { return .strong }
        return .balanced
    }
}

// MARK: - Rows

private struct ReplacementRow: View {
    static let arrowWidth: CGFloat = 16
    static let actionsWidth: CGFloat = 60

    let entry: SettingsStore.CustomDictionaryEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: Space.md) {
            FlowLayout(spacing: Space.xs) {
                ForEach(self.entry.triggers, id: \.self) { trigger in
                    HeardChip(text: trigger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(AppFont.iconSmall)
                .foregroundStyle(self.theme.palette.tertiaryText)
                .frame(width: Self.arrowWidth)
                .accessibilityHidden(true)

            Text(self.entry.replacement)
                .font(AppFont.transcript)
                .foregroundStyle(self.theme.palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            HStack(spacing: Space.xxs) {
                IconButton("Edit replacement for \(self.entry.replacement)", systemName: "pencil", action: self.onEdit)
                IconButton("Delete replacement for \(self.entry.replacement)", systemName: "trash", role: .destructive, action: self.onDelete)
            }
            .frame(width: Self.actionsWidth, alignment: .trailing)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Heard as \(self.entry.triggers.joined(separator: ", ")), written as \(self.entry.replacement)")
    }
}

private struct HeardChip: View {
    @Environment(\.theme) private var theme
    let text: String
    var highlighted = false

    var body: some View {
        Text(self.text)
            .font(AppFont.callout)
            .foregroundStyle(self.theme.palette.secondaryText)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xxs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(self.highlighted ? self.theme.palette.subtle(self.theme.palette.warning) : self.theme.palette.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(self.highlighted ? self.theme.palette.warning : self.theme.palette.hairline, lineWidth: 1)
            )
    }
}

private struct CustomWordRow: View {
    let term: ParakeetVocabularyStore.VocabularyConfig.Term
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: Space.md) {
            Text(self.term.text)
                .font(AppFont.transcript)
                .foregroundStyle(self.theme.palette.primaryText)
                .textSelection(.enabled)

            Spacer(minLength: Space.sm)

            if let weight = self.term.weight {
                SettingsKit.Chip(text: "\(BoostStrengthPreset.nearest(for: weight).rawValue) priority")
            }

            HStack(spacing: Space.xxs) {
                IconButton("Edit \(self.term.text)", systemName: "pencil", action: self.onEdit)
                IconButton("Delete \(self.term.text)", systemName: "trash", role: .destructive, action: self.onDelete)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
    }
}

// MARK: - Editor Sheets

private enum EditorSheetLayout {
    static let width: CGFloat = 460
    static let minHeight: CGFloat = 300
}

/// A labelled field with help text, shared by the editor sheets.
private struct EditorField<Field: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let help: String
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(self.title)
                .font(AppFont.rowTitle)
                .foregroundStyle(self.theme.palette.primaryText)
            self.field
            Text(self.help)
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ReplacementEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let entry: SettingsStore.CustomDictionaryEntry?
    let existingTriggers: Set<String>
    let onSave: (SettingsStore.CustomDictionaryEntry) -> Void

    @State private var triggersText = ""
    @State private var replacement = ""

    private var triggers: [String] {
        self.triggersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    private var duplicateTriggers: [String] {
        self.triggers.filter { self.existingTriggers.contains($0) }
    }

    private var trimmedReplacement: String {
        self.replacement.trimmingCharacters(in: .whitespaces)
    }

    private var canSave: Bool {
        !self.triggers.isEmpty && !self.trimmedReplacement.isEmpty && self.duplicateTriggers.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(self.entry == nil ? "Add Replacement" : "Edit Replacement")
                .font(AppFont.pageTitle)
                .foregroundStyle(self.theme.palette.primaryText)

            EditorField(
                title: "Heard as",
                help: "What SayIt writes by mistake. Separate variations with commas."
            ) {
                TextField(AppIdentity.defaultDictionaryAliasesDisplay, text: self.$triggersText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { self.saveIfValid() }
            }

            EditorField(title: "Written as", help: "How it should appear in your text.") {
                TextField(AppIdentity.displayName, text: self.$replacement)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { self.saveIfValid() }
            }

            if !self.duplicateTriggers.isEmpty {
                SettingsKit.Notice(
                    .warning,
                    title: "Already in another replacement",
                    message: self.duplicateTriggers.map { "“\($0)”" }.joined(separator: ", ")
                )
            }

            if !self.triggers.isEmpty, !self.trimmedReplacement.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Preview")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(self.theme.palette.secondaryText)
                    FlowLayout(spacing: Space.xs) {
                        ForEach(self.triggers, id: \.self) { trigger in
                            HeardChip(text: trigger, highlighted: self.duplicateTriggers.contains(trigger))
                        }
                        Image(systemName: "arrow.right")
                            .font(AppFont.iconSmall)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                            .padding(.vertical, Space.xs)
                        Text(self.trimmedReplacement)
                            .font(AppFont.transcript)
                            .foregroundStyle(self.theme.palette.primaryText)
                    }
                }
                .padding(Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(self.theme.palette.surfaceSunken)
                )
            }

            Spacer(minLength: 0)

            HStack(spacing: Space.sm) {
                Spacer()
                Button("Cancel") { self.dismiss() }
                    .buttonStyle(.sayItSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(self.entry == nil ? "Add Replacement" : "Save Changes") { self.saveIfValid() }
                    .buttonStyle(.sayItPrimary)
                    .disabled(!self.canSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: EditorSheetLayout.width)
        .frame(minHeight: EditorSheetLayout.minHeight)
        .background(self.theme.palette.surface)
        .onAppear {
            if let entry = self.entry {
                self.triggersText = entry.triggers.joined(separator: ", ")
                self.replacement = entry.replacement
            }
        }
    }

    private func saveIfValid() {
        guard self.canSave else { return }
        let saved = SettingsStore.CustomDictionaryEntry(
            id: self.entry?.id ?? UUID(),
            triggers: self.triggers,
            replacement: self.trimmedReplacement
        )
        self.onSave(saved)
        self.dismiss()
    }
}

struct CustomWordEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let term: ParakeetVocabularyStore.VocabularyConfig.Term?
    let existingTerms: Set<String>
    let onSave: (ParakeetVocabularyStore.VocabularyConfig.Term) -> Void

    @State private var termText = ""
    @State private var strength: BoostStrengthPreset = .balanced

    private var normalizedTerm: String {
        self.termText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        self.existingTerms.contains(self.normalizedTerm.lowercased())
    }

    private var canSave: Bool {
        !self.normalizedTerm.isEmpty && !self.isDuplicate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(self.term == nil ? "Add Custom Word" : "Edit Custom Word")
                .font(AppFont.pageTitle)
                .foregroundStyle(self.theme.palette.primaryText)

            EditorField(title: "Word or phrase", help: "Spell it exactly as it should appear.") {
                TextField(AppIdentity.displayName, text: self.$termText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { self.saveIfValid() }
            }

            EditorField(title: "Priority", help: self.strength.hint) {
                Picker("Priority", selection: self.$strength) {
                    ForEach(BoostStrengthPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if self.isDuplicate {
                SettingsKit.Notice(.warning, title: "“\(self.normalizedTerm)” is already a custom word")
            }

            Spacer(minLength: 0)

            HStack(spacing: Space.sm) {
                Spacer()
                Button("Cancel") { self.dismiss() }
                    .buttonStyle(.sayItSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(self.term == nil ? "Add Word" : "Save Changes") { self.saveIfValid() }
                    .buttonStyle(.sayItPrimary)
                    .disabled(!self.canSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: EditorSheetLayout.width)
        .frame(minHeight: EditorSheetLayout.minHeight)
        .background(self.theme.palette.surface)
        .onAppear {
            if let term = self.term {
                self.termText = term.text
                self.strength = BoostStrengthPreset.nearest(for: term.weight ?? BoostStrengthPreset.balanced.weight)
            } else {
                self.termText = ""
                self.strength = .balanced
            }
        }
    }

    private func saveIfValid() {
        guard self.canSave else { return }
        self.onSave(
            ParakeetVocabularyStore.VocabularyConfig.Term(
                text: self.normalizedTerm,
                weight: self.strength.weight,
                aliases: self.term?.aliases ?? []
            )
        )
        self.dismiss()
    }
}
