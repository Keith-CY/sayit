//
//  RecordingView.swift
//  SayIt
//
//  Recording controls and configuration view
//

import AVFoundation
import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService { self.appServices.asr }
    @Environment(\.theme) private var theme
    @Binding var appear: Bool

    let stopAndProcessTranscription: () async -> Void
    let startRecording: () -> Void

    private var recordingControlAction: RecordingControlAction {
        RecordingControlPolicy.action(
            isRunning: self.asr.isRunning,
            isReady: self.asr.isAsrReady,
            isPreparingModel: self.asr.isDownloadingModel || self.asr.isLoadingModel
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                // Hero Header Card
                ThemedCard(style: .standard) {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Voice Dictation")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("AI-powered speech recognition")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }

                        // Status and Recording Control
                        VStack(spacing: 10) {
                            // Status indicator
                            HStack {
                                Circle()
                                    .fill(self.asr.isRunning ? .red : self.asr.isAsrReady ? Color.fluidGreen : .secondary)
                                    .frame(width: 8, height: 8)

                                Text(self.asr.isRunning ? "Recording..." : self.asr.isAsrReady ? "Ready to record" : "Model not ready")
                                    .font(.subheadline)
                                    .foregroundStyle(self.asr.isRunning ? .red : self.asr.isAsrReady ? Color.fluidGreen : .secondary)
                            }

                            // Recording Control (Single Toggle Button)
                            Button(action: {
                                switch self.recordingControlAction {
                                case .stop:
                                    Task {
                                        await self.stopAndProcessTranscription()
                                    }
                                case .start:
                                    self.startRecording()
                                case .prepareAndStart:
                                    Task {
                                        do {
                                            try await self.asr.ensureAsrReady()
                                            self.startRecording()
                                        } catch {
                                            self.asr.errorTitle = "Voice Model Failed to Prepare"
                                            self.asr.errorMessage = error.localizedDescription
                                            self.asr.showError = true
                                        }
                                    }
                                case .waitForModel:
                                    break
                                }
                            }) {
                                HStack {
                                    Image(systemName: self.recordingControlAction == .stop ? "stop.fill" : "mic.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(self.recordingButtonTitle)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PremiumButtonStyle(isRecording: self.asr.isRunning))
                            .buttonHoverEffect()
                            .scaleEffect(self.asr.isRunning ? 1.05 : 1.0)
                            .animation(.spring(response: 0.3), value: self.asr.isRunning)
                            .disabled(self.recordingControlAction == .waitForModel)
                        }
                    }
                    .padding(14)
                }
                .modifier(CardAppearAnimation(delay: 0.1, appear: self.$appear))
            }
            .padding(14)
        }
    }

    private var recordingButtonTitle: String {
        switch self.recordingControlAction {
        case .start:
            return "Start Recording"
        case .stop:
            return "Stop Recording"
        case .prepareAndStart:
            return "Start Recording"
        case .waitForModel:
            return "Preparing Voice Model…"
        }
    }
}
