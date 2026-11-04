import SwiftUI
import AppKit
import CoreText

// UI V2 — @@ennuienoir design system (see Theme.swift). The audio engine is unchanged.

enum WindowOpacity {
    static let key = "window.backgroundOpacity"
    static let defaultValue = 0.88
    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0.7, value)) : defaultValue
    }
}

final class FrostedBackgroundView: NSVisualEffectView {
    private let tint = NSView()
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.cornerRadius = 15; layer?.masksToBounds = true
        tint.frame = bounds; tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        addSubview(tint)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// `dark` follows the ennuienoir light / noir switch: off-white acrylic or near-black acrylic.
    func configure(opacity: Double, reduceTransparency: Bool, dark: Bool = false) {
        let value = WindowOpacity.clamped(opacity)
        let solid = reduceTransparency || value >= 1
        // Only this background view fades; the NSPanel and foreground stay at alpha 1.
        alphaValue = solid ? 1 : value
        state = solid ? .inactive : .active
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let white: CGFloat = dark ? 0.07 : 0.885
        tint.layer?.backgroundColor = NSColor(white: white, alpha: solid ? 1 : 0.78).cgColor
    }
}

struct FrostedGlass: NSViewRepresentable {
    let opacity: Double
    var dark = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func makeNSView(context: Context) -> FrostedBackgroundView {
        let view = FrostedBackgroundView()
        view.configure(opacity: opacity, reduceTransparency: reduceTransparency, dark: dark)
        return view
    }
    func updateNSView(_ view: FrostedBackgroundView, context: Context) {
        view.configure(opacity: opacity, reduceTransparency: reduceTransparency, dark: dark)
    }
}

// MARK: - Presets (dark gooey pill)

private struct PresetControls: View {
    @ObservedObject var model: SoundModel
    @ObservedObject var store: PresetStore
    @Environment(\.palette) private var p
    @State private var selectedID: UUID?
    @State private var editing = false
    @State private var renaming = false
    @State private var name = ""
    @State private var error: String?
    private var selected: AudioPreset? { store.presets.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GooeyContainer(color: p.bar) {
                HStack(spacing: 5) {
                    Menu {
                        if store.presets.isEmpty { Text("Aucun preset enregistré") }
                        ForEach(store.presets) { preset in
                            Button(preset.name) { model.applyPreset(preset); selectedID = preset.id; error = nil }
                        }
                        Divider()
                        Button("Enregistrer les réglages…") { beginEdit(rename: false) }
                        Button("Renommer…") { beginEdit(rename: true) }.disabled(selected == nil)
                        Button("Supprimer", role: .destructive) {
                            guard let selectedID else { return }
                            do { try store.delete(id: selectedID); self.selectedID = nil; error = nil }
                            catch { self.error = error.localizedDescription }
                        }.disabled(selected == nil)
                    } label: {
                        HStack(spacing: 8) {
                            Text("PRESET").font(Typo.mono(8)).tracking(1.3).foregroundStyle(p.barSoft)
                            Text((selected?.name ?? "aucun") + (selected.map { $0.matches(model.settings) ? "" : " *" } ?? ""))
                                .font(Typo.light(13)).lineLimit(1).foregroundStyle(p.barText)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(p.barText.opacity(0.7))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .contentShape(Capsule())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                    .frame(maxWidth: .infinity)
                    .gooeySegment()

                    RoundBarButton(size: 36, help: "Enregistrer vitesse, basses et volume") { beginEdit(rename: false) } label: {
                        Image(systemName: "plus").font(.system(size: 13, weight: .light))
                    }
                    .gooeySegment()
                }
            }
            if selected?.speed != nil, selected?.speed != 1, model.mode == .system, !model.liveSpeed {
                Text("vitesse mémorisée : active le mode réserve pour l’entendre.").font(Typo.mono(8.5)).foregroundStyle(p.inkFaint)
            }
            if let message = error ?? store.errorMessage {
                Text(message).font(Typo.mono(9)).foregroundStyle(p.ink)
            }
        }
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                MonoLabel(renaming ? "Renommer le preset" : "Enregistrer un preset")
                TextField("nom", text: $name).textFieldStyle(.plain).font(Typo.thin(20)).foregroundStyle(p.ink).onSubmit(save)
                    .overlay(alignment: .bottom) { Rectangle().fill(p.ink).frame(height: 1).offset(y: 3) }
                if let error { Text(error).font(Typo.mono(9)).foregroundStyle(p.ink).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Chip(title: "annuler") { editing = false }
                    Spacer()
                    Chip(title: "enregistrer", on: true, action: save).keyboardShortcut(.defaultAction)
                }
            }
            .padding(18).frame(width: 260)
            .background(LinearGradient(colors: [p.bgTop, p.bgBottom], startPoint: .top, endPoint: .bottom))
            .environment(\.palette, p)
            .preferredColorScheme(p.isDark ? .dark : .light)
        }
    }
    private func beginEdit(rename: Bool) {
        renaming = rename; name = rename ? selected?.name ?? "" : ""; error = nil; editing = true
    }
    private func save() {
        do {
            if renaming, let selectedID { try store.rename(id: selectedID, name: name) }
            else { selectedID = try store.save(name: name, settings: model.settings).id }
            editing = false; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Small pieces

/// Thin level line (ENTRÉE / SORTIE meters).
private struct LevelLine: View {
    @Environment(\.palette) private var p
    let title: String
    let level: Float
    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased()).font(Typo.mono(8)).tracking(1.2)
                .foregroundStyle(level > 0.00001 ? p.ink : p.inkFaint)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(p.line).frame(height: 1)
                    Rectangle().fill(p.ink).frame(width: g.size.width * CGFloat(min(1, max(0, level))), height: 1.6)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 10)
        }
    }
}

private struct PanelHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Panel

struct DockView: View {
    @ObservedObject var model: SoundModel
    @AppStorage(Palette.darkKey) private var dark = false
    var body: some View {
        DockContent(model: model, dark: $dark)
            .environment(\.palette, dark ? .dark : .light)
    }
}

private struct DockContent: View {
    @ObservedObject var model: SoundModel
    @Binding var dark: Bool
    @Environment(\.palette) private var p
    @State private var pinned = true
    @State private var expanded = false
    @State private var showingAppearance = false
    @AppStorage(WindowOpacity.key) private var backgroundOpacity = WindowOpacity.defaultValue

    private let defaults = EffectSettings()
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.0" }

    private var stateTitle: String {
        guard model.running else { return model.busy ? "autorisation…" : "en attente" }
        if model.mode == .file { return "lecture fichier" }
        if model.liveSpeed { return model.buffering ? "chargement" : "direct différé" }
        return "live audio"
    }
    private var effectiveRate: Double {
        Double(model.settings.bypass || (model.mode == .system && !model.liveSpeed) ? Float(1) : model.settings.speed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            titleBlock
            modeSwitch
            PresetControls(model: model, store: model.presetStore)
            visualizer
            sourceOptions
            effects
            output
            transport
            footer
        }
        .padding(18).frame(width: 354).fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(p.ink)
        .background(GeometryReader { proxy in Color.clear.preference(key: PanelHeight.self, value: proxy.size.height) })
        .onPreferenceChange(PanelHeight.self) { height in
            guard height > 0, let window = NSApp.windows.first(where: { $0 is SoundPanel }), abs(window.frame.height - height) > 1 else { return }
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                var frame = window.frame
                frame.origin.y += frame.height - height; frame.size.height = height
                window.setFrame(frame, display: true)
            }
        }
        .background(FrostedGlass(opacity: backgroundOpacity, dark: dark))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(p.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .tint(p.ink)
        .preferredColorScheme(dark ? .dark : .light)
    }

    // logo bubble melting into the name pill, round window buttons on the right (rail header reference)
    private var header: some View {
        GooeyContainer(color: p.bar) {
            HStack(spacing: 5) {
                ZStack {
                    SpinningRing(spinning: model.running).opacity(0.35)
                    if let url = Bundle.main.url(forResource: "BrandLogo", withExtension: "png"), let logo = NSImage(contentsOf: url) {
                        Image(nsImage: logo).renderingMode(.template).resizable().scaledToFit().frame(width: 26, height: 17)
                    } else {
                        Image(systemName: "waveform").font(.system(size: 14, weight: .light))
                    }
                }
                .frame(width: 46, height: 46)
                .foregroundStyle(p.barText)
                .accessibilityLabel("Logo DVD Audio")
                .gooeySegment()

                HStack(spacing: 8) {
                    Text("++sound@dock").font(Typo.light(13)).lineLimit(1)
                    Circle().fill(p.barText).frame(width: 4, height: 4)
                        .shadow(color: p.barText.opacity(0.9), radius: 3)
                        .opacity(model.running ? 1 : 0.25)
                }
                .foregroundStyle(p.barText)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .gooeySegment()

                Spacer(minLength: 4)

                HStack(spacing: 0) {
                    RoundBarButton(size: 30, on: showingAppearance, help: "Opacité du fond") { showingAppearance.toggle() } label: {
                        Image(systemName: "circle.lefthalf.filled").font(.system(size: 11))
                    }
                    .popover(isPresented: $showingAppearance, arrowEdge: .bottom) { appearancePopover }
                    RoundBarButton(size: 30, on: pinned, help: "Garder au premier plan") {
                        pinned.toggle(); NSApp.windows.first(where: { $0 is SoundPanel })?.level = pinned ? .floating : .normal
                    } label: { Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 10)) }
                    RoundBarButton(size: 30, help: "Masquer — réouvrir depuis la barre des menus") { NSApp.keyWindow?.orderOut(nil) } label: {
                        Image(systemName: "minus").font(.system(size: 11))
                    }
                }
                .padding(.horizontal, 3)
                .frame(height: 36)
                .gooeySegment()
            }
        }
    }

    private var appearancePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            MonoLabel("Apparence")
            ThinSlider(label: "opacité du fond",
                       value: Binding(get: { WindowOpacity.clamped(backgroundOpacity) }, set: { backgroundOpacity = WindowOpacity.clamped(($0 * 100).rounded() / 100) }),
                       range: 0.7...1, format: { "\(Int(($0 * 100).rounded()))%" }) { backgroundOpacity = WindowOpacity.defaultValue }
            HStack {
                Text("light / noir").font(Typo.light(12)).foregroundStyle(p.inkSoft)
                Spacer()
                Chip(title: "light", on: !dark) { withAnimation(.easeInOut(duration: 0.3)) { dark = false } }
                Chip(title: "noir", on: dark) { withAnimation(.easeInOut(duration: 0.3)) { dark = true } }
            }
        }
        .padding(18).frame(width: 260)
        .background(LinearGradient(colors: [p.bgTop, p.bgBottom], startPoint: .top, endPoint: .bottom))
        .environment(\.palette, p)
        .preferredColorScheme(p.isDark ? .dark : .light)
    }

    // "EDIT / MONTAGE · RHYTHM · BEAT" + big thin title (inspector reference)
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel("Sound / Dock · stereo → fx")
            Text(stateTitle).font(Typo.thin(34)).foregroundStyle(p.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .animation(.easeOut(duration: 0.2), value: stateTitle)
            Text(model.status).font(Typo.mono(10)).foregroundStyle(p.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // VIDEO ⇄ LAB switch reference
    private var modeSwitch: some View {
        GooeyContainer(color: p.bar) {
            HStack(spacing: 3) {
                ForEach(AudioMode.allCases, id: \.self) { mode in
                    let on = model.mode == mode
                    Button { if !model.busy { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.mode = mode } } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode == .system ? "dot.radiowaves.left.and.right" : "doc").font(.system(size: 10, weight: on ? .medium : .light))
                            Text(mode.rawValue.lowercased()).font(Typo.mono(10.5, on ? .medium : .regular))
                        }
                        .foregroundStyle(on ? p.bar : p.barText.opacity(0.65))
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(Capsule().fill(on ? p.barText : .clear))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Source " + mode.rawValue)
                }
            }
            .padding(4)
            .gooeySegment()
        }
    }

    // the viewer tile, with the 16 × 10 meter in ink
    private var visualizer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MonoLabel(model.mode == .file ? (model.fileURL?.lastPathComponent ?? "fichier") : "blackhole 2ch", size: 8.5)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                MonoLabel(String(format: "rate %.2f×", effectiveRate), size: 8.5)
            }
            MiniVisualizer(model: model.visualizer, color: p.ink)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(p.tile.opacity(p.isDark ? 0.6 : 0.45)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(p.line, lineWidth: 1))
    }

    @ViewBuilder private var sourceOptions: some View {
        if model.mode == .file {
            Button { model.chooseFile() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder").font(.system(size: 11, weight: .light))
                    Text(model.fileURL?.lastPathComponent ?? "ouvrir un audio…").font(Typo.mono(10.5)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(p.ink)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(p.line.opacity(0.6)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        if model.mode == .system {
            PillToggle(title: "vitesse en direct · réserve 30 s", isOn: $model.liveSpeed).disabled(model.busy)
        }
        if model.mode == .system && model.liveSpeed {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.buffering ? String(format: "chargement de la réserve… %.0f%%", model.reserveProgress * 100) : String(format: "réserve : %.1f s / 60 s", model.reserveSeconds))
                    .foregroundStyle(p.ink)
                if model.buffering { LevelLine(title: "réserve", level: Float(model.reserveProgress)) }
                Text("accélérer vide la réserve ; ralentir augmente le retard.").foregroundStyle(p.inkFaint)
                if model.resyncs > 0 { Text("réserve pleine : recalage du direct (\(model.resyncs)).").foregroundStyle(p.ink) }
            }
            .font(Typo.mono(9))
        }
    }

    private var effects: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionRule(title: "effets")
            Group {
                if model.mode == .file || model.liveSpeed {
                    ThinSlider(label: "vitesse", value: $model.settings.speed.double, range: 0.5...2,
                               format: { String(format: "%.2f×", $0) }) { model.settings.speed = defaults.speed }
                }
                ThinSlider(label: "bass boost", value: $model.settings.bass.double, range: 0...12,
                           format: { String(format: "%.0f dB", $0) }) { model.settings.bass = defaults.bass }
                ThinSlider(label: "pitch", value: $model.settings.pitch.double, range: -12...12,
                           format: { String(format: "%+.0f st", $0) }) { model.settings.pitch = defaults.pitch }
                ThinSlider(label: "reverb", value: $model.settings.reverb.double, range: 0...45,
                           format: { String(format: "%.0f%%", $0) }) { model.settings.reverb = defaults.reverb }
            }
            .disabled(model.settings.bypass)

            HStack(spacing: 14) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                    HStack(spacing: 5) {
                        MonoLabel("// égaliseur", size: 9)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 7, weight: .semibold)).foregroundStyle(p.inkSoft)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                PillToggle(title: "lissage", isOn: $model.smoothTransitions)
                    .help("Transitions de 300 ms pour basses, volume et vitesse lorsqu’elle est active.")
                PillToggle(title: "bypass", isOn: $model.settings.bypass)
            }
            if expanded {
                VStack(spacing: 14) {
                    ThinSlider(label: "250 Hz", value: $model.settings.low.double, range: -12...12,
                               format: { String(format: "%+.0f dB", $0) }) { model.settings.low = defaults.low }
                    ThinSlider(label: "1.2 kHz", value: $model.settings.mid.double, range: -12...12,
                               format: { String(format: "%+.0f dB", $0) }) { model.settings.mid = defaults.mid }
                    ThinSlider(label: "6 kHz", value: $model.settings.high.double, range: -12...12,
                               format: { String(format: "%+.0f dB", $0) }) { model.settings.high = defaults.high }
                }
                .disabled(model.settings.bypass)
            }
        }
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SectionRule(title: "sortie")
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10)).foregroundStyle(p.inkSoft)
                }
                .buttonStyle(.plain).help("Actualiser les périphériques").accessibilityLabel("Actualiser les périphériques")
            }
            Menu {
                if model.outputs.isEmpty { Text("Aucune sortie disponible") }
                ForEach(model.outputs) { device in
                    Button { model.selectOutput(device.id) } label: {
                        if device.id == model.outputID { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hifispeaker").font(.system(size: 10, weight: .light))
                    Text(model.outputs.first(where: { $0.id == model.outputID })?.name ?? "aucune sortie disponible")
                        .font(Typo.mono(10.5)).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(p.ink)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(p.line.opacity(0.6)))
                .contentShape(Capsule())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .disabled(model.busy)
            .accessibilityLabel("Sortie")

            if model.running && model.mode == .system {
                HStack(spacing: 14) {
                    LevelLine(title: "entrée", level: model.inputLevel)
                    LevelLine(title: "sortie", level: model.outputLevel)
                }
                if model.outputMuted {
                    Chip(title: "sortie en sourdine — réactiver", on: true) { model.unmuteOutput() }
                }
                if !model.signalSummary.isEmpty {
                    Text(model.signalSummary).font(Typo.mono(9)).foregroundStyle(p.inkSoft)
                }
            }
        }
    }

    // transport bar: round play button melting into the action pill, then volume (bottom bar reference)
    private var transport: some View {
        GooeyContainer(color: p.bar) {
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Button { model.toggle() } label: {
                        Image(systemName: model.running ? "stop.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(model.running ? p.barText : p.bar)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(model.running ? .clear : p.barText).padding(5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain).disabled(model.busy)
                    .accessibilityLabel(model.running ? "Arrêter" : "Démarrer")
                    .gooeySegment()

                    Button { model.toggle() } label: {
                        HStack(spacing: 8) {
                            Text(model.busy ? "autorisation…" : model.running ? "arrêter" : (model.mode == .file ? "lire le fichier" : "connecter le son"))
                                .font(Typo.light(14))
                            Spacer(minLength: 4)
                            BarDivider()
                            Text(String(format: "%.2f×", effectiveRate)).font(Typo.thin(19)).monospacedDigit()
                        }
                        .foregroundStyle(p.barText)
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).disabled(model.busy)
                    .help("Vitesse en direct avec réserve de 30 secondes ; des recharges ou recalages peuvent interrompre la musique.")
                    .gooeySegment()
                }
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.2").font(.system(size: 11, weight: .light)).foregroundStyle(p.barText.opacity(0.8))
                    BarSlider(value: $model.settings.volume.double)
                        .accessibilityLabel("Volume de sortie")
                    Text("\(Int(model.settings.volume * 100))").font(Typo.mono(10)).monospacedDigit()
                        .foregroundStyle(p.barText).frame(width: 26, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .gooeySegment()
            }
        }
    }

    // round buttons melting together + version pill (rail footer reference)
    private var footer: some View {
        GooeyContainer(color: p.bar) {
            HStack(spacing: 5) {
                RoundBarButton(help: "Guide d’installation") { AppDelegate.openGuide() } label: { Text("?").font(Typo.mono(12, .medium)) }
                    .gooeySegment()
                RoundBarButton(help: "Reset des effets") { model.settings = EffectSettings() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                }
                .gooeySegment()
                RoundBarButton(help: "light / noir") { withAnimation(.easeInOut(duration: 0.3)) { dark.toggle() } } label: {
                    Image(systemName: dark ? "moon" : "sun.max").font(.system(size: 11))
                }
                .gooeySegment()
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text("v\(version)").font(Typo.mono(8.5)).foregroundStyle(p.barText.opacity(0.35))
                    Icon("heart").frame(width: 16, height: 12).foregroundStyle(p.barText.opacity(0.45))
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .gooeySegment()
            }
        }
    }
}

// MARK: - App

final class SoundPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: SoundPanel!
    var model: SoundModel!
    var statusItem: NSStatusItem!
    static func openGuide() {
        if let url = Bundle.main.url(forResource: "Guide", withExtension: "html") { NSWorkspace.shared.open(url) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Fonts.registerBundled()
        model = SoundModel()
        panel = SoundPanel(contentRect: NSRect(x: 0, y: 0, width: 354, height: 520), styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "++sound@dock"
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.level = .floating
        panel.isMovableByWindowBackground = true; panel.backgroundColor = .clear; panel.isOpaque = false; panel.alphaValue = 1; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: DockView(model: model))
        panel.setContentSize(panel.contentView!.fittingSize)
        panel.center()
        panel.setFrameAutosaveName("SoundDockPanel")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "++sound@dock")
        let menu = NSMenu()
        menu.addItem(withTitle: "Afficher ++sound@dock", action: #selector(show), keyEquivalent: "")
        menu.addItem(withTitle: "Arrêter le traitement", action: #selector(stop), keyEquivalent: "")
        menu.addItem(withTitle: "Guide d’installation", action: #selector(guide), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter ++sound@dock", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        show()
    }
    @objc func show() { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func stop() { model.stop() }
    @objc func guide() { Self.openGuide() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main struct SoundDockMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
