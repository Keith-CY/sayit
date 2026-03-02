//
//  FeedbackView.swift
//  SayIt
//
//  Local support module (no network requests).
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
                            Text("Support")
                                .font(.system(size: 28, weight: .bold))
                            Text("Help improve \(AppIdentity.displayName)")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 8)

                ThemedCard(style: .prominent, hoverEffect: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                        Text("Feedback is local-only")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(self.theme.palette.primaryText)

                                Text("This section is now local-only.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(self.theme.palette.secondaryText)
                            }
                        }

                        Text("Feedback is saved locally only. No analytics upload is used.")
                            .font(.system(size: 13))
                            .foregroundStyle(self.theme.palette.primaryText)
                            .padding(.top, 2)
                    }
                    .padding(20)
                }

                ThemedCard(style: .standard, hoverEffect: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to share feedback")
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text("Use the local settings/history and local logs if you want to review feedback items.")
                            .font(.system(size: 14))
                            .foregroundStyle(self.theme.palette.secondaryText)

                        TextEditor(text: .constant("Feedback is intentionally kept local in this build. Please share feature notes in the local feedback notes area.")
                        )
                        .font(.system(size: 14))
                        .frame(height: 130)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .disabled(true)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(self.theme.palette.contentBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(self.theme.palette.cardBorder.opacity(0.45), lineWidth: 1.2)
                                )
                        )
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
