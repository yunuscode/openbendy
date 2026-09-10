import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    var enable: () -> Void
    @State private var login = SMAppService.mainApp.status == .enabled
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                nav(.general).padding(.top, 48)
                Text("Settings").fontWeight(.semibold).foregroundStyle(.white.opacity(0.6)).padding(.top, 25).padding(.leading, 10).padding(.bottom, 8)
                nav(.appearance)
                Text("OpenBendy").fontWeight(.semibold).foregroundStyle(.white.opacity(0.6)).padding(.top, 20).padding(.leading, 10).padding(.bottom, 8)
                nav(.about)
                Spacer()
            }.padding(.horizontal, 10).frame(width: 190).background(Color.white.opacity(0.025))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    pageIcon(prefs.page)
                    Text(prefs.page.rawValue).font(.system(size: 14, weight: .bold))
                    Spacer()
                    if prefs.page == .appearance {
                        Button(prefs.enabled ? "Pause" : "Enable desktop effect", action: enable)
                            .controlSize(.small)
                            .accessibilityLabel(prefs.enabled ? "Pause desktop effect" : "Enable desktop effect")
                    }
                }.padding(.horizontal, 23).frame(height: 64)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch prefs.page {
                        case .appearance: appearance
                        case .general: general
                        case .about: about
                        }
                    }.padding(.horizontal, 23).padding(.bottom, 25)
                }.scrollIndicators(.hidden).ignoresSafeArea(.container, edges: .top)
            }.frame(maxWidth: .infinity)
        }
        .font(.system(size: 13)).foregroundStyle(Color(white: 0.93))
        .background(LinearGradient(colors: [Color(hex: 0x606060), Color(hex: 0x56585b)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
        .tint(.blue).accentColor(.blue)
        .ignoresSafeArea(.container, edges: .top)
        .frame(width: 644, height: 700)
        .alert("OpenBendy", isPresented: Binding(get: { prefs.error != nil }, set: { if !$0 { prefs.error = nil } })) {
            Button("OK") { prefs.error = nil }
        } message: { Text(prefs.error ?? "") }
    }
    private func pageIcon(_ page: SettingsPage) -> some View {
        Image(systemName: page.symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
            .frame(width: 24, height: 24).background(page == .appearance ? Color(hex: 0x2499eb) : Color(white: 0.57), in: RoundedRectangle(cornerRadius: 7))
    }
    private func nav(_ page: SettingsPage) -> some View {
        Button { prefs.page = page } label: {
            HStack(spacing: 10) { pageIcon(page); Text(page.rawValue); Spacer() }
                .padding(.horizontal, 9).frame(height: 38)
                .background(prefs.page == page ? Color.white.opacity(0.085) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("nav-\(page.rawValue)")
    }
    private var appearance: some View {
        Group {
            VStack(spacing: 9) {
                MacBookPreview(prefs: prefs)
                Text(prefs.enabled ? "Desktop effect is on · follows your MacBook lid" : prefs.captureStatus)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity).padding(.top, 1)
            HStack(spacing: 10) {
                Text("\(Int(prefs.angle.rounded()))°").monospacedDigit().foregroundStyle(.white.opacity(0.7)).frame(width: 34, alignment: .leading)
                Slider(value: $prefs.manualAngle, in: 5...135).labelsHidden().disabled(prefs.followLid || prefs.playing).accessibilityLabel("Lid angle")
                Toggle("Follow lid", isOn: $prefs.followLid).toggleStyle(.switch).fixedSize().controlSize(.small).disabled(prefs.sensorAngle == nil)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("Style").fontWeight(.semibold).foregroundStyle(.white.opacity(0.65)).padding(.leading, 4)
                HStack(spacing: 8) {
                    ForEach(BendStyle.allCases) { style in
                        Button { prefs.style = style } label: {
                            VStack(spacing: 7) {
                                PreviewEffect(params: .init(angle: 62, clearAngle: 135, perspective: style == .arc || style == .book ? 1 : (style == .silk ? 0 : 0.3), blur: style == .frost ? 0.8 : 0.65, shadow: style == .shade ? 1 : 0.2, style: style))
                                    .aspectRatio(1.58, contentMode: .fit)
                                    .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(prefs.style == style ? Color(hex: 0x00a4ff) : .clear, lineWidth: 2))
                                HStack(spacing: 5) {
                                    Text(style.rawValue)
                                    if prefs.style == style { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x00a4ff)).font(.system(size: 11)) }
                                }.frame(height: 18)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(style.rawValue) style").accessibilityAddTraits(prefs.style == style ? .isSelected : [])
                    }
                }
            }
            VStack(spacing: 0) {
                sliderRow("Perspective", value: $prefs.perspective)
                Divider().overlay(.white.opacity(0.035))
                sliderRow("Variable blur", value: $prefs.blur)
                Divider().overlay(.white.opacity(0.035))
                sliderRow("Shadow", value: $prefs.shadow)
            }.background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Clear at"); Spacer(); Text("\(Int(prefs.clearAngle))°").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: $prefs.clearAngle, in: 60...135, step: 1).accessibilityLabel("Clear angle")
                Text("The desktop settles back when the lid opens past this angle.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.62))
            }.padding(14).background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 13))
            HStack {
                Text(prefs.sensorAngle == nil ? "Manual preview" : "Lid sensor connected").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button("Restore Defaults") { prefs.reset() }.controlSize(.small)
            }
        }
    }
    private func sliderRow(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 13) {
            Text(title).frame(width: 93, alignment: .leading)
            Slider(value: value, in: 0...1).accessibilityLabel(title)
            Text("\(Int((value.wrappedValue * 100).rounded()))%").monospacedDigit().foregroundStyle(.white.opacity(0.66)).frame(width: 40, alignment: .trailing)
        }.padding(.horizontal, 14).frame(height: 45)
    }
    private var general: some View {
        Group {
            VStack(alignment: .leading, spacing: 17) {
                Toggle("Enable desktop effect", isOn: Binding(get: { prefs.enabled }, set: { _ in enable() })).toggleStyle(.switch)
                Text(prefs.captureStatus).foregroundStyle(.secondary).font(.system(size: 12))
                Divider()
                Toggle("Open at login", isOn: $login).toggleStyle(.switch).onChange(of: login) { _, new in
                    do { if new { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { prefs.error = error.localizedDescription; login = SMAppService.mainApp.status == .enabled }
                }
                Toggle("Play sound when the desktop clears", isOn: $prefs.sound).toggleStyle(.switch)
            }.padding(16).background(.black.opacity(0.23), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 14) {
                Text("Screen Recording").fontWeight(.semibold)
                Text("Allow OpenBendy to capture the desktop for the live effect. Frames are processed on this Mac, never saved or uploaded.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                Button("Allow Screen Recording…") {
                    if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }.padding(16).background(.black.opacity(0.23), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 10) {
                Text("Lid sensor").fontWeight(.semibold)
                Text(prefs.sensorStatus).foregroundStyle(.secondary)
                Text("Use the angle slider in Appearance to try the effect at any time.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            }.padding(16).background(.black.opacity(0.23), in: RoundedRectangle(cornerRadius: 13))
            Text("Press Esc to pause the desktop effect. You can also pause it from the menu bar.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
        }
    }
    private var about: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image("OpenBendyBrand").resizable().interpolation(.high).scaledToFit().frame(width: 88, height: 88).padding(.top, 18)
            Text("OpenBendy").font(.system(size: 28, weight: .semibold))
            Link("openbendy.com", destination: URL(string: "https://openbendy.com")!)
            Text("Your desktop bends as you close the lid.").font(.system(size: 15))
            Text("Native SwiftUI, ScreenCaptureKit and Metal.\nBuilt for Apple silicon Macs running macOS 14 or later.").foregroundStyle(.secondary).lineSpacing(5)
            Text("Version 1.0.4").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
