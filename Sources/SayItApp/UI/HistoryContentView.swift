import AppKit
import SayItCore
import SwiftUI
import UniformTypeIdentifiers

struct HistoryContentView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @EnvironmentObject private var language: AppLanguageCenter

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                leftPane
                    .frame(minWidth: 280, maxWidth: 360, maxHeight: .infinity)
                rightPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if !viewModel.status.isEmpty {
                Divider()
                HStack {
                    Text(viewModel.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            viewModel.refresh()
        }
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox(language.text("history.search")) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(language.text("history.search"), text: $viewModel.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            viewModel.search()
                        }

                    HStack(spacing: 8) {
                        Button(language.text("history.refresh")) {
                            viewModel.refresh()
                        }
                        Button(language.text("history.deleteSession")) {
                            viewModel.deleteSelectedSession()
                        }
                        .disabled(viewModel.selectedSessionID == nil)
                    }
                }
            }

            if !viewModel.searchResults.isEmpty {
                GroupBox("Search") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.searchResults) { segment in
                                Text(segment.finalText)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(minHeight: 80, maxHeight: 180)
                }
            }

            GroupBox(language.text("history.sessions")) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.sessions, id: \.id) { summary in
                            Button {
                                viewModel.selectSession(summary.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(summary.session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)
                                    Text("\(summary.segmentCount) segments")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let preview = summary.previewText, !preview.isEmpty {
                                        Text(preview)
                                            .lineLimit(2)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(
                                            viewModel.selectedSessionID == summary.id
                                                ? Color.accentColor.opacity(0.18)
                                                : Color.secondary.opacity(0.08)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var rightPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                GroupBox(language.text("history.audioAssets")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if viewModel.audioAssets.isEmpty {
                            Text(language.text("history.noAudioAssets"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("", selection: $viewModel.selectedAudioAssetID) {
                                ForEach(viewModel.audioAssets) { asset in
                                    Text("\(asset.fileName) • \(viewModel.durationText(for: asset))")
                                        .tag(Optional(asset.id))
                                }
                            }
                            .pickerStyle(.menu)

                            Text(viewModel.selectedAudioAssetPath)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        HStack(spacing: 8) {
                            Button(language.text("history.playAudio")) {
                                viewModel.playSelectedAudio()
                            }
                            .disabled(!viewModel.hasSelectedAudioAsset)

                            Button(language.text("history.stopAudio")) {
                                viewModel.stopAudioPlayback()
                            }
                            .disabled(!viewModel.isPlayingAudio)

                            Button(language.text("history.retranscribeAudio")) {
                                Task { await viewModel.retranscribeSelectedAudio() }
                            }
                            .disabled(!viewModel.hasSelectedAudioAsset)

                            Button(language.text("history.deleteAudio")) {
                                viewModel.deleteSelectedAudioAsset()
                            }
                            .disabled(!viewModel.hasSelectedAudioAsset)
                        }
                    }
                }

                GroupBox(language.text("history.segments")) {
                    if viewModel.selectedSegments.isEmpty {
                        Text("-")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(viewModel.selectedSegments) { segment in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("[\(segment.sequence)] \(segment.provider)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(segment.finalText)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                    Divider()
                                }
                            }
                        }
                        .frame(minHeight: 180, maxHeight: 420)
                    }
                }

                GroupBox(language.text("history.exports")) {
                    HStack(spacing: 8) {
                        Button(language.text("history.exportTxt")) {
                            Task { await viewModel.exportSelected(format: .txt, outputURL: askExportURL(format: .txt)) }
                        }
                        Button(language.text("history.exportMd")) {
                            Task { await viewModel.exportSelected(format: .md, outputURL: askExportURL(format: .md)) }
                        }
                        Button(language.text("history.exportJson")) {
                            Task { await viewModel.exportSelected(format: .json, outputURL: askExportURL(format: .json)) }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func askExportURL(format: ExportFormat) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "sayit-export.\(format.rawValue)"
        panel.allowedContentTypes = [contentType(for: format)]
        let result = panel.runModal()
        guard result == .OK else { return nil }
        return panel.url
    }

    private func contentType(for format: ExportFormat) -> UTType {
        switch format {
        case .txt:
            return .plainText
        case .md:
            return UTType(filenameExtension: "md") ?? .plainText
        case .json:
            return .json
        }
    }
}
