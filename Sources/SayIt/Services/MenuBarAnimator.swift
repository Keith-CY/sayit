import AppKit

/// Shows the menu bar icon for the current state.
///
/// The recording overlay is the one moving element while SayIt works (DESIGN.md §7),
/// so the menu bar icon does not loop: it switches to a static frame of the waveform
/// (recording) or writing (working) artwork and back to the resting icon. All images
/// are rendered once, at init.
@MainActor
final class MenuBarAnimator {
    enum AnimationState {
        case idle
        case recording
        case processing
    }

    private enum Constants {
        static let frameCount = 12
        /// Representative frame of each sequence: the pose with the most motion in it.
        static let representativeFrame = 4
        static let fallbackResourceNames = ["menubar_icon_36", "menubar_icon_18"]
        static let iconSize = NSSize(width: 18, height: 18)
    }

    private let statusItem: NSStatusItem
    private let idleImage: NSImage?
    private let recordingImage: NSImage?
    private let processingImage: NSImage?
    private var currentState: AnimationState?

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        self.idleImage = Self.loadStaticIcon().map { Self.prepared($0, size: Constants.iconSize) }
        self.recordingImage = Self.loadFrame(prefix: "menubar_wave").map { Self.prepared($0, size: Constants.iconSize) }
        self.processingImage = Self.loadFrame(prefix: "menubar_write").map { Self.prepared($0, size: Constants.iconSize) }
    }

    func show(_ state: AnimationState) {
        guard state != self.currentState else { return }
        self.currentState = state

        let image: NSImage?
        switch state {
        case .idle: image = self.idleImage
        case .recording: image = self.recordingImage ?? self.idleImage
        case .processing: image = self.processingImage ?? self.idleImage
        }

        guard let image, let button = self.statusItem.button else { return }
        button.imageScaling = .scaleProportionallyUpOrDown
        button.image = image
    }

    /// Renders `image` into a template image of `size` (avoids edge clipping in the menu bar).
    static func prepared(_ image: NSImage, size: NSSize) -> NSImage {
        let prepared = NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)
            return true
        }
        prepared.isTemplate = true
        return prepared
    }

    private static func loadFrame(prefix: String) -> NSImage? {
        let index = min(Constants.representativeFrame, Constants.frameCount - 1)
        return Self.loadImage(named: String(format: "%@_%02d_36", prefix, index))
    }

    private static func loadStaticIcon() -> NSImage? {
        if let image = Self.loadImage(named: "MenuBarIcon") {
            return image
        }
        for candidate in Constants.fallbackResourceNames {
            if let image = Self.loadImage(named: candidate) {
                return image
            }
        }
        return MenuBarIconGenerator.createMenuBarIcon()
    }

    static func loadImage(named name: String) -> NSImage? {
        if let image = NSImage(named: name) {
            image.isTemplate = true
            return image
        }

        let imageNames = [
            (Bundle.main, "png"),
            (Bundle.main, "pdf"),
            (Bundle.main, nil),
        ]

        for (bundle, ext) in imageNames {
            if let path = bundle.path(forResource: name, ofType: ext),
               let image = NSImage(contentsOfFile: path)
            {
                image.isTemplate = true
                return image
            }
        }

        return nil
    }
}
