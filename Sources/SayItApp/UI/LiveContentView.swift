import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LiveContentView: View {
    @ObservedObject var viewModel: LiveTranscriptionViewModel
    @EnvironmentObject private var language: AppLanguageCenter

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let isWideLayout = geometry.size.width > 1060

                ScrollView {
                    if isWideLayout {
                        HStack(alignment: .top, spacing: 14) {
                            transcriptCard
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            VStack(alignment: .leading, spacing: 14) {
                                headerCard
                                actionCard
                            }
                            .frame(width: min(360, geometry.size.width * 0.32), alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            headerCard
                            transcriptCard
                            actionCard
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.shouldShowCodexOAuthOverlay {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()

                LiquidGlassCard(cornerRadius: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(language.text("settings.codexOAuth"))
                                .font(.headline.weight(.semibold))
                            Spacer()
                            Button(language.text("live.oauthClose")) {
                                viewModel.dismissCodexOAuthOverlay()
                            }
                            .disabled(viewModel.codexOAuthInProgress)
                            .buttonStyle(GlassPillButtonStyle())
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
                                .buttonStyle(GlassPillButtonStyle())
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
                            .buttonStyle(GlassPillButtonStyle())

                            Button(language.text("live.oauthOpenBrowser")) {
                                viewModel.openCodexAuthURLInBrowser()
                            }
                            .disabled(viewModel.codexDeviceAuthURL.isEmpty)
                            .buttonStyle(GlassPillButtonStyle())

                            Button(language.text("settings.codexOAuthCopyURL")) {
                                viewModel.copyCodexAuthURL()
                            }
                            .disabled(viewModel.codexDeviceAuthURL.isEmpty)
                            .buttonStyle(GlassPillButtonStyle())

                            Button(language.text("settings.codexOAuthRefresh")) {
                                Task { await viewModel.refreshCodexOAuthStatus() }
                            }
                            .buttonStyle(GlassPillButtonStyle())

                            Button(language.text("settings.codexOAuthCancel")) {
                                viewModel.cancelCodexOAuthLogin()
                            }
                            .disabled(!viewModel.codexOAuthInProgress)
                            .buttonStyle(GlassPillButtonStyle())
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
                }
                .frame(maxWidth: 620)
                .padding(8)
            }
        }
    }

    private var headerCard: some View {
        LiquidGlassCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("tab.live"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(LiquidGlassTheme.ink)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(viewModel.isRecording ? LiquidGlassTheme.hotPink : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)
                            .shadow(color: LiquidGlassTheme.roseQuartz.opacity(viewModel.isRecording ? 0.72 : 0), radius: 6)
                        Text("\(language.text("status")): \(viewModel.status)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if viewModel.isProcessing {
                            ProgressView()
                                .controlSize(.small)
                            Text(language.text("live.processing"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isProcessing)

                    if viewModel.isProcessing && viewModel.hasDeterminateProcessingProgress {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: viewModel.processingProgressFraction, total: 1)
                                .progressViewStyle(.linear)
                                .tint(LiquidGlassTheme.hotPink)

                            Text(viewModel.processingProgressPercentText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeInOut(duration: 0.18), value: viewModel.processingCompletedUnits)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    VoicePulseView(
                        isActive: viewModel.isRecording,
                        level: viewModel.liveAudioLevel,
                        bands: viewModel.liveAudioBands
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if viewModel.isRecording {
                        Text(String(format: language.text("live.micLevel"), viewModel.liveAudioLevel * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var transcriptCard: some View {
        LiquidGlassCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(language.text("final"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(LiquidGlassTheme.ink)

                if !viewModel.partialText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text("partial"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(viewModel.partialText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(LiquidGlassTheme.hotPink.opacity(0.10))
                            .cornerRadius(8)
                    }
                }

                TextEditor(text: $viewModel.currentText)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .frame(minHeight: 360)
                    .padding(8)
                    .background(Color.white.opacity(0.56))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(LiquidGlassTheme.hairline.opacity(0.92), lineWidth: 1)
                    )
            }
        }
    }

    private var actionCard: some View {
        LiquidGlassCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(language.text("settings.sectionGeneral"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(LiquidGlassTheme.ink)

                HStack(spacing: 8) {
                    Button(viewModel.isRecording ? language.text("stop") : language.text("start")) {
                        if viewModel.isRecording {
                            viewModel.stopRecording()
                        } else {
                            viewModel.startRecording()
                        }
                    }
                    .buttonStyle(GlassPillButtonStyle(isSelected: viewModel.isRecording))

                    Button(language.text("clear")) {
                        viewModel.clearText()
                    }
                    .buttonStyle(GlassPillButtonStyle())

                    Button(language.text("transcribeFile")) {
                        if let url = askAudioFileURL() {
                            viewModel.transcribeAudioFile(url: url)
                        }
                    }
                    .disabled(viewModel.isRecording)
                    .buttonStyle(GlassPillButtonStyle())
                }
                .controlSize(.regular)

                HStack(spacing: 8) {
                    Button(language.text("refine")) {
                        viewModel.refineCurrentText()
                    }
                    .buttonStyle(GlassPillButtonStyle())

                    Button(language.text("speak")) {
                        viewModel.speakCurrentText()
                    }
                    .buttonStyle(GlassPillButtonStyle())

                    Button(language.text("live.codexOAuthLogin")) {
                        viewModel.startCodexOAuthLogin()
                    }
                    .disabled(viewModel.codexOAuthInProgress)
                    .buttonStyle(GlassPillButtonStyle())
                }
                .controlSize(.regular)
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
