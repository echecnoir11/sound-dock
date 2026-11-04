import SwiftUI
import AppKit
import CoreText

// Design system ported from @@ennuienoir (UI/Theme.swift, UI/Gooey.swift, UI/Components.swift):
// soft grey "dotted paper" ambience, dark gooey bars melting into each other, JetBrains Mono + Helvetica Neue Thin.

// MARK: - Fonts

enum Fonts {
    /// Registers the JetBrains Mono files shipped in Resources/Fonts (falls back to an installed copy or SF Mono).
    static func registerBundled() {
        let dirs = [Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
                    URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Fonts")]
        for case let dir? in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for f in files where f.pathExtension == "ttf" { CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil) }
        }
    }
}

enum Typo {
    static func thin(_ size: CGFloat) -> Font { .custom("HelveticaNeue-Thin", size: size) }
    static func light(_ size: CGFloat) -> Font { .custom("HelveticaNeue-Light", size: size) }
    static func regular(_ size: CGFloat) -> Font { .custom("HelveticaNeue", size: size) }
    static func mono(_ size: CGFloat, _ weight: MonoWeight = .regular) -> Font { .custom("JetBrainsMono-\(weight.rawValue)", size: size) }
    enum MonoWeight: String { case thin = "Thin", light = "Light", regular = "Regular", medium = "Medium" }
}

// MARK: - Palette

struct Palette {
    let bgTop: Color, bgBottom: Color
    let ink: Color, inkSoft: Color, inkFaint: Color
    let line: Color, tile: Color, tileShadow: Color
    let bar: Color, barText: Color, barSoft: Color, barHi: Color
    let isDark: Bool

    static let light = Palette(
        bgTop: Color(white: 0.915), bgBottom: Color(white: 0.845),
        ink: Color(white: 0.06), inkSoft: Color(white: 0.36), inkFaint: Color(white: 0.58),
        line: Color.black.opacity(0.09), tile: Color(white: 0.975), tileShadow: Color.black.opacity(0.13),
        bar: Color(white: 0.075), barText: Color(white: 0.95), barSoft: Color(white: 0.55), barHi: Color.white.opacity(0.13),
        isDark: false)

    static let dark = Palette(
        bgTop: Color(white: 0.10), bgBottom: Color(white: 0.04),
        ink: Color(white: 0.94), inkSoft: Color(white: 0.62), inkFaint: Color(white: 0.4),
        line: Color.white.opacity(0.10), tile: Color(white: 0.14), tileShadow: Color.black.opacity(0.6),
        bar: Color(white: 0.16), barText: Color(white: 0.95), barSoft: Color(white: 0.55), barHi: Color.white.opacity(0.12),
        isDark: true)

    static let darkKey = "ui.dark"
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.light }
extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    func softShadow(_ p: Palette, radius: CGFloat = 18, y: CGFloat = 8) -> some View {
        shadow(color: p.tileShadow, radius: radius, x: 0, y: y)
    }
}

extension Binding where Value == Float {
    var double: Binding<Double> { Binding<Double>(get: { Double(wrappedValue) }, set: { wrappedValue = Float($0) }) }
}

// MARK: - Pictograms (Resources/Icons, transparent template PNGs)

enum IconLib {
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage? {
        if let i = cache[name] { return i }
        let candidates = [Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Icons"),
                          Bundle.main.url(forResource: name, withExtension: "png"),
                          URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Icons/\(name).png")]
        for case let url? in candidates {
            if let img = NSImage(contentsOf: url) { img.isTemplate = true; cache[name] = img; return img }
        }
        return nil
    }
}

struct Icon: View {
    let name: String
    var fallback = "circle"
    init(_ name: String, fallback: String = "circle") { self.name = name; self.fallback = fallback }
    var body: some View {
        if let img = IconLib.image(name) {
            Image(nsImage: img).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: fallback).resizable().scaledToFit()
        }
    }
}

// MARK: - Labels

/// Small spaced uppercase mono label, e.g. "EDIT / MONTAGE · RHYTHM".
struct MonoLabel: View {
    @Environment(\.palette) private var p
    let text: String
    var size: CGFloat = 9.5
    var color: Color?
    init(_ text: String, size: CGFloat = 9.5, color: Color? = nil) { self.text = text; self.size = size; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(Typo.mono(size)).tracking(size * 0.16).foregroundStyle(color ?? p.inkSoft)
    }
}

/// "// MODE ———" section header.
struct SectionRule: View {
    @Environment(\.palette) private var p
    let title: String
    var body: some View {
        HStack(spacing: 10) {
            MonoLabel("// " + title, size: 9)
            Rectangle().fill(p.line).frame(height: 1)
        }
    }
}

// MARK: - Gooey bars (metaball bridges between pills)

struct GooeyBlob: Equatable { var rect: CGRect; var radius: CGFloat? }

private struct GooeySegmentKey: PreferenceKey {
    static var defaultValue: [GooeyBlob] = []
    static func reduce(value: inout [GooeyBlob], nextValue: () -> [GooeyBlob]) { value.append(contentsOf: nextValue()) }
}

extension View {
    /// Marks this view as one blob of the surrounding `GooeyContainer` (capsule by default, or a rounded rect).
    func gooeySegment(cornerRadius: CGFloat? = nil) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: GooeySegmentKey.self, value: [GooeyBlob(rect: g.frame(in: .named("gooey")), radius: cornerRadius)])
        })
    }
}

struct GooeyContainer<Content: View>: View {
    var color: Color
    var blur: CGFloat = 8
    @ViewBuilder var content: Content
    @Environment(\.palette) private var p

    var body: some View {
        let pad: CGFloat = 24
        content
            .coordinateSpace(name: "gooey")
            .backgroundPreferenceValue(GooeySegmentKey.self) { frames in
                Canvas { ctx, _ in
                    ctx.addFilter(.alphaThreshold(min: 0.5, color: color))
                    ctx.addFilter(.blur(radius: blur))
                    ctx.drawLayer { layer in
                        for b in frames {
                            let rr = b.rect.offsetBy(dx: pad, dy: pad)
                            let cap = min(rr.height, rr.width) / 2
                            layer.fill(Path(roundedRect: rr, cornerRadius: min(cap, b.radius ?? cap), style: .continuous), with: .color(.black))
                        }
                    }
                }
                .padding(-pad)
                .shadow(color: p.tileShadow.opacity(1.2), radius: 12, x: 0, y: 6)
                .allowsHitTesting(false)
            }
    }
}

/// Text / icon button living inside a dark gooey bar, with a soft hover pill.
struct BarButton<Label: View>: View {
    @Environment(\.palette) private var p
    var selected = false
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(selected || hover ? p.barText : p.barText.opacity(0.72))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(selected ? p.barHi.opacity(1.6) : (hover ? p.barHi : .clear)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

/// Round icon button for gooey bars (rail footer reference).
struct RoundBarButton<Label: View>: View {
    @Environment(\.palette) private var p
    var size: CGFloat = 34
    var on = false
    let help: String
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(on ? p.bar : p.barText.opacity(hover ? 1 : 0.75))
                .frame(width: size, height: size)
                .background(Circle().fill(on ? p.barText : (hover ? p.barHi : .clear)).padding(3))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help).accessibilityLabel(help)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

struct BarDivider: View {
    @Environment(\.palette) private var p
    var body: some View { Rectangle().fill(p.barText.opacity(0.14)).frame(width: 1, height: 16) }
}

/// Thin slider for dark bars.
struct BarSlider: View {
    @Environment(\.palette) private var p
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var body: some View {
        GeometryReader { g in
            let f = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(p.barText.opacity(0.2)).frame(height: 2)
                Capsule().fill(p.barText).frame(width: max(0, g.size.width * f), height: 2)
                Circle().fill(p.barText).frame(width: 10, height: 10).offset(x: g.size.width * f - 5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let x = min(1, max(0, v.location.x / max(1, g.size.width)))
                value = range.lowerBound + x * (range.upperBound - range.lowerBound)
            })
        }
        .frame(height: 20)
    }
}

// MARK: - Thin slider (ruler + hollow knob, big thin value)

struct ThinSlider: View {
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    var onReset: () -> Void
    @State private var dragging = false

    private var fraction: Double { (value - range.lowerBound) / (range.upperBound - range.lowerBound) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(Typo.light(12)).foregroundStyle(p.inkSoft)
                Spacer()
                Text(format(value)).font(Typo.thin(20)).monospacedDigit().foregroundStyle(p.ink)
            }
            GeometryReader { geo in
                let w = geo.size.width
                let x = CGFloat(min(1, max(0, fraction))) * w
                ZStack(alignment: .leading) {
                    Canvas { ctx, size in
                        for i in 0...20 {
                            let tx = size.width * CGFloat(i) / 20
                            let h: CGFloat = i % 5 == 0 ? 5 : 2.5
                            ctx.fill(Path(CGRect(x: tx - 0.25, y: size.height / 2 - h / 2, width: 0.5, height: h)), with: .color(p.inkFaint.opacity(0.55)))
                        }
                    }
                    Rectangle().fill(p.line).frame(height: 1)
                    Rectangle().fill(p.ink).frame(width: max(0, x), height: 1.4)
                    Circle().fill(p.tile).overlay(Circle().stroke(p.ink, lineWidth: 1))
                        .frame(width: dragging ? 14 : 11, height: dragging ? 14 : 11)
                        .softShadow(p, radius: 3, y: 1)
                        .offset(x: x - (dragging ? 7 : 5.5))
                }
                .frame(height: 16)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        dragging = true
                        let f = min(1, max(0, g.location.x / max(1, w)))
                        value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in dragging = false })
                .onTapGesture(count: 2) { onReset() }
            }
            .frame(height: 16)
        }
        .opacity(enabled ? 1 : 0.4)
        .animation(.easeOut(duration: 0.12), value: dragging)
        .help("double-clic : valeur par défaut")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { dir in
            let step = (range.upperBound - range.lowerBound) / 20
            value = min(range.upperBound, max(range.lowerBound, value + (dir == .increment ? step : -step)))
        }
    }
}

// MARK: - Pill toggle + chips

struct PillToggle: View {
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isOn.toggle() } } label: {
            HStack(spacing: 8) {
                Text(title).font(Typo.mono(10)).foregroundStyle(p.inkSoft)
                Capsule().fill(isOn ? p.ink : p.line)
                    .frame(width: 30, height: 17)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(p.tile).frame(width: 13, height: 13).softShadow(p, radius: 2, y: 1).padding(2)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(title).accessibilityValue(isOn ? "activé" : "désactivé")
    }
}

/// Small capsule chip ("apply", "reset" in ennuienoir).
struct Chip: View {
    @Environment(\.palette) private var p
    let title: String
    var on = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(Typo.mono(10.5))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(on ? p.tile : p.ink)
                .background(Capsule().fill(on ? p.ink : p.line.opacity(0.6)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The dotted radial ring, slowly turning while audio runs.
struct SpinningRing: View {
    var spinning: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: spinning ? 1.0 / 20 : 3600)) { tl in
            Icon("ring").rotationEffect(.radians(spinning ? tl.date.timeIntervalSinceReferenceDate * 0.4 : 0))
        }
        .allowsHitTesting(false)
    }
}
