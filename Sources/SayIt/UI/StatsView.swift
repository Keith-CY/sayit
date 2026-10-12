import Charts
import SwiftUI

struct StatsView: View {
    @ObservedObject private var historyStore: TranscriptionHistoryStore
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.theme) private var theme

    @State private var showClearConfirmation = false
    @State private var showWPMEditor = false
    @State private var chartRange: ChartRange = .week

    init() {
        self.init(historyStore: .shared)
    }

    init(historyStore: TranscriptionHistoryStore) {
        _historyStore = ObservedObject(wrappedValue: historyStore)
    }

    enum ChartRange: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30

        var id: Int { self.rawValue }

        var title: String {
            switch self {
            case .week: return "Last 7 Days"
            case .month: return "Last 30 Days"
            }
        }
    }

    var body: some View {
        ActivityUI.Page("Stats", subtitle: "What you’ve written by voice, and the time it saved you.") {
            if !self.settings.saveTranscriptionHistory {
                self.historyOffBanner
            }

            if self.historyStore.entries.isEmpty {
                ThemedCard {
                    ActivityUI.EmptyState(
                        systemImage: "chart.bar",
                        title: "No Stats Yet",
                        message: "Stats are calculated from your dictation history. Dictate something and it shows up here."
                    )
                }
            } else {
                self.summaryCard
                self.activityCard
                self.insightsCard
                self.milestonesCard
                self.recordsCard
                self.clearSection
            }
        }
    }

    // MARK: - History Off

    private var historyOffBanner: some View {
        ActivityUI.Banner(
            .info,
            title: "History is off",
            message: "New dictations aren’t saved, so your stats won’t change."
        ) {
            Button("Turn On History") {
                self.settings.saveTranscriptionHistory = true
            }
            .buttonStyle(.sayIt(.secondary, size: .small))
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        ThemedCard(style: .prominent) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Space.xxl) {
                    self.timeSavedBlock
                    Divider().frame(height: Self.summaryDividerHeight)
                    self.summaryMetrics
                }
                VStack(alignment: .leading, spacing: Space.xl) {
                    self.timeSavedBlock
                    Divider()
                    self.summaryMetrics
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let summaryDividerHeight: CGFloat = 64

    private var timeSavedBlock: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Time Saved")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(self.theme.palette.secondaryText)
            Text(self.historyStore.formattedTimeSaved(typingWPM: self.settings.userTypingWPM))
                .font(AppFont.metric)
                .foregroundStyle(self.theme.palette.primaryText)
                .contentTransition(.numericText())
            HStack(spacing: Space.xs) {
                Text("Compared with typing at \(self.settings.userTypingWPM) WPM.")
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
                Button("Change…") {
                    self.showWPMEditor = true
                }
                .buttonStyle(.sayIt(.quiet, size: .small))
                .popover(isPresented: self.$showWPMEditor, arrowEdge: .bottom) {
                    TypingSpeedEditor(initialValue: self.settings.userTypingWPM) { newValue in
                        self.settings.userTypingWPM = newValue
                        self.showWPMEditor = false
                    } onCancel: {
                        self.showWPMEditor = false
                    }
                    .sayItTheme()
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var summaryMetrics: some View {
        let store = self.historyStore
        let today = store.wordsToday
        return HStack(alignment: .top, spacing: Space.xxl) {
            SummaryMetric(
                title: "Words",
                value: store.totalWords.formatted(),
                caption: today > 0 ? "+\(today.formatted()) today" : "None today"
            )
            SummaryMetric(
                title: "Dictations",
                value: store.entries.count.formatted(),
                caption: "\(CopyFormat.count(store.averageWordsPerTranscription, "word")) on average"
            )
            SummaryMetric(
                title: "Streak",
                value: CopyFormat.count(store.currentStreak, "day"),
                caption: "Best: \(CopyFormat.count(store.bestStreak, "day"))"
            )
        }
    }

    // MARK: - Activity

    private var activityCard: some View {
        let data = self.historyStore.dailyWordCounts(days: self.chartRange.rawValue)
        let totalWords = data.reduce(0) { $0 + $1.words }
        let activeDays = data.filter { $0.words > 0 }.count

        return ThemedCard {
            VStack(alignment: .leading, spacing: Space.lg) {
                ActivityUI.SectionTitle("Activity") {
                    Picker("Range", selection: self.$chartRange.motionBinding()) {
                        ForEach(ChartRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Range")
                }

                if totalWords == 0 {
                    ActivityUI.EmptyState(
                        systemImage: "chart.bar",
                        title: "No Activity in This Range",
                        message: "Dictations from the \(self.chartRange.title.lowercased()) appear here."
                    )
                } else {
                    ActivityChart(data: data, range: self.chartRange)

                    Text("\(CopyFormat.count(totalWords, "word")) across \(CopyFormat.count(activeDays, "active day"))")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
            }
        }
    }

    // MARK: - Insights

    private var insightsCard: some View {
        let store = self.historyStore
        let topApps = store.topAppsFormatted(limit: 3)
        let notEnoughData = "Not enough data yet"

        return ThemedCard {
            VStack(alignment: .leading, spacing: Space.lg) {
                ActivityUI.SectionTitle("Insights")
                Grid(alignment: .topLeading, horizontalSpacing: Space.xl, verticalSpacing: Space.lg) {
                    GridRow {
                        ActivityUI.LabeledValue(
                            label: "Top Apps",
                            value: topApps.isEmpty ? notEnoughData : topApps.joined(separator: ", "),
                            systemImage: "square.grid.2x2"
                        )
                        ActivityUI.LabeledValue(
                            label: "Enhanced",
                            value: "\(store.aiEnhancementRate)% of dictations",
                            systemImage: "sparkles"
                        )
                    }
                    GridRow {
                        ActivityUI.LabeledValue(
                            label: "Peak Time",
                            value: store.peakHour == nil ? notEnoughData : store.peakHourFormatted,
                            systemImage: "clock"
                        )
                        ActivityUI.LabeledValue(
                            label: "Average Length",
                            value: CopyFormat.count(store.averageWordsPerTranscription, "word"),
                            systemImage: "text.alignleft"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Milestones

    private var milestonesCard: some View {
        let store = self.historyStore
        return ThemedCard {
            VStack(alignment: .leading, spacing: Space.lg) {
                ActivityUI.SectionTitle("Milestones") {
                    Text("\(store.totalMilestonesAchieved) of \(store.totalMilestonesPossible) reached")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                VStack(alignment: .leading, spacing: Space.md) {
                    MilestoneRow(title: "Words", milestones: store.wordMilestones)
                    MilestoneRow(title: "Dictations", milestones: store.transcriptionMilestones)
                    MilestoneRow(title: "Streak", milestones: store.streakMilestones)
                }
            }
        }
    }

    // MARK: - Records

    private var recordsCard: some View {
        let store = self.historyStore
        return ThemedCard {
            VStack(alignment: .leading, spacing: Space.lg) {
                ActivityUI.SectionTitle("Personal Records")
                HStack(alignment: .top, spacing: Space.xl) {
                    ActivityUI.LabeledValue(
                        label: "Longest Dictation",
                        value: CopyFormat.count(store.longestTranscriptionWords, "word")
                    )
                    ActivityUI.LabeledValue(
                        label: "Most Words in a Day",
                        value: CopyFormat.count(store.mostWordsInDay, "word")
                    )
                    ActivityUI.LabeledValue(
                        label: "Most Dictations in a Day",
                        value: CopyFormat.count(store.mostTranscriptionsInDay, "dictation")
                    )
                }
            }
        }
    }

    // MARK: - Clear

    private var clearSection: some View {
        let count = self.historyStore.entries.count
        return HStack(spacing: Space.md) {
            Text("Stats are calculated from your history.")
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
            Spacer()
            Button("Clear History…") {
                self.showClearConfirmation = true
            }
            .buttonStyle(.sayIt(.destructive, size: .small))
        }
        .confirmationDialog(
            "Clear all history?",
            isPresented: self.$showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                withMotion(Motion.exit) {
                    self.historyStore.clearAllHistory()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes \(CopyFormat.count(count, "dictation")) from History. Stats are calculated from History, so they reset too. This can’t be undone.")
        }
    }
}

// MARK: - Summary Metric

private struct SummaryMetric: View {
    @Environment(\.theme) private var theme

    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(self.title)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(self.theme.palette.secondaryText)
            Text(self.value)
                .font(AppFont.metricSmall)
                .foregroundStyle(self.theme.palette.primaryText)
                .contentTransition(.numericText())
                .lineLimit(1)
            Text(self.caption)
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Activity Chart

private struct ActivityChart: View {
    @Environment(\.theme) private var theme

    let data: [(date: Date, words: Int)]
    let range: StatsView.ChartRange

    @State private var selectedDate: Date?

    private static let height: CGFloat = 168

    private var axisDateFormat: Date.FormatStyle {
        self.range == .week
            ? Date.FormatStyle.dateTime.weekday(.abbreviated)
            : Date.FormatStyle.dateTime.month(.abbreviated).day()
    }

    private var selectedDay: (date: Date, words: Int)? {
        guard let selectedDate else { return nil }
        let calendar = Calendar.current
        return self.data.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        let accent = self.theme.palette.accent
        let selected = self.selectedDay

        Chart {
            ForEach(self.data, id: \.date) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Words", item.words)
                )
                .foregroundStyle(selected == nil || selected?.date == item.date ? accent : accent.opacity(0.35))
                .cornerRadius(Radius.xs)
                .accessibilityLabel(item.date.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityValue(CopyFormat.count(item.words, "word"))
            }

            if let selected {
                RuleMark(x: .value("Day", selected.date, unit: .day))
                    .foregroundStyle(self.theme.palette.hairline)
                    .annotation(position: .top, spacing: Space.xs, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(selected.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                .font(AppFont.caption)
                                .foregroundStyle(self.theme.palette.secondaryText)
                            Text(CopyFormat.count(selected.words, "word"))
                                .font(AppFont.captionEmphasis)
                                .foregroundStyle(self.theme.palette.primaryText)
                        }
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(self.theme.palette.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
                        )
                    }
            }
        }
        .chartXSelection(value: self.$selectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: self.range == .week ? 1 : 7)) { _ in
                AxisValueLabel(format: self.axisDateFormat)
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(self.theme.palette.separator)
                AxisValueLabel()
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        }
        .frame(height: Self.height)
        .accessibilityLabel("Words per day, \(self.range.title.lowercased())")
    }
}

// MARK: - Milestones

private struct MilestoneRow: View {
    @Environment(\.theme) private var theme

    let title: String
    let milestones: [(target: Int, achieved: Bool, label: String)]

    private static let titleWidth: CGFloat = 88

    var body: some View {
        HStack(spacing: Space.sm) {
            Text(self.title)
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
                .frame(width: Self.titleWidth, alignment: .leading)

            ForEach(Array(self.milestones.enumerated()), id: \.offset) { _, milestone in
                HStack(spacing: Space.xxs) {
                    Image(systemName: milestone.achieved ? "checkmark" : "circle.dotted")
                        .font(AppFont.micro)
                        .accessibilityHidden(true)
                    Text(milestone.label)
                        .font(AppFont.caption)
                }
                .foregroundStyle(milestone.achieved ? self.theme.palette.accentForeground : self.theme.palette.tertiaryText)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xxs)
                .background(
                    Capsule().fill(milestone.achieved ? self.theme.palette.accentSubtle : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(milestone.achieved ? Color.clear : self.theme.palette.hairline, lineWidth: 1)
                )
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(self.title) milestones")
        .accessibilityValue(self.accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let reached = self.milestones.filter(\.achieved).map(\.label)
        let next = self.milestones.first { !$0.achieved }?.label
        var parts: [String] = []
        parts.append(reached.isEmpty ? "None reached" : "Reached \(reached.joined(separator: ", "))")
        if let next { parts.append("next \(next)") }
        return parts.joined(separator: "; ")
    }
}

// MARK: - Typing Speed Editor

private struct TypingSpeedEditor: View {
    @Environment(\.theme) private var theme

    let onSave: (Int) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    private static let validRange = 1...200
    private static let fieldWidth: CGFloat = 64
    private static let popoverWidth: CGFloat = 260

    init(initialValue: Int, onSave: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: "\(initialValue)")
    }

    private var parsedValue: Int? {
        guard let value = Int(self.text.trimmingCharacters(in: .whitespaces)),
              Self.validRange.contains(value)
        else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Your Typing Speed")
                .font(AppFont.sectionTitle)

            HStack(spacing: Space.sm) {
                TextField("Words per minute", text: self.$text)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(width: Self.fieldWidth)
                    .focused(self.$isFocused)
                    .onSubmit(self.save)
                Text("words per minute")
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            if self.parsedValue == nil {
                Label("Enter a whole number from 1 to 200.", systemImage: "exclamationmark.circle")
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.error)
            } else {
                Text("An average typist manages about 40 WPM; professionals reach 65–75 WPM.")
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Space.sm) {
                Spacer()
                Button("Cancel", action: self.onCancel)
                    .buttonStyle(.sayIt(.secondary, size: .small))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: self.save)
                    .buttonStyle(.sayIt(.primary, size: .small))
                    .keyboardShortcut(.defaultAction)
                    .disabled(self.parsedValue == nil)
            }
        }
        .padding(Space.lg)
        .frame(width: Self.popoverWidth)
        .onAppear { self.isFocused = true }
    }

    private func save() {
        guard let value = self.parsedValue else { return }
        self.onSave(value)
    }
}

// MARK: - Helpers

private extension Binding {
    /// Applies the state motion token when the value changes.
    func motionBinding() -> Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { newValue in withMotion(Motion.state) { self.wrappedValue = newValue } }
        )
    }
}

#Preview {
    StatsView()
        .frame(width: 720, height: 900)
        .sayItTheme()
}
