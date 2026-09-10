import SwiftUI
import MetalKit

// Vector scenery for the Appearance preview.
struct Landscape: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack {
                Canvas { context, size in
                    let sx = size.width / 280, sy = size.height / 175
                    context.scaleBy(x: sx, y: sy)
                    context.fill(Path(CGRect(x: 0, y: 0, width: 280, height: 175)), with: .linearGradient(Gradient(colors: [Color(hex: 0x4d5d77), Color(hex: 0xaab5c5)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 175)))
                    context.fill(Path(ellipseIn: CGRect(x: 202, y: 36, width: 23, height: 23)), with: .color(Color(hex: 0xdce5ef)))
                    let ridges: [(Double, UInt, Double)] = [(81, 0x7d8591, 0), (94, 0x6d7581, 1.8), (104, 0x5c6470, 3.4), (121, 0x49515e, 5.7)]
                    for (base, color, phase) in ridges {
                        var p = Path(); p.move(to: CGPoint(x: 0, y: base))
                        for x in stride(from: 0.0, through: 280.0, by: 2) {
                            let y = base + sin(x / 24 + phase) * 9 + sin(x / 9 + phase) * 2.7
                            p.addLine(to: CGPoint(x: x, y: y))
                        }
                        p.addLine(to: CGPoint(x: 280, y: 175)); p.addLine(to: CGPoint(x: 0, y: 175)); p.closeSubpath()
                        context.fill(p, with: .color(Color(hex: color)))
                    }
                    var far = Path(); far.move(to: CGPoint(x: 0, y: 112)); far.addCurve(to: CGPoint(x: 128, y: 140), control1: CGPoint(x: 40, y: 126), control2: CGPoint(x: 85, y: 145)); far.addCurve(to: CGPoint(x: 280, y: 93), control1: CGPoint(x: 197, y: 136), control2: CGPoint(x: 231, y: 104)); far.addLine(to: CGPoint(x: 280, y: 175)); far.addLine(to: CGPoint(x: 0, y: 175)); far.closeSubpath()
                    context.fill(far, with: .linearGradient(Gradient(colors: [Color(hex: 0xa1b1c3), Color(hex: 0xe0e8f3)]), startPoint: CGPoint(x: 0, y: 175), endPoint: CGPoint(x: 250, y: 100)))
                    var near = Path(); near.move(to: CGPoint(x: 0, y: 126)); near.addCurve(to: CGPoint(x: 155, y: 151), control1: CGPoint(x: 52, y: 112), control2: CGPoint(x: 107, y: 143)); near.addCurve(to: CGPoint(x: 280, y: 147), control1: CGPoint(x: 213, y: 164), control2: CGPoint(x: 239, y: 157)); near.addLine(to: CGPoint(x: 280, y: 175)); near.addLine(to: CGPoint(x: 0, y: 175)); near.closeSubpath()
                    context.fill(near, with: .linearGradient(Gradient(colors: [Color(hex: 0xd2deea), Color(hex: 0x71849d)]), startPoint: CGPoint(x: 30, y: 122), endPoint: CGPoint(x: 230, y: 190)))
                }
                VStack(spacing: w * 0.023) {
                    Text("Wednesday, September 9").font(.system(size: w * 0.025, weight: .semibold))
                    Text("9:41").font(.system(size: w * 0.142, weight: .light)).tracking(-w * 0.008)
                    Spacer()
                    Capsule().fill(.white.opacity(0.75)).frame(width: w * 0.20, height: 1).padding(.bottom, w * 0.012)
                }.foregroundStyle(Color(hex: 0xebeff6)).padding(.top, w * 0.082)
            }
        }.accessibilityHidden(true)
    }
}

struct PreviewEffect: View {
    let params: BendParameters
    var body: some View {
        GeometryReader { g in
            MetalLandscapePreview(params: params)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: g.size.width * 0.035))
        }
    }
}

private struct MetalLandscapePreview: NSViewRepresentable {
    let params: BendParameters
    final class Coordinator { var renderer: DesktopRenderer? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    @MainActor func makeNSView(context: Context) -> NSView {
        do {
            let renderer = try DesktopRenderer()
            let image = ImageRenderer(content: Landscape().frame(width: 640, height: 400))
            if let cgImage = image.cgImage { try renderer.submitPreview(cgImage) }
            renderer.update(params)
            context.coordinator.renderer = renderer
            return renderer.view
        } catch {
            return NSTextField(labelWithString: "Preview unavailable")
        }
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.renderer?.update(params)
        context.coordinator.renderer?.render()
        view.needsDisplay = true
    }
}

struct MacBookPreview: View {
    @ObservedObject var prefs: Preferences
    var body: some View {
        ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(topLeadingRadius: 17, topTrailingRadius: 17).fill(Color(hex: 0x111111))
                .frame(width: 268, height: 175).padding(.bottom, 8)
            PreviewEffect(params: prefs.preview).frame(width: 254, height: 158).padding(.bottom, 17)
            UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                .fill(Color(hex: 0x111111)).frame(width: 60, height: 10).offset(y: -167)
            UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3).fill(Color(hex: 0x8b8b8c)).frame(width: 300, height: 9)
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4).fill(Color(hex: 0x565658)).frame(width: 72, height: 4).padding(.bottom, 5)
            Button { prefs.playPreview() } label: {
                Image(systemName: prefs.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: 0x30353e).opacity(0.72), in: Circle())
            }.buttonStyle(.plain).help(prefs.playing ? "Stop preview" : "Play bend preview")
                .accessibilityLabel(prefs.playing ? "Stop preview" : "Play bend preview")
                .padding(.bottom, 80)
        }.frame(width: 300, height: 184)
    }
}

extension Color {
    init(hex: UInt) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
