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

            Text("STT supports faster_whisper / whisper / parakeet. If you choose faster_whisper, install local runtime and preload the small model before recording.")
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
