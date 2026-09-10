import AppKit
import ScreenCaptureKit
import CoreMedia

final class DesktopEffect: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var renderer: DesktopRenderer?
    private var overlay: NSPanel?
    private let queue = DispatchQueue(label: "local.openbendy.frames", qos: .userInteractive)
    private let frameLock = NSLock()
    private var receivedFrame = false
    private var lastProgress = 0.0
    private var watchdog: Timer?
    private var lastFrameAt: TimeInterval = 0
    private var capturedFrames = 0
    var onError: ((String) -> Void)?
    var onClear: (() -> Void)?

    @MainActor func start() async throws {
        guard stream == nil else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let builtIn = content.displays.first { CGDisplayIsBuiltin($0.displayID) != 0 }
        guard let display = builtIn ?? content.displays.first else {
            throw NSError(domain: "OpenBendy", code: 2, userInfo: [NSLocalizedDescriptionKey: "No display is available."])
        }
        let excluded = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width; config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 3; config.showsCursor = false; config.capturesAudio = false
        let renderer = try DesktopRenderer()
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }
        let rect = screen?.frame ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.backgroundColor = .black; panel.isOpaque = true; panel.hasShadow = false
        panel.contentView = renderer.view
        frameLock.withLock { self.renderer = renderer }; overlay = panel
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        do { try await stream.startCapture() }
        catch { self.stream = nil; frameLock.withLock { self.renderer = nil }; overlay = nil; throw error }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameLock.lock(); let age = Date.timeIntervalSinceReferenceDate - self.lastFrameAt; self.frameLock.unlock()
            // Never leave a frozen captured desktop covering the real desktop.
            if age > 2 { self.overlay?.orderOut(nil) }
        }
    }
    @MainActor func update(_ parameters: BendParameters) {
        renderer?.update(parameters)
        frameLock.lock(); let fresh = receivedFrame && Date.timeIntervalSinceReferenceDate - lastFrameAt < 2; frameLock.unlock()
        if parameters.progress > 0.002 && fresh {
            if overlay?.isVisible != true { overlay?.orderFrontRegardless() }
            renderer?.render()
        }
        else { overlay?.orderOut(nil) }
        if lastProgress > 0.01 && parameters.progress <= 0.002 { onClear?() }
        lastProgress = parameters.progress
    }
    @MainActor func diagnostics() -> [String: Any] {
        frameLock.lock()
        let frames = capturedFrames, age = Date.timeIntervalSinceReferenceDate - lastFrameAt
        frameLock.unlock()
        return ["capturedFrames": frames, "frameAge": age, "renderedFrames": renderer?.renderedFrames ?? 0,
                "overlayVisible": overlay?.isVisible ?? false, "progress": lastProgress]
    }
    @MainActor func stop() async {
        watchdog?.invalidate(); watchdog = nil
        overlay?.orderOut(nil)
        let old = stream; stream = nil
        try? await old?.stopCapture()
        frameLock.withLock { renderer?.clear(); renderer = nil; receivedFrame = false }; overlay = nil
        lastProgress = 0
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int else { return }
        // Idle frames carry no changed pixels, but confirm the stream is alive.
        let status = SCFrameStatus(rawValue: rawStatus)
        if status == .idle {
            frameLock.lock(); lastFrameAt = Date.timeIntervalSinceReferenceDate; frameLock.unlock(); return
        }
        guard status == .complete, let buffer = sampleBuffer.imageBuffer else { return }
        frameLock.withLock { renderer?.submit(buffer); receivedFrame = true; capturedFrames += 1; lastFrameAt = Date.timeIntervalSinceReferenceDate }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.overlay?.orderOut(nil)
            self.onError?(error.localizedDescription)
        }
    }
}
