import AVFoundation
import ApplicationServices
import SayItCore
import SwiftUI

struct OnboardingView: View {
    @State private var configPath: String = "-"

    private var micStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Determined"
        @unknown default: return "Unknown"
        }
    }

    private var accessibilityStatus: String {
        AXIsProcessTrusted() ? "Trusted" : "Not Trusted"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permission Self Check")
                .font(.title3.weight(.semibold))

            Text("Microphone: \(micStatus)")
            Text("Accessibility: \(accessibilityStatus)")

            Text("If permissions are denied, open System Settings -> Privacy & Security and grant access.")
                .foregroundStyle(.secondary)
                .font(.footnote)

            Divider()

            Text("Config path: \(configPath)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("STT is configured to use faster_whisper only. Ensure local faster_whisper runtime is available before recording.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            configPath = AppConfigManager.defaultConfigURL().path
        }
    }
}
