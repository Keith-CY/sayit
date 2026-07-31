//
//  UpdateController.swift
//  SayIt
//
//  GitHub Releases-backed application updates.
//

import AppKit
import Combine
import Foundation
import Sparkle

struct AppVersion: Equatable {
    let marketingVersion: String
    let buildNumber: String

    var displayName: String {
        guard !self.buildNumber.isEmpty else { return self.marketingVersion }
        return "\(self.marketingVersion) (\(self.buildNumber))"
    }

    static func current(in bundle: Bundle = .main) -> AppVersion {
        let marketingVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return AppVersion(
            marketingVersion: marketingVersion ?? "Development",
            buildNumber: buildNumber ?? ""
        )
    }
}

enum UpdateConfiguration {
    static let repositoryURLString = "https://github.com/Keith-CY/sayit"
    static let releasesURLString = "\(repositoryURLString)/releases"
    static let feedURLString = "\(repositoryURLString)/releases/latest/download/appcast.xml"
}

@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController()

    @Published private(set) var automaticChecksEnabled = true
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var lastErrorMessage: String?

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    private override init() {
        super.init()
        _ = self.updaterController
        self.refreshStatus()
    }

    var currentVersion: AppVersion {
        AppVersion.current()
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        self.updaterController.updater.automaticallyChecksForUpdates = enabled
        self.refreshStatus()
    }

    func refreshStatus() {
        let updater = self.updaterController.updater
        self.automaticChecksEnabled = updater.automaticallyChecksForUpdates
        self.lastCheckDate = updater.lastUpdateCheckDate
    }

    @objc func checkForUpdates(_ sender: Any? = nil) {
        self.lastErrorMessage = nil
        self.updaterController.checkForUpdates(sender)
    }

    func openReleasesPage() {
        guard let url = URL(string: UpdateConfiguration.releasesURLString) else { return }
        NSWorkspace.shared.open(url)
    }
}

extension UpdateController: SPUUpdaterDelegate {
    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        self.lastCheckDate = updater.lastUpdateCheckDate
        self.lastErrorMessage = error?.localizedDescription
    }
}
