import AppKit

@MainActor
final class MenuBarAnimator {
    enum AnimationState {
        case idle
        case recording
        case processing
    }

    private enum Constants {
        static let defaultFrameCount = 12
        static let defaultFrameInterval: TimeInterval = 0.08
        static let fallbackResourceNames = ["menubar_icon_36", "menubar_icon_18"]
    }

    private let statusItem: NSStatusItem
    private let frameCount: Int
    private let frameInterval: TimeInterval
    private var timer: Timer?
    private var idx = 0
    private let recordingFrames: [NSImage]
    private let processingFrames: [NSImage]
    private let iconSize = NSSize(width: 18, height: 18)

    init(
        statusItem: NSStatusItem,
        frameCount: Int = Constants.defaultFrameCount,
        frameInterval: TimeInterval = Constants.defaultFrameInterval
    ) {
        self.statusItem = statusItem
        self.frameCount = frameCount
        self.frameInterval = frameInterval
        self.recordingFrames = Self.loadFrames(prefix: "menubar_wave", count: frameCount)
        self.processingFrames = Self.loadFrames(prefix: "menubar_write", count: frameCount)
    }

    func start(_ state: AnimationState) {
        self.stop(staticImageName: nil)

        let frames: [NSImage]
        switch state {
        case .recording:
            frames = self.recordingFrames
        case .processing:
            frames = self.processingFrames
        case .idle:
            self.applyStaticIcon()
            return
        }

        guard frames.isEmpty == false else {
            self.applyStaticIcon()
            return
        }

        self.idx = 0
        self.apply(frames[self.idx])
        self.timer = Timer.scheduledTimer(withTimeInterval: self.frameInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.idx = (self.idx + 1) % frames.count
                self.apply(frames[self.idx])
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop(staticImageName: String? = nil) {
        self.timer?.invalidate()
        self.timer = nil
        self.applyStaticIcon(named: staticImageName)
    }

    private func apply(_ image: NSImage) {
        guard let button = self.statusItem.button else { return }
        button.imageScaling = .scaleProportionallyUpOrDown
        button.image = self.preparedMenuBarImage(from: image)
    }

    private func applyStaticIcon(named staticImageName: String? = nil) {
        let image = Self.loadStaticIcon(named: staticImageName)
            ?? Self.loadImage(named: "MenuBarIcon")
            ?? self.placeholderImage()

        guard let button = self.statusItem.button else { return }
        button.imageScaling = .scaleProportionallyUpOrDown
        button.image = self.preparedMenuBarImage(from: image)
    }

    private func placeholderImage() -> NSImage {
        let image = NSImage(size: .init(width: 18, height: 18))
        image.lockFocus()
        NSColor.clear.set()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        return image
    }

    private func preparedMenuBarImage(from image: NSImage) -> NSImage {
        let preparedImage = NSImage(size: self.iconSize)
        preparedImage.lockFocus()

        // Match the 18x18 menu bar rendering target to avoid edge clipping.
        image.draw(
            in: NSRect(origin: .zero, size: self.iconSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1.0
        )

        preparedImage.unlockFocus()
        preparedImage.isTemplate = true
        return preparedImage
    }

    private static func loadFrames(prefix: String, count: Int) -> [NSImage] {
        let all = (0..<count).compactMap { index in
            Self.loadImage(named: String(format: "%@_%02d_36", prefix, index))
        }
        return all
    }

    private static func loadStaticIcon(named name: String?) -> NSImage? {
        if let name {
            return Self.loadImage(named: name)
        }

        for candidate in Constants.fallbackResourceNames {
            if let image = Self.loadImage(named: candidate) {
                return image
            }
        }

        return nil
    }

    static func loadImage(named name: String) -> NSImage? {
        let imageNames = [Bundle.main.path(forResource: name, ofType: "png"),
                          Bundle.main.path(forResource: name, ofType: "pdf"),
                          Bundle.main.path(forResource: name, ofType: nil)]
        let moduleNames = [Bundle.module.path(forResource: name, ofType: "png"),
                           Bundle.module.path(forResource: name, ofType: "pdf"),
                           Bundle.module.path(forResource: name, ofType: nil)]

        for path in imageNames + moduleNames where path != nil {
            if let path = path, let image = NSImage(contentsOfFile: path) {
                image.isTemplate = true
                return image
            }
        }

        return NSImage(named: name)
    }
}
