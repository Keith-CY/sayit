//
//  FeedbackView.swift
//  FeedbackView.swift
//  SayIt
//

import SwiftUI

struct FeedbackView: View {
    @Environment(\.theme) private var theme
    @State private var appear: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "waveform")
                            .font(.system(size: 32))
                            .foregroundStyle(self.theme.palette.accent)
                        VStack(alignment: .leading) {
                            Text("Support & Help")
                                .font(.system(size: 28, weight: .bold))
                            Text("Local troubleshooting and how-to guidance.")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 8)

                ThemedCard(style: .prominent, hoverEffect: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Local support module")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(self.theme.palette.primaryText)

                                Text("No cloud sync and no analytics upload in this build.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(self.theme.palette.secondaryText)
                            }
                        }

                        Text("Use this panel as a local reference for quick troubleshooting.")
                            .font(.system(size: 13))
                            .foregroundStyle(self.theme.palette.primaryText)
                            .padding(.top, 2)
                    }
                    .padding(20)
                }

                ThemedCard(style: .standard, hoverEffect: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to get help")
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text("Review settings, recent history, and logs in the app before restarting.")
                            .font(.system(size: 14))
                            .foregroundStyle(self.theme.palette.secondaryText)

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Check microphone permission if recording seems unavailable.", systemImage: "mic.fill")
                            Label("Verify Dictation settings and copy-to-clipboard toggle in Preferences.", systemImage: "slider.horizontal.3")
                            Label("If the model fails to download, use the Voice Engine panel to retry download.", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(self.theme.palette.secondaryText)

                        Text("These notes are stored locally only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
                .modifier(CardAppearAnimation(delay: 0.1, appear: self.$appear))
            }
            .padding(24)
        }
        .onAppear {
            self.appear = true
        }
    }
}

#Preview {
    FeedbackView()
}
