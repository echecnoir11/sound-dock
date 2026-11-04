import Foundation
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import CoreAudio
import AudioGuard

func safely(_ operation: () throws -> Void) throws {
    var swiftError: Error?
    let exception = SDRunSafely { do { try operation() } catch { swiftError = error } }
    if let exception { throw exception }
    if let swiftError { throw swiftError }
}

struct AudioFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func check(_ code: OSStatus, _ action: String) throws {
    if code != noErr { throw AudioFailure(message: "\(action) (CoreAudio \(code)).") }
}
struct Device: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let inputs: Int
    let outputs: Int
    let transport: UInt32
    var isBlackHole: Bool { name.lowercased().contains("blackhole") }
    var isPhysical: Bool { !isBlackHole && transport != kAudioDeviceTransportTypeAggregate && transport != kAudioDeviceTransportTypeVirtual }
}
enum Hardware {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func number(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var a = address(selector), value: UInt32 = 0, size = UInt32(4)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value)
        return value
    }
    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var a = address(selector)
        let storage = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        storage.initialize(to: nil)
        defer { storage.deinitialize(count: 1); storage.deallocate() }
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(id, &a, 0, nil, &size, storage)
        return status == noErr ? (storage.pointee as String? ?? "") : ""
    }
    static func channels(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
        var a = address(kAudioDevicePropertyStreamConfiguration, scope), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
    static func devices() -> [Device] {
        var a = address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { return [] }
        return ids.map { Device(id: $0, uid: string($0, kAudioDevicePropertyDeviceUID), name: string($0, kAudioObjectPropertyName), inputs: channels($0, kAudioObjectPropertyScopeInput), outputs: channels($0, kAudioObjectPropertyScopeOutput), transport: number($0, kAudioDevicePropertyTransportType)) }
    }
    static var defaultOutput: AudioDeviceID { number(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) }
    static func setDefault(_ id: AudioDeviceID) throws {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice), value = id
        try check(AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value), "Changer la sortie système")
    }
    static func isMuted(_ id: AudioDeviceID) -> Bool {
        var a = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(id, &a) else { return false }
        var value: UInt32 = 0, size: UInt32 = 4
        return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr && value != 0
    }
    static func unmute(_ id: AudioDeviceID) throws {
        var a = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(id, &a) else { return }
        var value: UInt32 = 0
        try check(AudioObjectSetPropertyData(id, &a, 0, nil, 4, &value), "Réactiver la sortie")
    }
    static func unitDevice(_ unit: AudioUnit) -> AudioDeviceID {
        var value: AudioDeviceID = 0, size: UInt32 = 4
        AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &value, &size)
        return value
    }
    static func rate(_ id: AudioDeviceID) -> Double {
        var a = address(kAudioDevicePropertyNominalSampleRate), v: Double = 0, size = UInt32(8)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v)
        return v
    }
    static func setRate(_ id: AudioDeviceID, _ rate: Double) throws {
        var a = address(kAudioDevicePropertyNominalSampleRate), value = rate
        try check(AudioObjectSetPropertyData(id, &a, 0, nil, 8, &value), "Aligner la fréquence audio")
    }

}
struct EffectSettings: Equatable {
    var bass: Float = 0, low: Float = 0, mid: Float = 0, high: Float = 0
    var pitch: Float = 0, reverb: Float = 0, volume: Float = 1, speed: Float = 1
    var bypass = false
}
final class Effects {
    private var transitionTimer: Timer?
    deinit { transitionTimer?.invalidate() }
    func cancelTransitions() { transitionTimer?.invalidate(); transitionTimer = nil }
    let eq = AVAudioUnitEQ(numberOfBands: 4)
    let pitch = AVAudioUnitTimePitch()
    let reverb = AVAudioUnitReverb()
    let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    init() {
        let frequencies: [Float] = [90, 250, 1200, 6000]
        for i in 0..<4 {
            eq.bands[i].frequency = frequencies[i]
            eq.bands[i].bandwidth = 1
            eq.bands[i].filterType = i == 0 ? .lowShelf : (i == 3 ? .highShelf : .parametric)
            eq.bands[i].bypass = false
        }
        pitch.rate = 1
        reverb.loadFactoryPreset(.mediumHall)
    }
    func attach(to engine: AVAudioEngine) {
        [eq, pitch, reverb, limiter].forEach { engine.attach($0) }
    }
    func connect(_ engine: AVAudioEngine, source: AVAudioNode, format: AVAudioFormat) {
        engine.connect(source, to: eq, format: format)
        engine.connect(eq, to: pitch, format: format)
        engine.connect(pitch, to: reverb, format: format)
        engine.connect(reverb, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
    }
    func apply(_ s: EffectSettings, engine: AVAudioEngine, allowSpeed: Bool = false, smooth: Bool = false) {
        cancelTransitions()
        eq.bypass = s.bypass
        eq.globalGain = 0
        for i in 1..<4 { eq.bands[i].gain = [s.low, s.mid, s.high][i - 1] }
        pitch.pitch = s.bypass ? 0 : s.pitch * 100
        reverb.wetDryMix = s.bypass ? 0 : s.reverb
        let rate: Float = s.bypass || !allowSpeed ? 1 : min(2, max(0.5, s.speed))
        let bass = eq.bands[0].gain, volume = engine.mainMixerNode.outputVolume, speed = pitch.rate
        guard smooth, engine.isRunning else {
            eq.bands[0].gain = s.bass; engine.mainMixerNode.outputVolume = s.volume; pitch.rate = rate
            return
        }
        guard bass != s.bass || volume != s.volume || speed != rate else { return }
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak engine] timer in
            guard let self, let engine else { timer.invalidate(); return }
            let t = Float(min(1, (ProcessInfo.processInfo.systemUptime - started) / 0.3))
            let eased = t * t * (3 - 2 * t)
            self.eq.bands[0].gain = bass + (s.bass - bass) * eased
            engine.mainMixerNode.outputVolume = volume + (s.volume - volume) * eased
            self.pitch.rate = speed + (rate - speed) * eased
            if t >= 1 { self.cancelTransitions() }
        }
        timer.tolerance = 0.002
        transitionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

}

enum AudioMode: String, CaseIterable { case system = "Système", file = "Fichier" }

/// Existing CoreAudio device inventory, refreshed on the main queue.
final class AudioDeviceWatcher {
    private var address = Hardware.address(kAudioHardwarePropertyDevices)
    private let listener: AudioObjectPropertyListenerBlock
    init(onChange: @escaping () -> Void) {
        listener = { _, _ in onChange() }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }
    deinit { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) }
}

@MainActor final class SoundModel: ObservableObject {
    let presetStore: PresetStore
    let visualizer = VisualizerModel()
    @Published var mode: AudioMode = .system { didSet { stop(message: mode == .file ? "Ouvre un fichier audio pour régler sa vitesse." : "Prêt à connecter BlackHole 2ch.") } }
    @Published var liveSpeed = false {
        didSet {
            guard liveSpeed != oldValue else { return }
            if !liveSpeed { settings.speed = 1 }
            if running && mode == .system { stop(); start() }
        }
    }
    @Published var reserveSeconds: Double = 0
    @Published var reserveProgress: Double = 0
    @Published var buffering = false
    @Published var resyncs: UInt64 = 0
    @Published var fileURL: URL?
    private var player: AVAudioPlayerNode?
    private var capture: OpaquePointer?
    @Published var devices: [Device] = []
    @Published var outputID: AudioDeviceID = 0
    @Published var running = false
    @Published var busy = false
    @Published var inputLevel: Float = 0
    @Published var outputLevel: Float = 0
    @Published var signalSummary = ""
    @Published var outputMuted = false
    @Published var status = "Prêt à connecter BlackHole 2ch."
    @Published var smoothTransitions = UserDefaults.standard.object(forKey: "smoothTransitions.enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(smoothTransitions, forKey: "smoothTransitions.enabled")
            applySettings()
        }
    }
    @Published var settings = EffectSettings() { didSet { applySettings() } }
    private func applySettings() {
        if let engine { effects?.apply(settings, engine: engine, allowSpeed: mode == .file || liveSpeed, smooth: smoothTransitions) }
    }
    private var engine: AVAudioEngine?
    private var effects: Effects?
    private var aggregate: AudioDeviceID = 0
    private var routeSource: AudioDeviceID = 0
    private var previousOutput: AudioDeviceID = 0
    private var configurationObserver: NSObjectProtocol?
    private var healthTimer: Timer?
    private var deviceWatcher: AudioDeviceWatcher?
    private var switchingOutput = false
    var sources: [Device] { devices.filter { $0.isBlackHole && $0.inputs == 2 && $0.outputs == 2 } }
    var outputs: [Device] { devices.filter { $0.isPhysical && $0.outputs >= 2 } }
    init(presetStore: PresetStore = PresetStore()) {
        self.presetStore = presetStore; refresh(); recoverRoute()
        deviceWatcher = AudioDeviceWatcher { [weak self] in self?.refresh() }
    }
    func applyPreset(_ preset: AudioPreset) {
        guard preset.isValid else { return }
        settings = preset.applying(to: settings)
    }
    func refresh() {
        devices = Hardware.devices()
        if running && mode == .system && !sources.contains(where: { $0.id == routeSource }) {
            stop(message: "Entrée BlackHole déconnectée. Traitement arrêté.")
        }
        if !outputs.contains(where: { $0.id == outputID }) {
            if running { stop(message: "Sortie déconnectée. Choisis une sortie puis relance la lecture.") }
            outputID = outputs.first(where: { $0.id == Hardware.defaultOutput })?.id ?? outputs.first?.id ?? 0
        }
    }
    func selectOutput(_ id: AudioDeviceID) {
        guard id != outputID, !busy else { return }
        guard let target = outputs.first(where: { $0.id == id }) else { status = "Cette sortie n’est plus disponible."; refresh(); return }
        guard running else { outputID = id; return }
        if mode == .system {
            // The aggregate's clock belongs to the physical output. Reuse the
            // established stop/start route, never run two engines in parallel.
            stop(); outputID = id; start()
        } else if let engine {
            switchingOutput = true
            defer { switchingOutput = false }
            do {
                try safely { try engine.outputNode.auAudioUnit.setDeviceID(id) }
                guard engine.outputNode.auAudioUnit.deviceID == id else { throw AudioFailure(message: "La sortie demandée n’a pas pu être sélectionnée.") }
                outputID = id
                if !engine.isRunning || player?.isPlaying != true {
                    stop(message: "Sortie modifiée. Relance le fichier sur cette sortie.")
                } else { status = "Lecture → \(target.name)" }
            } catch { stop(message: error.localizedDescription); refresh() }
        }
    }
    private func handleConfigurationChange(_ changedEngine: AVAudioEngine) {
        guard engine === changedEngine, !switchingOutput else { return }
        if changedEngine.isRunning && changedEngine.outputNode.auAudioUnit.deviceID == outputID && (mode == .system || player?.isPlaying == true) { return }
        stop(message: "Configuration audio modifiée. Choisis ta sortie puis relance la lecture.")
    }
    func recoverRoute() {
        guard let uid = UserDefaults.standard.string(forKey: "restoreOutputUID") else { return }
        if let original = devices.first(where: { $0.uid == uid }), devices.first(where: { $0.id == Hardware.defaultOutput })?.isBlackHole == true {
            do { try Hardware.setDefault(original.id); UserDefaults.standard.removeObject(forKey: "restoreOutputUID"); status = "Sortie audio restaurée après interruption." }
            catch { status = error.localizedDescription }
        }
    }
    func toggle() {
        if running { stop(message: mode == .file ? "Lecture arrêtée." : "Traitement arrêté. Sortie habituelle restaurée."); return }
        guard !busy else { return }
        if mode == .file { startFile(); return }
        refresh()
        guard !sources.isEmpty, !outputs.isEmpty else { status = "Installe BlackHole 2ch puis actualise les périphériques. Consulte le guide."; return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: start(); return
        case .denied, .restricted:
            status = "Autorise ++sound@dock dans Réglages Système → Confidentialité → Microphone."
            return
        case .notDetermined: break
        @unknown default: status = "Autorisation audio inconnue."; return
        }
        busy = true
        AVCaptureDevice.requestAccess(for: .audio) { allowed in
            DispatchQueue.main.async {
                self.busy = false
                if allowed && self.mode == .system { self.start() } else { self.status = "Autorise ++sound@dock dans Réglages Système → Confidentialité → Microphone." }
            }
        }
    }
    func unmuteOutput() {
        do { try Hardware.unmute(outputID); outputMuted = Hardware.isMuted(outputID) }
        catch { status = error.localizedDescription }
    }
    func chooseFile() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.audio]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        picker.message = "Choisir un fichier audio — l’original reste intact."
        if picker.runModal() == .OK, let url = picker.url {
            stop(message: "Prêt à lire : \(url.lastPathComponent)")
            fileURL = url
        }
    }
    func startFile() {
        refresh()
        guard let url = fileURL else { status = "Ouvre d’abord un fichier audio."; return }
        guard let target = outputs.first(where: { $0.id == outputID }) else { status = "Choisis une sortie stéréo physique."; return }
        do {
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0, (1...2).contains(file.processingFormat.channelCount) else {
                throw AudioFailure(message: "Choisis un fichier mono ou stéréo non vide.")
            }
            let e = AVAudioEngine(), fx = Effects(), node = AVAudioPlayerNode()
            engine = e; effects = fx; player = node
            try e.outputNode.auAudioUnit.setDeviceID(target.id)
            e.attach(node); fx.attach(to: e)
            fx.connect(e, source: node, format: file.processingFormat)
            fx.apply(settings, engine: e, allowSpeed: true)
            node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak e] _ in
                // Leave the audio callback before stopping the player to avoid a deadlock.
                DispatchQueue.main.async {
                    guard let self, let e, self.engine === e, self.running else { return }
                    self.stop(message: "Lecture terminée. Le fichier original est intact.")
                }
            }
            let meter = visualizer
            e.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in meter.capture(buffer) }
            try safely { e.prepare(); try e.start() }; node.play()
            visualizer.start()
            running = true; status = "Lecture → \(target.name)"
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: e, queue: .main) { [weak self, weak e] _ in
                DispatchQueue.main.async { if let e { self?.handleConfigurationChange(e) } }
            }
        } catch { stop(message: error.localizedDescription) }
    }
    func start() {
        refresh()
        guard let source = sources.first, let target = outputs.first(where: { $0.id == outputID }) else {
            status = "BlackHole 2ch et une sortie stéréo sont nécessaires."; return
        }
        do {
            let rate = Hardware.rate(target.id)
            guard rate >= 44100, rate <= 96000 else { throw AudioFailure(message: "Choisis une sortie à 44,1, 48 ou 96 kHz dans Configuration audio et MIDI.") }
            try Hardware.setRate(source.id, rate)
            let descriptor: [String: Any] = [
                kAudioAggregateDeviceNameKey: "++sound@dock • traitement",
                kAudioAggregateDeviceUIDKey: "audio.sounddock.aggregate.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: target.uid,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: source.uid, kAudioSubDeviceDriftCompensationKey: 1],
                    [kAudioSubDeviceUIDKey: target.uid, kAudioSubDeviceDriftCompensationKey: 0]
                ]
            ]
            try check(AudioHardwareCreateAggregateDevice(descriptor as CFDictionary, &aggregate), "Créer le routage privé")
            guard Hardware.channels(aggregate, kAudioObjectPropertyScopeInput) >= 2, Hardware.channels(aggregate, kAudioObjectPropertyScopeOutput) == source.outputs + target.outputs else { throw AudioFailure(message: "Le périphérique agrégé n’est pas prêt. Réessaie après quelques secondes.") }
            previousOutput = Hardware.defaultOutput; routeSource = source.id
            if let original = devices.first(where: { $0.id == previousOutput }), !original.isBlackHole {
                UserDefaults.standard.set(original.uid, forKey: "restoreOutputUID")
            } else { previousOutput = target.id; UserDefaults.standard.set(target.uid, forKey: "restoreOutputUID") }
            try Hardware.setDefault(source.id)
            let e = AVAudioEngine(), fx = Effects()
            engine = e; effects = fx
            // Render to the selected physical device. Capture runs in its own HAL
            // unit on the drift-corrected aggregate; AVAudioEngine never opens a mic.
            try e.outputNode.auAudioUnit.setDeviceID(target.id)
            var captureError: NSError?
            guard let input = SDCaptureCreate(aggregate, rate, &captureError) else {
                throw captureError ?? AudioFailure(message: "Entrée BlackHole indisponible.") as NSError
            }
            capture = input
            if liveSpeed && !SDCaptureConfigureBuffer(input, rate, 30, 60) {
                throw AudioFailure(message: "Impossible de préparer la réserve de 30 secondes.")
            }
            buffering = liveSpeed
            guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { throw AudioFailure(message: "Format stéréo indisponible.") }
            let sourceNode = AVAudioSourceNode(format: format) { silence, _, frames, buffers in
                SDCaptureRead(input, frames, buffers)
                silence.pointee = false
                return noErr
            }
            e.attach(sourceNode)
            fx.attach(to: e); fx.connect(e, source: sourceNode, format: format); fx.apply(settings, engine: e, allowSpeed: liveSpeed)
            let meter = visualizer
            e.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
                SDCaptureMarkOutput(input, buffer.frameLength, buffer.audioBufferList)
                meter.capture(buffer)
            }
            try check(SDCaptureStart(input), "Démarrer la capture BlackHole")
            try safely { e.prepare(); try e.start() }
            guard e.outputNode.auAudioUnit.deviceID == target.id else {
                throw AudioFailure(message: "La sortie du moteur ne correspond pas à la sortie choisie. Connexion annulée.")
            }
            visualizer.start()
            running = true; status = "En direct → \(target.name)"
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: e, queue: .main) { [weak self, weak e] _ in
                DispatchQueue.main.async {
                    if let e { self?.handleConfigurationChange(e) }
                }
            }
            healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.running else { return }
                    if let capture = self.capture {
                        let levels = SDCaptureGetLevels(capture)
                        self.inputLevel = levels.input; self.outputLevel = levels.output
                        self.reserveSeconds = levels.queuedSeconds; self.reserveProgress = levels.progress
                        self.buffering = levels.buffering; self.resyncs = levels.resyncs
                        self.outputMuted = Hardware.isMuted(self.outputID)
                        if let unit = self.engine?.outputNode.audioUnit {
                            NSLog("SDDEVICE actual=%u expected=%u muted=%d", Hardware.unitDevice(unit), self.outputID, self.outputMuted)
                        }
                        self.signalSummary = levels.error != 0 ? "Erreur de capture \(levels.error)" : self.liveSpeed && levels.buffering ? "Mise en réserve du son — reprise automatique" : levels.input > 0.00001 ? (levels.output > 0.00001 ? "Signal reçu et transmis" : "Signal reçu — sortie silencieuse") : "En attente du son d’une application"
                        NSLog("SDSIGNAL in=%f source=%f out=%f callbacks=%llu captured=%llu rendered=%llu error=%d", levels.input, levels.source, levels.output, levels.callbacks, levels.captured, levels.rendered, levels.error)
                    }
                    if self.engine?.outputNode.auAudioUnit.deviceID != self.outputID {
                        self.stop(message: "Sortie du moteur modifiée. Traitement arrêté pour éviter une boucle.")
                        return
                    }
                    if Hardware.defaultOutput != self.routeSource || self.engine?.isRunning != true {
                        self.stop(message: "Sortie audio modifiée. Traitement arrêté.")
                    }
                }
            }
        } catch { stop(message: error.localizedDescription) }
    }
    func stop(message: String = "Traitement arrêté. Sortie habituelle restaurée.") {
        healthTimer?.invalidate(); healthTimer = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }; configurationObserver = nil
        var restoreFailed = false
        if routeSource != 0, Hardware.defaultOutput == routeSource, previousOutput != 0 {
            do {
                let restore = outputs.first(where: { $0.id == previousOutput })?.id ?? outputs.first?.id
                guard let restore else { throw AudioFailure(message: "Aucune sortie disponible.") }
                try Hardware.setDefault(restore); UserDefaults.standard.removeObject(forKey: "restoreOutputUID")
            } catch { restoreFailed = true }
        }
        inputLevel = 0; outputLevel = 0; signalSummary = ""
        reserveSeconds = 0; reserveProgress = 0; buffering = false; resyncs = 0
        effects?.cancelTransitions()
        player?.stop(); player = nil
        try? safely { engine?.stop() }; engine = nil; effects = nil
        visualizer.stop()
        if let capture { SDCaptureDestroy(capture); self.capture = nil }
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        routeSource = 0; previousOutput = 0; running = false
        status = restoreFailed ? "Restauration impossible : sélectionne ta sortie dans Réglages Système → Son." : message
    }
}
