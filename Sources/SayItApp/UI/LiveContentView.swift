import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LiveContentView: View {
    @ObservedObject var viewModel: LiveTranscriptionViewModel
    @EnvironmentObject private var language: AppLanguageCenter

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        transcriptPanel
                        actionPanel
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if viewModel.shouldShowCodexOAuthOverlay {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(language.text("settings.codexOAuth"))
                            .font(.headline)
                        Spacer()
                        Button(language.text("live.oauthClose")) {
                            viewModel.dismissCodexOAuthOverlay()
                        }
                        .disabled(viewModel.codexOAuthInProgress)
                    }

                    Text("\(language.text("settings.codexOAuthStatus")): \(viewModel.codexOAuthStatusLine)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !viewModel.codexDeviceAuthCode.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(language.text("settings.codexOAuthCode")):")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(viewModel.codexDeviceAuthCode)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                            Spacer()
                            Button(language.text("settings.codexOAuthCopyCode")) {
                                viewModel.copyCodexDeviceCode()
                            }
                        }
                    }

                    if !viewModel.codexDeviceAuthURL.isEmpty {
                        if let authURL = URL(string: viewModel.codexDeviceAuthURL) {
                            Link(viewModel.codexDeviceAuthURL, destination: authURL)
                                .font(.caption2)
                        } else {
                            Text(viewModel.codexDeviceAuthURL)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    HStack(spacing: 8) {
                        Button(language.text("settings.codexOAuthStart")) {
                            viewModel.startCodexOAuthLogin()
                        }
                        .disabled(viewModel.codexOAuthInProgress)

                        Button(language.text("live.oauthOpenBrowser")) {
                            viewModel.openCodexAuthURLInBrowser()
                        }
                        .disabled(viewModel.codexDeviceAuthURL.isEmpty)

                        Button(language.text("settings.codexOAuthCopyURL")) {
                            viewModel.copyCodexAuthURL()
                        }
                        .disabled(viewModel.codexDeviceAuthURL.isEmpty)

                        Button(language.text("settings.codexOAuthRefresh")) {
                            Task { await viewModel.refreshCodexOAuthStatus() }
                        }

                        Button(language.text("settings.codexOAuthCancel")) {
                            viewModel.cancelCodexOAuthLogin()
                        }
                        .disabled(!viewModel.codexOAuthInProgress)
                    }

                    if !viewModel.codexOAuthLogs.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(viewModel.codexOAuthLogs.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.caption2.monospaced())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(minHeight: 80, maxHeight: 160)
                    }
                }
                .padding(14)
                .frame(maxWidth: 620)
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(radius: 18)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text("tab.live"))
                    .font(.title3.weight(.semibold))
                Text("\(language.text("status")): \(viewModel.status)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VoicePulseView(isActive: viewModel.isRecording)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var transcriptPanel: some View {
        GroupBox(language.text("final")) {
            VStack(alignment: .leading, spacing: 8) {
                if !viewModel.partialText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text("partial"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(viewModel.partialText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(8)
                    }
                }

                TextEditor(text: $viewModel.currentText)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .frame(minHeight: 260)
                    .border(Color.secondary.opacity(0.25), width: 1)
            }
        }
    }

    private var actionPanel: some View {
        GroupBox(language.text("settings.sectionGeneral")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button(viewModel.isRecording ? language.text("stop") : language.text("start")) {
                        if viewModel.isRecording {
                            viewModel.stopRecording()
                        } else {
                            viewModel.startRecording()
                        }
                    }
                    .keyboardShortcut(.space, modifiers: [.command, .shift])

                    Button(language.text("clear")) {
                        viewModel.clearText()
                    }

                    Button(language.text("transcribeFile")) {
                        if let url = askAudioFileURL() {
                            viewModel.transcribeAudioFile(url: url)
                        }
                    }
                    .disabled(viewModel.isRecording)
                }

                HStack(spacing: 10) {
                    Button(language.text("refine")) {
                        viewModel.refineCurrentText()
                    }

                    Button(language.text("speak")) {
                        viewModel.speakCurrentText()
                    }

                    Button(language.text("live.codexOAuthLogin")) {
                        viewModel.startCodexOAuthLogin()
                    }
                    .disabled(viewModel.codexOAuthInProgress)
                }
            }
        }
    }

    private func askAudioFileURL() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        let result = panel.runModal()
        guard result == .OK else { return nil }
        return panel.url
    }
}
