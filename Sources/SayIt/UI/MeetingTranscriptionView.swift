import SwiftUI
import UniformTypeIdentifiers

/// "File Transcription": transcribe an audio or video file with the active speech model.
struct MeetingTranscriptionView: View {
    let asrService: ASRService
    @StateObject private var transcriptionService: MeetingTranscriptionService
    @State private var selectedFileURL: URL?
    @Environment(\.theme) private var theme

    init(asrService: ASRService) {
        self.asrService = asrService
        _transcriptionService = StateObject(wrappedValue: MeetingTranscriptionService(asrService: asrService))
    }

    /// Previews and snapshot tests: inject a service in a specific state.
    init(asrService: ASRService, service: MeetingTranscriptionService, selectedFileURL: URL?) {
        self.asrService = asrService
        _transcriptionService = StateObject(wrappedValue: service)
        _selectedFileURL = State(initialValue: selectedFileURL)
    }

    @State private var showingFilePicker = false
    @State private var showingExportDialog = false
    @State private var exportFormat: ExportFormat = .text
    @State private var isDropTargeted = false
    @State private var notice: Notice?
    @State private var transcriptionTask: Task<Void, Never>?

    /// A problem that isn't owned by the transcription service (file picking, drop, export).
    private struct Notice: Equatable {
        let kind: ActivityUI.BannerKind
        let title: String
        let message: String?
    }

    enum ExportFormat: String, CaseIterable {
        case text = "Plain Text (.txt)"
        case json = "JSON (.json)"

        var fileExtension: String {
            switch self {
            case .text: return "txt"
            case .json: return "json"
            }
        }
    }

    private static let supportedFileExtensions = ["wav", "mp3", "m4a", "aac", "flac", "aiff", "caf", "mp4", "mov"]
    private static let supportedFormatsText = "WAV, MP3, M4A, AAC, FLAC, AIFF, CAF, MP4 or MOV"
    private static let transcriptMaxHeight: CGFloat = 360

    var body: some View {
        ActivityUI.Page(
            "File Transcription",
            subtitle: "Turn a recording or video into text with your speech model."
        ) {
            if let fileURL = self.selectedFileURL {
                self.fileCard(fileURL)
            } else {
                self.dropZone
            }

            if let notice = self.notice {
                ActivityUI.Banner(notice.kind, title: notice.title, message: notice.message) {
                    Button("Dismiss") { withMotion(Motion.exit) { self.notice = nil } }
                        .buttonStyle(.sayIt(.quiet, size: .small))
                }
                .motionTransition()
            }

            if let error = self.transcriptionService.error {
                ActivityUI.Banner(.error, title: "Couldn’t transcribe this file", message: error) {
                    if self.selectedFileURL != nil {
                        Button("Try Again", action: self.startTranscription)
                            .buttonStyle(.sayIt(.quiet, size: .small))
                    }
                    Button("Choose Another File…") {
                        self.transcriptionService.reset()
                        self.showingFilePicker = true
                    }
                    .buttonStyle(.sayIt(.secondary, size: .small))
                }
                .motionTransition()
            } else if self.transcriptionService.wasCancelled {
                ActivityUI.Banner(.info, title: "Transcription cancelled") {
                    if self.selectedFileURL != nil {
                        Button("Transcribe Again", action: self.startTranscription)
                            .buttonStyle(.sayIt(.secondary, size: .small))
                    }
                }
                .motionTransition()
            }

            if let result = self.transcriptionService.result {
                self.resultCard(result)
                    .motionTransition()
            }
        }
        .motion(Motion.state, value: self.transcriptionService.isTranscribing)
        .motion(Motion.state, value: self.transcriptionService.result?.id)
        .fileImporter(
            isPresented: self.$showingFilePicker,
            allowedContentTypes: [.audio, .movie, .mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    self.select(url)
                }
            case let .failure(error):
                DebugLogger.shared.error("File picker error: \(error)", source: "MeetingTranscriptionView")
                self.notice = Notice(kind: .error, title: "Couldn’t open the file", message: error.localizedDescription)
            }
        }
        .onDisappear {
            self.transcriptionTask?.cancel()
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        return VStack(spacing: Space.md) {
            Image(systemName: "arrow.down.doc")
                .font(AppFont.iconLarge)
                .foregroundStyle(self.isDropTargeted ? self.theme.palette.accentForeground : self.theme.palette.secondaryText)
                .frame(width: Space.xxxl, height: Space.xxxl)
                .background(Circle().fill(self.isDropTargeted ? self.theme.palette.accentSubtle : self.theme.palette.surfaceSunken))
                .accessibilityHidden(true)
            Text("Drop an Audio or Video File Here")
                .font(AppFont.bodyEmphasis)
                .foregroundStyle(self.theme.palette.primaryText)
            Button("Choose File…") {
                self.showingFilePicker = true
            }
            .buttonStyle(.sayItSecondary)
            Text(Self.supportedFormatsText)
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxxl)
        .background(shape.fill(self.isDropTargeted ? self.theme.palette.accentSubtle : self.theme.palette.surface))
        .overlay(
            shape.strokeBorder(
                self.isDropTargeted ? self.theme.palette.accent : self.theme.palette.hairline,
                style: StrokeStyle(lineWidth: 1.5, dash: [Space.sm, Space.xs + Space.xxs])
            )
        )
        .motion(Motion.snappy, value: self.isDropTargeted)
        .onDrop(of: [.fileURL], isTargeted: self.$isDropTargeted) { providers in
            self.handleDrop(providers: providers)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop zone for audio or video files")
    }

    // MARK: - File Card

    private func fileCard(_ fileURL: URL) -> some View {
        let service = self.transcriptionService
        return ThemedCard(style: .prominent) {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(spacing: Space.md) {
                    Image(systemName: "waveform")
                        .font(AppFont.icon)
                        .foregroundStyle(self.theme.palette.accentForeground)
                        .frame(width: Space.xxxl - Space.sm, height: Space.xxxl - Space.sm)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(self.theme.palette.accentSubtle)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(fileURL.lastPathComponent)
                            .font(AppFont.rowTitle)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(Self.fileSize(of: fileURL))
                            .font(AppFont.caption)
                            .foregroundStyle(self.theme.palette.secondaryText)
                    }
                    Spacer(minLength: Space.md)
                    IconButton("Remove File", systemName: "xmark") {
                        withMotion(Motion.exit) {
                            self.selectedFileURL = nil
                            self.transcriptionService.reset()
                        }
                    }
                    .disabled(service.isTranscribing)
                }

                if service.isTranscribing {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        ProgressView(value: service.progress)
                            .progressViewStyle(.linear)
                            .tint(self.theme.palette.accent)
                            .accessibilityLabel("Transcription progress")
                        HStack {
                            Text(service.currentStatus.isEmpty ? "Starting…" : service.currentStatus)
                                .font(AppFont.caption)
                                .foregroundStyle(self.theme.palette.secondaryText)
                                .contentTransition(.opacity)
                            Spacer()
                            Button("Cancel", action: self.cancelTranscription)
                                .buttonStyle(.sayIt(.secondary, size: .small))
                                .keyboardShortcut(.cancelAction)
                        }
                    }
                    .motionTransition()
                } else {
                    HStack {
                        Spacer()
                        Button(service.result == nil ? "Transcribe" : "Transcribe Again", action: self.startTranscription)
                            .buttonStyle(SayItButtonStyle(role: service.result == nil ? .primary : .secondary))
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
    }

    // MARK: - Result

    private func resultCard(_ result: TranscriptionResult) -> some View {
        let isEmpty = result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return ThemedCard {
            VStack(alignment: .leading, spacing: Space.lg) {
                ActivityUI.SectionTitle("Transcript") {
                    if !isEmpty {
                        ActivityUI.CopyButton(text: result.text)
                        Menu("Export") {
                            ForEach(ExportFormat.allCases, id: \.self) { format in
                                Button(format.rawValue) {
                                    self.exportFormat = format
                                    self.showingExportDialog = true
                                }
                            }
                        }
                        .menuStyle(.button)
                        .buttonStyle(.sayIt(.secondary, size: .small))
                        .fixedSize()
                    }
                }

                Text(Self.summary(of: result))
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)

                if isEmpty {
                    ActivityUI.EmptyState(
                        systemImage: "waveform.slash",
                        title: "No Speech Found",
                        message: "SayIt didn’t hear any speech in this file. Check that it has an audio track with someone talking."
                    )
                } else {
                    ScrollView {
                        ActivityUI.TranscriptBlock(text: result.text)
                    }
                    .frame(maxHeight: Self.transcriptMaxHeight)
                }
            }
        }
        .fileExporter(
            isPresented: self.$showingExportDialog,
            document: TranscriptionDocument(
                result: result,
                format: self.exportFormat,
                service: self.transcriptionService
            ),
            contentType: self.exportFormat == .text ? .plainText : .json,
            defaultFilename: "\((result.fileName as NSString).deletingPathExtension) transcript.\(self.exportFormat.fileExtension)"
        ) { exportResult in
            switch exportResult {
            case .success:
                DebugLogger.shared.info("File exported successfully", source: "MeetingTranscriptionView")
            case let .failure(error):
                DebugLogger.shared.error("Export failed: \(error)", source: "MeetingTranscriptionView")
                self.notice = Notice(kind: .error, title: "Export failed", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Actions

    private func select(_ url: URL) {
        withMotion(Motion.state) {
            self.selectedFileURL = url
            self.notice = nil
            self.transcriptionService.reset()
        }
    }

    private func startTranscription() {
        guard let fileURL = self.selectedFileURL else { return }
        self.notice = nil
        self.transcriptionTask?.cancel()
        self.transcriptionTask = Task {
            do {
                _ = try await self.transcriptionService.transcribeFile(fileURL)
            } catch is CancellationError {
                // The service shows the cancelled state.
            } catch {
                // The service exposes the error; it is shown in the banner.
                DebugLogger.shared.error("Transcription error: \(error)", source: "MeetingTranscriptionView")
            }
        }
    }

    private func cancelTranscription() {
        self.transcriptionTask?.cancel()
        self.transcriptionService.cancel()
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL? = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            guard let url = url else { return }
            let ext = url.pathExtension.lowercased()
            DispatchQueue.main.async {
                guard Self.supportedFileExtensions.contains(ext) else {
                    withMotion(Motion.enter) {
                        self.notice = Notice(
                            kind: .warning,
                            title: "That file type isn’t supported",
                            message: "Use \(Self.supportedFormatsText)."
                        )
                    }
                    return
                }
                self.select(url)
            }
        }
        return true
    }

    // MARK: - Formatting

    private static func fileSize(of fileURL: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int64
        else {
            return "Size unknown"
        }
        return CopyFormat.bytes(fileSize)
    }

    static func summary(of result: TranscriptionResult) -> String {
        var parts: [String] = []
        if result.duration > 0 {
            let pattern: Duration.TimeFormatStyle.Pattern = result.duration >= 3600 ? .hourMinuteSecond : .minuteSecond
            parts.append("\(Duration.seconds(result.duration).formatted(.time(pattern: pattern))) of audio")
        }
        if result.processingTime > 0 {
            let seconds = max(1, Int(result.processingTime.rounded()))
            var speed = "transcribed in \(CopyFormat.count(seconds, "second"))"
            if result.duration > 0 {
                let factor = result.duration / result.processingTime
                speed += " (\(factor.formatted(.number.precision(.fractionLength(0...1))))× real time)"
            }
            parts.append(speed)
        }
        if result.confidence > 0 {
            parts.append("confidence \(Int((result.confidence * 100).rounded()))%")
        }
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

// MARK: - Document for Export

struct TranscriptionDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.plainText, .json]
    }

    let result: TranscriptionResult
    let format: MeetingTranscriptionView.ExportFormat
    let service: MeetingTranscriptionService

    init(
        result: TranscriptionResult,
        format: MeetingTranscriptionView.ExportFormat,
        service: MeetingTranscriptionService
    ) {
        self.result = result
        self.format = format
        self.service = service
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnknown)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp.\(self.format.fileExtension)")

        switch self.format {
        case .text:
            try self.service.exportToText(self.result, to: tempURL)
        case .json:
            try self.service.exportToJSON(self.result, to: tempURL)
        }

        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Preview

#Preview {
    MeetingTranscriptionView(asrService: ASRService())
        .frame(width: 700, height: 800)
        .sayItTheme()
}
