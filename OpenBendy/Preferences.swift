import SwiftUI
import Combine

struct BendParameters {
    var angle: Double
    var clearAngle: Double
    var perspective: Double
    var blur: Double
    var shadow: Double
    var style: BendStyle
    var progress: Double {
        let t = min(1, max(0, (clearAngle - angle) / max(1, clearAngle - 5)))
        return t * t * (3 - 2 * t)
    }
}

enum BendStyle: String, CaseIterable, Identifiable {
    case silk = "Silk", shade = "Shade", frost = "Frost"
    var id: String { rawValue }
    var index: Int { Self.allCases.firstIndex(of: self)! }
}

enum SettingsPage: String, CaseIterable {
    case general = "General", appearance = "Appearance", about = "About"
    var symbol: String {
        switch self { case .general: return "gearshape.fill"; case .appearance: return "circle.lefthalf.filled"; case .about: return "info.circle.fill" }
    }
}

final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var style: BendStyle { didSet { defaults.set(style.rawValue, forKey: "style") } }
    @Published var perspective: Double { didSet { defaults.set(perspective, forKey: "perspective") } }
    @Published var blur: Double { didSet { defaults.set(blur, forKey: "blur") } }
    @Published var shadow: Double { didSet { defaults.set(shadow, forKey: "shadow") } }
    @Published var clearAngle: Double { didSet { defaults.set(clearAngle, forKey: "clearAngle") } }
    @Published var sound: Bool { didSet { defaults.set(sound, forKey: "sound") } }
    @Published var followLid = false
    @Published var manualAngle = 135.0
    @Published var sensorAngle: Double?
    @Published var page: SettingsPage = .appearance
    @Published var enabled = false { didSet { defaults.set(enabled, forKey: "desktopEffectEnabled") } }
    var resumeDesktopEffect: Bool { defaults.bool(forKey: "desktopEffectEnabled") }
    @Published var captureStatus = "Not running"
    @Published var sensorStatus = "Looking for lid sensor…"
    @Published var error: String?
    @Published var playing = false
    @Published var previewAngle = 135.0
    var angle: Double { playing ? previewAngle : (followLid ? (sensorAngle ?? manualAngle) : manualAngle) }
    var preview: BendParameters { parameters(angle: angle) }
    func parameters(angle: Double) -> BendParameters {
        .init(angle: angle, clearAngle: clearAngle, perspective: perspective, blur: blur, shadow: shadow, style: style)
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["perspective": 1.0, "blur": 0.65, "shadow": 0.5, "clearAngle": 100.0, "sound": true])
        style = BendStyle(rawValue: defaults.string(forKey: "style") ?? "Silk") ?? .silk
        perspective = defaults.double(forKey: "perspective")
        blur = defaults.double(forKey: "blur")
        shadow = defaults.double(forKey: "shadow")
        clearAngle = defaults.double(forKey: "clearAngle")
        sound = defaults.bool(forKey: "sound")
    }
    func reset() {
        style = .silk; perspective = 1; blur = 0.65; shadow = 0.5; clearAngle = 100
    }
    @MainActor func playPreview() {
        guard !playing else { playing = false; return }
        playing = true
        Task { @MainActor in
            let start = Date()
            while playing {
                let t = Date().timeIntervalSince(start)
                if t >= 3.4 { break }
                previewAngle = 135 - sin(t / 3.4 * .pi) * 112
                try? await Task.sleep(for: .milliseconds(16))
            }
            playing = false; previewAngle = 135
        }
    }
}
