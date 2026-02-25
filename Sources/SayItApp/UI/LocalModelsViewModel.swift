import Foundation
import SayItCore

@MainActor
final class LocalModelsViewModel: ObservableObject {
    @Published var installedNames: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var inspections: [String: ModelInstallInspection] = [:]
    @Published var verificationResults: [String: ModelVerificationResult] = [:]
    @Published var status: String = ""
    @Published var isBusy: Bool = false
    @Published var busyModelID: String?

    let catalog = ModelCatalog.defaults()
    private let runtime: SayItCoreRuntime?

    init(runtime: SayItCoreRuntime?) {
        self.runtime = runtime
        refresh()
    }

    func refresh() {
        guard let runtime else {
            status = "Model manager unavailable"
            return
        }

        do {
            var nextInspections: [String: ModelInstallInspection] = [:]
            var nextInstalledNames: Set<String> = []
            for descriptor in catalog {
                let inspection = try runtime.modelDownloadManager.inspect(descriptor)
                nextInspections[descriptor.id] = inspection
                if inspection.installedExists {
                    nextInstalledNames.insert(descriptor.name)
                }
            }
            inspections = nextInspections
            installedNames = nextInstalledNames
            status = "Installed: \(installedNames.count)"
        } catch {
            status = "Model refresh error: \(error.localizedDescription)"
        }
    }

    func isInstalled(_ descriptor: LocalModelDescriptor) -> Bool {
        installedNames.contains(descriptor.name)
    }

    func progress(for descriptor: LocalModelDescriptor) -> Double? {
        downloadProgress[descriptor.id]
    }

    func inspection(for descriptor: LocalModelDescriptor) -> ModelInstallInspection? {
        inspections[descriptor.id]
    }

    func installedPath(for descriptor: LocalModelDescriptor) -> String {
        inspection(for: descriptor)?.installedPath.path ?? "-"
    }

    func quickStatus(for descriptor: LocalModelDescriptor) -> ModelInstallInspection.QuickStatus {
        inspection(for: descriptor)?.quickStatus ?? .notInstalled
    }

    func verification(for descriptor: LocalModelDescriptor) -> ModelVerificationResult? {
        verificationResults[descriptor.id]
    }

    func isVerifying(_ descriptor: LocalModelDescriptor) -> Bool {
        busyModelID == descriptor.id && isBusy
    }

    func sizeLabel(for descriptor: LocalModelDescriptor) -> String {
        Self.byteFormatter.string(fromByteCount: descriptor.sizeBytes)
    }

    func runtimeRequirementHint(for descriptor: LocalModelDescriptor) -> String {
        switch descriptor.engine {
        case .whisper:
            return "Runtime: embedded whisper.cpp (in-process)"
        case .parakeet:
            return "Runtime: FluidAudio Parakeet CoreML (in-process, auto-download)"
        case .moonshine:
            return "Runtime: compatibility mode (Parakeet core -> Whisper fallback); archive is for native runtime prep"
        }
    }

    func toggle(_ descriptor: LocalModelDescriptor) async {
        if isInstalled(descriptor) {
            await remove(descriptor)
        } else {
            await download(descriptor)
        }
    }

    func download(_ descriptor: LocalModelDescriptor) async {
        guard let runtime else { return }
        isBusy = true
        busyModelID = descriptor.id
        defer { isBusy = false }
        defer { busyModelID = nil }

        do {
            _ = try await runtime.modelDownloadManager.download(descriptor) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.downloadProgress[progress.descriptorID] = progress.fractionCompleted
                    if let fraction = progress.fractionCompleted {
                        self.status = "Downloading \(descriptor.name) \(Int(fraction * 100))%"
                    } else {
                        self.status = "Downloading \(descriptor.name)"
                    }
                }
            }
            downloadProgress[descriptor.id] = 1
            status = "Downloaded \(descriptor.name)"
            verificationResults[descriptor.id] = ModelVerificationResult(descriptorID: descriptor.id, isValid: true, reason: "ok")
            refresh()
        } catch {
            downloadProgress[descriptor.id] = nil
            status = "Model operation failed: \(error.localizedDescription)"
        }
    }

    func remove(_ descriptor: LocalModelDescriptor) async {
        guard let runtime else { return }
        isBusy = true
        busyModelID = descriptor.id
        defer { isBusy = false }
        defer { busyModelID = nil }

        do {
            try runtime.modelDownloadManager.remove(descriptor)
            status = "Removed \(descriptor.name)"
            downloadProgress[descriptor.id] = nil
            verificationResults[descriptor.id] = nil
            refresh()
        } catch {
            status = "Model operation failed: \(error.localizedDescription)"
        }
    }

    func verify(_ descriptor: LocalModelDescriptor) async {
        guard let runtime else { return }
        isBusy = true
        busyModelID = descriptor.id
        defer { isBusy = false }
        defer { busyModelID = nil }

        do {
            let result = try runtime.modelDownloadManager.verify(descriptor)
            verificationResults[descriptor.id] = result
            status = "Verify \(descriptor.name): \(result.reason)"
            refresh()
        } catch {
            verificationResults[descriptor.id] = ModelVerificationResult(
                descriptorID: descriptor.id,
                isValid: false,
                reason: "verify_error"
            )
            status = "Verify failed: \(error.localizedDescription)"
            refresh()
        }
    }

    func retry(_ descriptor: LocalModelDescriptor) async {
        guard let runtime else { return }
        isBusy = true
        busyModelID = descriptor.id
        defer { isBusy = false }
        defer { busyModelID = nil }

        do {
            _ = try runtime.modelDownloadManager.cleanupArtifacts(descriptor, removeInstalled: true)
            verificationResults[descriptor.id] = nil
            downloadProgress[descriptor.id] = nil
            _ = try await runtime.modelDownloadManager.download(descriptor) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.downloadProgress[progress.descriptorID] = progress.fractionCompleted
                    if let fraction = progress.fractionCompleted {
                        self.status = "Retrying \(descriptor.name) \(Int(fraction * 100))%"
                    } else {
                        self.status = "Retrying \(descriptor.name)"
                    }
                }
            }
            downloadProgress[descriptor.id] = 1
            verificationResults[descriptor.id] = ModelVerificationResult(descriptorID: descriptor.id, isValid: true, reason: "ok")
            status = "Retry complete: \(descriptor.name)"
            refresh()
        } catch {
            status = "Retry failed: \(error.localizedDescription)"
            refresh()
        }
    }

    func cleanup(_ descriptor: LocalModelDescriptor) async {
        guard let runtime else { return }
        isBusy = true
        busyModelID = descriptor.id
        defer { isBusy = false }
        defer { busyModelID = nil }

        do {
            let inspection = try runtime.modelDownloadManager.inspect(descriptor)
            let removeInstalled = inspection.quickStatus == .sizeMismatch
            let cleaned = try runtime.modelDownloadManager.cleanupArtifacts(descriptor, removeInstalled: removeInstalled)
            verificationResults[descriptor.id] = nil
            downloadProgress[descriptor.id] = nil
            status = "Cleanup \(descriptor.name): installed=\(cleaned.removedInstalled) partial=\(cleaned.removedPartial)"
            refresh()
        } catch {
            status = "Cleanup failed: \(error.localizedDescription)"
            refresh()
        }
    }
}

private extension LocalModelsViewModel {
    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}
