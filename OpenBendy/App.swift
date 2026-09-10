import AppKit
import SwiftUI

@main
struct OpenBendyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let prefs = Preferences()
    private var window: NSWindow?
    private var status: NSStatusItem?
    private let sensor = LidSensor()
    private let effect = DesktopEffect()
    private var animationTimer: Timer?
    private let escapeShortcut = EscapeShortcut()
    private var localEscapeMonitor: Any?
    private var changingCapture = false
    private var resumeRequested = false
    private var smoothedAngle = 135.0
    private var lastDiagnosticAt = Date.distantPast
    private lazy var foldSound: NSSound? = Bundle.main.url(forResource: "fold", withExtension: "wav").flatMap { NSSound(contentsOf: $0, byReference: false) }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests exercise the shader and model without opening a second live overlay.
        guard NSClassFromString("XCTestCase") == nil else { return }
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = menuMark()
        item.button?.target = self; item.button?.action = #selector(showMenu)
        status = item
        resumeRequested = prefs.resumeDesktopEffect
        prefs.captureStatus = "Desktop effect is off"
        sensor.onAngle = { [weak self] angle in
            guard let self else { return }
            self.prefs.sensorAngle = angle
            self.prefs.sensorStatus = angle.map { "Connected · \(Int($0))°" } ?? "No compatible lid sensor is available."
            if angle != nil && self.resumeRequested {
                self.resumeRequested = false
                self.toggleEffect()
            }
        }
        sensor.start()
        effect.onError = { [weak self] message in
            guard let self else { return }
            self.animationTimer?.invalidate(); self.animationTimer = nil; self.escapeShortcut.stop()
            self.prefs.enabled = false; self.prefs.captureStatus = "Capture stopped"; self.prefs.error = message
            Task { await self.effect.stop() }
        }
        effect.onClear = { [weak self] in if self?.prefs.sound == true { self?.foldSound?.play() } }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.pause() } }
            return event
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(pause), name: NSWorkspace.willSleepNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pause), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        showSettings()
    }
    private func menuMark() -> NSImage {
        let image = NSImage(named: "OpenBendyMenu") ?? NSImage(size: NSSize(width: 20, height: 20))
        image.isTemplate = true
        image.accessibilityDescription = "OpenBendy"
        return image
    }
    @objc func showSettings() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 644, height: 700), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "OpenBendy"; w.titleVisibility = .hidden; w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false; w.minSize = NSSize(width: 644, height: 700)
            let hosting = NSHostingView(rootView: SettingsView(prefs: prefs, enable: { [weak self] in self?.toggleEffect() }))
            hosting.safeAreaRegions = []
            hosting.sizingOptions = []
            w.contentView = hosting
            w.setContentSize(NSSize(width: 644, height: 700))
            w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "OpenBendy", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: prefs.enabled ? "Pause Effect" : "Enable Effect", action: #selector(toggleEffect), keyEquivalent: "")
        menu.addItem(withTitle: "Appearance…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OpenBendy", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status?.menu = menu; status?.button?.performClick(nil); status?.menu = nil
    }
    private func tick() {
        guard prefs.enabled else { return }
        let target = prefs.sensorAngle ?? 135
        smoothedAngle = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? target : smoothedAngle + (target - smoothedAngle) * 0.22
        effect.update(prefs.parameters(angle: smoothedAngle))
        // Opt-in local QA only: no captured content is written to disk.
        if let path = ProcessInfo.processInfo.environment["OPENBENDY_DIAGNOSTICS_PATH"],
           Date().timeIntervalSince(lastDiagnosticAt) > 0.5 {
            lastDiagnosticAt = Date()
            var snapshot = effect.diagnostics()
            snapshot["sensorAngle"] = target
            snapshot["smoothedAngle"] = smoothedAngle
            if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
    }
    @objc func toggleEffect() {
        guard !changingCapture else { return }
        if prefs.enabled { pause(); return }
        // ScreenCaptureKit is authoritative. A legacy preflight result can stay stale
        // after an app update or permission change; do not block a valid capture here.
        guard prefs.sensorAngle != nil else {
            prefs.error = "A compatible MacBook lid sensor is required for the live desktop effect. You can still use the Appearance preview."
            return
        }
        changingCapture = true; prefs.captureStatus = "Starting…"
        Task { @MainActor in
            defer { changingCapture = false }
            do {
                try await effect.start()
                prefs.enabled = true; prefs.captureStatus = "Running · on-device capture"
                smoothedAngle = prefs.sensorAngle ?? 135
                let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.tick() }
                }
                animationTimer = timer
                RunLoop.main.add(timer, forMode: .common)
                if !escapeShortcut.start(action: { [weak self] in self?.pause() }) {
                    prefs.captureStatus = "Running · use the menu bar to pause"
                }
            } catch {
                prefs.enabled = false
                if (error as NSError).code == -3801 {
                    prefs.captureStatus = "Screen Recording permission required"
                    prefs.page = .general
                    prefs.error = "Enable OpenBendy in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen OpenBendy."
                } else {
                    prefs.captureStatus = "Could not start capture"
                    prefs.error = error.localizedDescription
                }
            }
        }
    }
    @objc func pause() {
        guard prefs.enabled, !changingCapture else { return }
        prefs.enabled = false; prefs.captureStatus = "Paused"; changingCapture = true
        animationTimer?.invalidate(); animationTimer = nil; escapeShortcut.stop()
        Task { @MainActor in await effect.stop(); changingCapture = false }
    }
    func applicationWillTerminate(_ notification: Notification) {
        sensor.stop(); animationTimer?.invalidate()
        escapeShortcut.stop()
        if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
    }
    @objc func quit() { NSApp.terminate(nil) }
}
